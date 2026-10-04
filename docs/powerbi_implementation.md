# Power BI Implementation (as built)

**Status: built, published and verified in the Power BI Service** (My workspace, Manipal tenant, built on 2026-10-05).

| Item | Name |
|---|---|
| Semantic model | **Olist E-Commerce Analytics** (import mode, 7 tables, 5 relationships, 30 measures, 1 calculated column) |
| Report | **Olist E-Commerce Performance Dashboard** (4 pages, 1920×1080) |
| File | `dashboard/powerbi_dashboard.pbix` (3.6 MB, report + imported data, downloaded from the Service) |
| Data source | the 7 CSVs in `dashboard/powerbi_data/`, uploaded through Power Query Online. The Service stores the uploaded copies in the owner's OneDrive, which allows refresh. |

The report was built entirely in the browser: Power Query Online for import, TMDL view and DAX query view for the model, and the web report editor for visuals. Power BI Desktop was not used, and the tenant has no Fabric capacity. All measures follow [notes.md](notes.md), and every KPI was cross-checked against the Python and SQL outputs (table at the end).

---

## 1. Data (`python/export_powerbi.py` → `dashboard/powerbi_data/`)

The Service only accepts local uploads up to about 10 MB per file and rejects local Excel files, so the cleaned data is exported as compact CSVs. The 32-character IDs are replaced with integer surrogate keys; metric values are unchanged, as the script's assertions check.

| Table in model | Grain | Key columns |
|---|---|---|
| `orders` | 1 row per order (99,441) | order_key, customer_key (= customer_unique_id), order_status, purchase_date, customer_state, customer_type, delivery_status, delivery_days, lateness_bucket, review_score (decimal, averaged per order) |
| `order_items` | 1 row per item (112,650) | order_key, seller_key, category (English), price, freight_value |
| `sellers` | 1 row per seller (3,095) | seller_key, seller_id, seller_state |
| `payment_summary` | month × payment type × installment band (174) | month_start, payment_type, installment_band, payments, orders, payment_value |
| `customer_frequency 1` | order-frequency band × customer type (4) | order_frequency, customer_type, customers, customer_gmv + calculated column `Orders per Customer` ("1", "2", "3", "4+") |
| `dates 1` | 1 row per day | date, year, month_number, month, year_month, month_start, in_trend_window |
| `months 1` | 1 row per month | month_start, year_month, in_trend_window |

The " 1" suffixes were added automatically by Power Query on upload and are cosmetic.

Two changes from the original Desktop plan:
- Payments are pre-aggregated, because they are only analysed by type, installment band and month.
- The customer-level table is replaced by a frequency summary. The customer metrics use `orders[customer_key]` instead.

## 2. Relationships (all many-to-one, single direction)

| From | To | How it was created |
|---|---|---|
| `order_items[order_key]` | `orders[order_key]` | auto-detected |
| `order_items[seller_key]` | `sellers[seller_key]` | auto-detected |
| `orders[purchase_date]` | `'dates 1'[date]` | TMDL |
| `'dates 1'[month_start]` | `'months 1'[month_start]` | TMDL |
| `payment_summary[month_start]` | `'months 1'[month_start]` | TMDL |

Month filters flow `months → dates → orders → order_items`. Category and seller filter only item-based measures, which is intended: an order can contain several categories.

## 3. Measures (home table `orders`, grouped in display folders)

