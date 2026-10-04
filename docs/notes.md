# Project Notes: Definitions, Assumptions & Decisions

This file records the definitions used everywhere in the project (Python, SQL and Power BI) and the reasoning behind each data decision.

## 1. Metric definitions

| Metric | Definition | Where |
|---|---|---|
| **GMV / product sales value** | `SUM(order_items.price)`. Excludes freight. All order statuses are included (gross). Canceled/unavailable orders account for only 0.7% of GMV. | `product_value` in `orders_clean.csv`; `GMV` measure |
| **Freight value** | `SUM(order_items.freight_value)` | `freight_value` |
| **Order total value** | product value + freight value for an order | `order_total_value` |
| **Payment value** | `SUM(payments.payment_value)`: what customers paid, including installment interest and vouchers. It is **not** used as "revenue". | `payment_value` |
| **AOV** | GMV ÷ orders with at least one item (98,666). The 775 orders with no items are excluded from the denominator. | |
| **Units sold** | number of rows in `order_items` (each row is one unit) | |
| **Customer** | `customer_unique_id` | |
| **Repeat customer** | a `customer_unique_id` with more than 1 order in the dataset period. All placed orders count. | `customer_type` |
| **Delivered order (for delivery metrics)** | `order_status = 'delivered'` **and** a customer delivery date **and** an estimated delivery date (96,470 orders) | `delivery_status ∈ {on_time, late}` |
| **Late delivery** | delivered date > estimated delivery date, evaluated only for the orders above. Every other order is `not_applicable` (`is_late` = null). | `delivery_status`, `is_late` |
| **Late delivery rate** | late orders ÷ delivered orders (as defined above) = 8.11% | |
| **Delivery days** | purchase timestamp → customer delivery timestamp, in days | `delivery_days` |
| **Review score (order level)** | average `review_score` per order. 551 orders have more than one review. | `review_score` |

The project does not use the word "revenue": Olist's revenue would be its commission, which is not in the data.

## 2. Why `customer_unique_id`
In the Olist data, `customer_id` is created **per order**. Grouping by it gives 99,441 "customers", each with exactly one order, so the dataset would appear to have no repeat customers. `customer_unique_id` identifies the real person. Grouping by it gives 96,096 customers:

| Orders | Customers |
|---|---|
| 1 | 93,099 |
| 2 | 2,745 |
| 3 | 203 |
| 4 | 30 |
| 5–17 | 19 |

The earlier version of `data_cleaning.py` computed `repeat_customer` from `customer_id` and so flagged zero repeat customers. That bug is now fixed.

## 3. Why the late-delivery rule excludes undelivered orders
Before the fix, `late_delivery = delivered_date > estimated_date` produced `False` whenever the delivered date was missing. As a result, ~3,000 shipped, canceled and unavailable orders were counted as "on time", which understated the late rate. Undelivered orders now receive `not_applicable`. The same CASE logic is used in `vw_order_summary` (SQL) and in the Power BI measures.

Estimated delivery dates carry no time of day (midnight). An order delivered later on the estimated day therefore counts as late. Olist's own data behaves the same way, and the rule is applied consistently.

## 4. Data-cleaning decisions (`python/data_cleaning.py`)
| Issue (raw data) | Count | Decision |
|---|---|---|
| Orders with status `delivered` but no delivery date | 8 | Kept, `not_applicable` for delivery metrics. These were previously dropped. Keeping them lets Python totals reconcile with SQL on the raw tables. |
| Orders with no items (mostly unavailable/canceled) | 775 | Kept. Product value is null and they are excluded from AOV. |
| Delivery date present but status not `delivered` | 6 | Excluded from delivery metrics |
| Products with no category | 610 | Category set to `unknown` |
| Categories without English translation | 2 | Portuguese name kept |
| Carrier date earlier than approval date | 1,359 | Kept (timestamp-recording issue; not used in analysis) |
| Payments with 0 installments | 2 | Kept. The values are valid, and the installment buckets start at 1. These were previously dropped. |
| Payments with value 0 | 9 | Kept (vouchers / `not_defined`) |
| Orders with multiple reviews | 551 | Score averaged per order |
| Exact duplicate rows | 0 in all tables | n/a |
| Referential integrity (items→orders/products/sellers, payments/reviews→orders) | 0 orphans | n/a |

Derived files: `orders_clean.csv` (order-level fact with all derived columns) and `customer_segments.csv` (one row per `customer_unique_id`). The remaining cleaned files are the raw tables, plus English categories on products.

## 5. Time window
Orders run from Sep-2016 to Oct-2018, but:
- Sep–Dec 2016 has ~300 orders, with no orders at all in Nov-2016.
- After Aug-2018 there are 20 orders: 19 canceled and 1 shipped. The data extract ends here.

**Monthly trends therefore use Jan-2017 → Aug-2018.** Totals (KPIs) use all data.

## 6. SQL / database assumptions
- PostgreSQL. The scripts were tested on PostgreSQL 18 and use standard features only (`FILTER`, window functions, `PERCENTILE_CONT`, `DATE_TRUNC`).
- `sql/02_load_data.sql` uses client-side `\copy` with paths relative to the project root, so `psql` must be started from the project root.
- SQL runs on the **raw** CSVs, so the database layer independently reproduces the cleaning logic. `vw_order_summary` in `05_business_analysis.sql` is the SQL equivalent of `orders_clean.csv`.
- `reviews` uses the composite key `(review_id, order_id)`, because `review_id` alone is not unique.
- There is no foreign key from products to category translation, because 2 categories are untranslated.
- No credentials are stored in the repo. Connect with your own `psql -U <user> -d olist`.

## 7. Known limitations
- **Association, not causation.** Late delivery is strongly associated with low review scores. Product, seller and region also vary, so the effect is not isolated.
- **Repeat rate depends on the window.** Customers who joined late in the period had little time to reorder. The 3.1% repeat rate is a lower bound for long-run retention.
- **Repeat customer value** is total GMV per customer over the period. It is not lifetime value: repeat customers spend more in total, but their **average order** is smaller (R$125 vs R$139).
- GMV includes canceled orders (0.7% of GMV). Refunds are not observable.
- Multi-seller orders: in seller-level delivery/review metrics, the order's outcome is attributed to every seller in the order.
- Olist's margin/commission is not in the data, so profitability cannot be analysed.
- Geography uses the customer state only. The geolocation table is loaded in SQL but not used, because the zip prefixes map to many coordinates.