```DAX
-- Sales
GMV = SUM(order_items[price])
Freight Value = SUM(order_items[freight_value])
Units Sold = COUNTROWS(order_items)
Avg Item Price = AVERAGE(order_items[price])
-- Payments
Payment Value = SUM(payment_summary[payment_value])
Payment Count = SUM(payment_summary[payments])
Avg Payment = DIVIDE([Payment Value], [Payment Count])
-- Orders
Total Orders = COUNTROWS(orders)
Orders with Items = DISTINCTCOUNT(order_items[order_key])
AOV = DIVIDE([GMV], [Orders with Items])
-- Customers (customer_key = customer_unique_id)
Unique Customers = DISTINCTCOUNT(orders[customer_key])
Repeat Customers = CALCULATE([Unique Customers], orders[customer_type] = "repeat")
Repeat Customer Rate = DIVIDE([Repeat Customers], [Unique Customers])
GMV per Customer = DIVIDE([GMV], [Unique Customers])
GMV Share = DIVIDE([GMV], CALCULATE([GMV], ALL(orders[customer_type])))
Customers by Frequency = SUM('customer_frequency 1'[customers])
-- Delivery (only status = delivered with both dates are evaluated)
Delivered Orders = CALCULATE([Total Orders], orders[delivery_status] IN {"on_time", "late"})
Late Orders = CALCULATE([Total Orders], orders[delivery_status] = "late")
Late Delivery Rate = DIVIDE([Late Orders], [Delivered Orders])
Avg Delivery Days = CALCULATE(AVERAGE(orders[delivery_days]), orders[delivery_status] IN {"on_time", "late"})
-- Satisfaction
Avg Review Score = AVERAGE(orders[review_score])
Avg Review On Time = CALCULATE([Avg Review Score], orders[delivery_status] = "on_time")
Avg Review Late = CALCULATE([Avg Review Score], orders[delivery_status] = "late")
Avg Review (Delivered Orders) = CALCULATE([Avg Review Score], orders[delivery_status] IN {"on_time", "late"})
Pct 1-2 Star Reviews = DIVIDE(CALCULATE(COUNTROWS(orders), orders[review_score] <= 2),
                              CALCULATE(COUNTROWS(orders), NOT ISBLANK(orders[review_score])))
-- Sellers
Active Sellers = DISTINCTCOUNT(order_items[seller_key])
-- Rankings (used instead of drag-and-drop Top N filters)
GMV Top 10 Categories = IF(RANKX(ALLSELECTED(order_items[category]), [GMV]) <= 10, [GMV])
GMV Top 10 Sellers = IF(RANKX(ALLSELECTED(sellers[seller_id]), [GMV]) <= 10, [GMV])
Late Rate States 1000 Plus = IF([Delivered Orders] >= 1000, [Late Delivery Rate])
```

## 4. Report pages

All monthly trend visuals carry a visual-level filter `'months 1'[in_trend_window] = True` (Jan-2017 to Aug-2018), so the sparse 2016 months and the Sep/Oct-2018 drop-off are excluded. KPI cards use all data.

| Page | Visuals |
|---|---|
| **Executive Overview** | KPI card (GMV, Total Orders, Unique Customers, AOV, Late Delivery Rate) · Monthly GMV line · Monthly orders column · Top 10 categories by GMV · Orders by status |
| **Customer & Retention** | KPI card (Unique/Repeat Customers, Repeat Rate, GMV per Customer, AOV) · GMV per customer by type · Customers by type donut · Order-frequency distribution · Segment table (customers, orders, GMV, share, GMV/customer, AOV) |
| **Delivery & Experience** | KPI card (Delivered Orders, Late Rate, Avg Delivery Days, Avg Review On Time/Late) · Avg review by lateness bucket · Monthly late-rate line · Late rate by state (≥1,000 delivered orders) · Lateness-bucket table |
| **Product & Seller** | KPI card (GMV, Units, Avg Item Price, Freight, Active Sellers) · Category table sorted by GMV · Units vs price scatter (bubble = GMV) · Top 10 sellers by GMV |

Screenshots: `images/dashboard_page1_executive_overview.png` … `images/dashboard_page4_product_seller.png`.

## 5. Verification (DAX query view vs Python/SQL)

| Check | Power BI | Python / SQL |
|---|---|---|
| GMV | 13,591,643.70 | 13,591,643.70 |
| Total orders / orders with items | 99,441 / 98,666 | 99,441 / 98,666 |
| AOV | 137.75 | 137.75 |
| Unique / repeat customers | 96,096 / 2,997 | 96,096 / 2,997 |
| GMV per customer (repeat / one-time) | 259.87 / 137.63 | 259.87 / 137.63 |
| Delivered / late orders, late rate | 96,470 / 7,826 / 8.11% | same |
| Avg review on time / late | 4.2943 / 2.5665 | 4.2943 / 2.5665 |
| GMV Jan–Aug 2018 / 2017 | 7,385,905.80 / 3,113,000.32 | same (SQL Q3) |
| Late rate Mar-2018 | 21.36% | 21.36% |
| Payment value | 16,008,872.12 | 16,008,872.12 |
| Top-10 categories | health_beauty … garden_tools | same |

## 6. Rebuilding or refreshing

- **Refresh after re-running the pipeline:** run `python python/data_cleaning.py` and then `python python/export_powerbi.py`. Upload the new CSVs over the copies in OneDrive → *Apps/Microsoft Power Query/Uploaded Files*, then click **Refresh now** on the semantic model.
- **Rebuilding in Power BI Desktop:** import the same 7 CSVs, recreate the 5 relationships in section 2, and paste the measures in section 3. TMDL or Tabular Editor can paste them in one go.
