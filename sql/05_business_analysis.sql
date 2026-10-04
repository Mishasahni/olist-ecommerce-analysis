-- =====================================================================
-- 05_business_analysis.sql
-- Business questions answered in PostgreSQL. Results match
-- python/analysis.py (see docs/notes.md for metric definitions).
--
-- Metric definitions used everywhere in this project:
--   GMV (product sales value) = SUM(order_items.price)
--   Freight value             = SUM(order_items.freight_value)
--   Payment value             = SUM(payments.payment_value)
--   AOV                       = GMV / orders with at least one item
--   Late delivery             = delivered date > estimated date, evaluated
--                               only for order_status = 'delivered' orders
--                               with both dates present
--   Customer                  = customer_unique_id (customer_id is per order)
-- Currency: Brazilian real (R$).
-- =====================================================================


-- ---------------------------------------------------------------------
-- Reusable order-level view: one row per order with its customer, value,
-- delivery classification and (averaged) review score.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_order_summary AS
WITH item_totals AS (
    SELECT
        order_id,
        COUNT(*)           AS items_count,
        SUM(price)         AS product_value,
        SUM(freight_value) AS freight_value
    FROM order_items
    GROUP BY order_id
),
review_scores AS (
    -- some orders have more than one review -> average per order
    SELECT order_id, AVG(review_score) AS review_score
    FROM reviews
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.order_status,
    c.customer_unique_id,
    c.customer_state,
    o.order_purchase_timestamp,
    DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS purchase_month,
    COALESCE(it.items_count, 0) AS items_count,
    it.product_value,
    it.freight_value,
    rs.review_score,
    CASE
        WHEN o.order_status <> 'delivered'
          OR o.order_delivered_customer_date IS NULL
          OR o.order_estimated_delivery_date IS NULL      THEN 'not_applicable'
        WHEN o.order_delivered_customer_date
             > o.order_estimated_delivery_date            THEN 'late'
        ELSE 'on_time'
    END AS delivery_status,
    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN EXTRACT(EPOCH FROM o.order_delivered_customer_date
                              - o.order_purchase_timestamp) / 86400.0
    END AS delivery_days,
    EXTRACT(EPOCH FROM o.order_delivered_customer_date
                     - o.order_estimated_delivery_date) / 86400.0 AS days_vs_estimate
FROM orders o
JOIN customers c        ON o.customer_id = c.customer_id
LEFT JOIN item_totals it ON o.order_id = it.order_id
LEFT JOIN review_scores rs ON o.order_id = rs.order_id;


-- =====================================================================
-- Q1. How big is the marketplace? (headline KPIs)
-- =====================================================================
SELECT
    (SELECT COUNT(*) FROM orders)                                   AS total_orders,
    (SELECT COUNT(DISTINCT order_id) FROM order_items)              AS orders_with_items,
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customers)      AS unique_customers,
    (SELECT SUM(price) FROM order_items)                            AS gmv,
    (SELECT SUM(freight_value) FROM order_items)                    AS freight_value,
    (SELECT SUM(payment_value) FROM payments)                       AS payment_value,
    (SELECT COUNT(*) FROM order_items)                              AS units_sold,
    ROUND((SELECT SUM(price) FROM order_items)
        / (SELECT COUNT(DISTINCT order_id) FROM order_items), 2)    AS aov,
    ROUND((SELECT AVG(price) FROM order_items), 2)                  AS avg_item_price;
-- RESULT: 99,441 orders | 96,096 customers | GMV R$13.59M | AOV R$137.75
-- Payment value (R$16.01M) > GMV + freight (R$15.84M) because it also
-- includes payments recorded on orders with no items (mostly canceled/unavailable).


-- =====================================================================
-- Q2. What happens to orders? (order status distribution)
-- =====================================================================
SELECT
    order_status,
    COUNT(*)                                            AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS share_pct,
    COALESCE(SUM(product_value), 0)                     AS gmv
FROM vw_order_summary
GROUP BY order_status
ORDER BY orders DESC;
-- RESULT: 97.0% delivered; canceled + unavailable = 1.2% of orders but only
-- 0.7% of GMV (most unavailable orders have no items).


-- =====================================================================
-- Q3. How did sales grow over time?
-- Trend window Jan-2017 to Aug-2018: 2016 has only ~300 orders (and no
-- Nov-2016 orders) and Sep/Oct-2018 contain almost only canceled orders.
-- =====================================================================
WITH monthly AS (
    SELECT
        purchase_month,
        COUNT(*)           AS orders,
        SUM(product_value) AS gmv
    FROM vw_order_summary
    WHERE items_count > 0
      AND purchase_month BETWEEN '2017-01-01' AND '2018-08-01'
    GROUP BY purchase_month
)
SELECT
    purchase_month,
    orders,
    gmv,
    ROUND(gmv / orders, 2) AS aov,
    ROUND(100.0 * (gmv / LAG(gmv) OVER (ORDER BY purchase_month) - 1), 1) AS gmv_mom_growth_pct
FROM monthly
ORDER BY purchase_month;
-- RESULT: GMV grew from R$120K (Jan-17) to ~R$1M/month in 2018; peak month
-- Nov-2017 (7,451 orders, Black Friday). AOV stayed within R$125-R$153, so
-- growth was driven by order volume, not basket size.

-- Year-over-year comparison for the comparable period (Jan-Aug)
SELECT
    EXTRACT(YEAR FROM purchase_month) AS year,
    COUNT(*)                          AS orders,
    SUM(product_value)                AS gmv
FROM vw_order_summary
WHERE items_count > 0
  AND EXTRACT(MONTH FROM purchase_month) BETWEEN 1 AND 8
  AND EXTRACT(YEAR FROM purchase_month) IN (2017, 2018)
GROUP BY 1
ORDER BY 1;


-- =====================================================================
-- Q4. Which categories drive sales, and how concentrated are they?
-- =====================================================================
WITH category_sales AS (
    SELECT
        COALESCE(t.product_category_name_english,
                 p.product_category_name, 'unknown') AS category,
        SUM(oi.price)               AS gmv,
        COUNT(*)                    AS units,
        COUNT(DISTINCT oi.order_id) AS orders,
        ROUND(AVG(oi.price), 2)     AS avg_price
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_translation t
        ON p.product_category_name = t.product_category_name
    GROUP BY 1
)
SELECT
    RANK() OVER (ORDER BY gmv DESC) AS gmv_rank,
    category,
    gmv,
    units,
    orders,
    avg_price,
    ROUND(100.0 * gmv / SUM(gmv) OVER (), 2) AS gmv_share_pct,
    ROUND(100.0 * SUM(gmv) OVER (ORDER BY gmv DESC) / SUM(gmv) OVER (), 2) AS cumulative_share_pct
FROM category_sales
ORDER BY gmv DESC
LIMIT 15;
-- RESULT: health_beauty (9.3%), watches_gifts (8.9%) and bed_bath_table
-- (7.6%) lead GMV; the top 10 of 74 categories = 62.4% of GMV.
-- bed_bath_table sells the most units but at a low average price (R$93),
-- while watches_gifts earns its GMV from a high average price (R$201).


-- =====================================================================
-- Q5. Who are the top sellers, and how concentrated is seller GMV?
-- =====================================================================
WITH seller_sales AS (
    SELECT
        seller_id,
        SUM(price)               AS gmv,
        COUNT(*)                 AS units,
        COUNT(DISTINCT order_id) AS orders
    FROM order_items
    GROUP BY seller_id
)
SELECT
    s.seller_id,
    sl.seller_state,
    s.gmv,
    s.units,
    s.orders,
    ROUND(100.0 * s.gmv / SUM(s.gmv) OVER (), 2) AS gmv_share_pct
FROM seller_sales s
JOIN sellers sl ON s.seller_id = sl.seller_id
ORDER BY s.gmv DESC
LIMIT 10;

-- Seller concentration: share of GMV by seller decile
WITH seller_sales AS (
    SELECT seller_id, SUM(price) AS gmv
    FROM order_items
    GROUP BY seller_id
),
ranked AS (
    SELECT gmv, NTILE(10) OVER (ORDER BY gmv DESC) AS decile
    FROM seller_sales
)
SELECT
    decile,
    COUNT(*)                                 AS sellers,
    SUM(gmv)                                 AS gmv,
    ROUND(100.0 * SUM(gmv) / SUM(SUM(gmv)) OVER (), 1) AS gmv_share_pct
FROM ranked
GROUP BY decile
ORDER BY decile;
-- RESULT: the top 10% of 3,095 sellers generate ~67% of GMV
-- (NTILE puts 310 sellers in decile 1; Python uses the top 309).


-- =====================================================================
-- Q6. Do customers come back, and are repeat customers worth more?
-- (customer_unique_id, NOT customer_id)
-- =====================================================================
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(*)                        AS order_count,
        COALESCE(SUM(product_value), 0) AS gmv
    FROM vw_order_summary
    GROUP BY customer_unique_id
)
SELECT
    order_count,
    COUNT(*) AS customers
FROM customer_orders
GROUP BY order_count
ORDER BY order_count;
-- RESULT: 1 -> 93,099 | 2 -> 2,745 | 3 -> 203 | 4 -> 30 | 5+ -> 19

WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(*)                        AS order_count,
        COALESCE(SUM(product_value), 0) AS gmv
    FROM vw_order_summary
    GROUP BY customer_unique_id
)
SELECT
    CASE WHEN order_count > 1 THEN 'repeat' ELSE 'one_time' END AS customer_type,
    COUNT(*)                                                    AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS customer_share_pct,
    SUM(order_count)                                            AS orders,
    SUM(gmv)                                                    AS gmv,
    ROUND(100.0 * SUM(gmv) / SUM(SUM(gmv)) OVER (), 2)          AS gmv_share_pct,
    ROUND(AVG(gmv), 2)                                          AS avg_gmv_per_customer
FROM customer_orders
GROUP BY 1;
-- RESULT: repeat customers are 3.1% of customers and 5.7% of GMV, with an
-- average GMV per customer of R$260 vs R$138 (~1.9x) for one-time customers.


-- =====================================================================
-- Q7. How reliable is delivery, and how does it relate to reviews?
-- =====================================================================
SELECT
    COUNT(*)                                                   AS delivered_orders,
    COUNT(*) FILTER (WHERE delivery_status = 'late')           AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivery_status = 'late') / COUNT(*), 2) AS late_rate_pct,
    ROUND(AVG(delivery_days), 1)                               AS avg_delivery_days,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)::NUMERIC, 1) AS median_delivery_days
FROM vw_order_summary
WHERE delivery_status IN ('on_time', 'late');
-- RESULT: 96,470 delivered orders | 7,826 late | 8.11% | 12.6 days avg

SELECT
    delivery_status,
    COUNT(*)                                                         AS orders,
    ROUND(AVG(delivery_days), 1)                                     AS avg_delivery_days,
    ROUND(AVG(review_score), 2)                                      AS avg_review,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2)
          / COUNT(review_score), 1)                                  AS pct_1_2_star,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score = 5)
          / COUNT(review_score), 1)                                  AS pct_5_star
FROM vw_order_summary
WHERE delivery_status IN ('on_time', 'late')
GROUP BY delivery_status;
-- RESULT: on-time 4.29 avg (9% 1-2 star) vs late 2.57 avg (54% 1-2 star).
-- Late deliveries are strongly ASSOCIATED with lower review scores; this
-- is an observational comparison, not proof of causation.

-- Review score by how late the order arrived
SELECT
    CASE
        WHEN delivery_status = 'on_time' THEN '0 on time'
        WHEN days_vs_estimate <= 3       THEN '1 1-3 days late'
        WHEN days_vs_estimate <= 7       THEN '2 4-7 days late'
        WHEN days_vs_estimate <= 14      THEN '3 8-14 days late'
        ELSE                                  '4 15+ days late'
    END                          AS lateness_bucket,
    COUNT(*)                     AS orders,
    ROUND(AVG(review_score), 2)  AS avg_review
FROM vw_order_summary
WHERE delivery_status IN ('on_time', 'late')
GROUP BY 1
ORDER BY 1;
-- RESULT: average score falls steadily from 4.29 (on time) to 3.77
-- (1-3 days late) and ~1.7 (8+ days late).

-- Late-delivery rate by month (operational trend)
SELECT
    purchase_month,
    COUNT(*)                                                                    AS delivered_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivery_status = 'late') / COUNT(*), 2) AS late_rate_pct
FROM vw_order_summary
WHERE delivery_status IN ('on_time', 'late')
  AND purchase_month BETWEEN '2017-01-01' AND '2018-08-01'
GROUP BY purchase_month
ORDER BY purchase_month;
-- RESULT: late rate spikes after peak periods (Nov-2017 14.3%,
-- Feb-2018 16.0%, Mar-2018 21.4%).


-- =====================================================================
-- Q8. Where is delivery weakest? (customer state, min. 1,000 orders)
-- =====================================================================
SELECT
    customer_state,
    COUNT(*)                                                                      AS delivered_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivery_status = 'late') / COUNT(*), 2) AS late_rate_pct,
    ROUND(AVG(delivery_days), 1)                                                  AS avg_delivery_days,
    ROUND(AVG(review_score), 2)                                                   AS avg_review
FROM vw_order_summary
WHERE delivery_status IN ('on_time', 'late')
GROUP BY customer_state
HAVING COUNT(*) >= 1000
ORDER BY late_rate_pct DESC;
-- RESULT: RJ (13.5%) and BA (14.0%) have more than twice SP's late rate
-- (5.9%) and much longer delivery times.


-- =====================================================================
-- Q9. How do customers pay?
-- =====================================================================
SELECT
    payment_type,
    COUNT(*)                                                     AS payments,
    COUNT(DISTINCT order_id)                                     AS orders,
    SUM(payment_value)                                           AS payment_value,
    ROUND(AVG(payment_value), 2)                                 AS avg_payment,
    ROUND(100.0 * SUM(payment_value) / SUM(SUM(payment_value)) OVER (), 2) AS value_share_pct
FROM payments
GROUP BY payment_type
ORDER BY payment_value DESC;
-- RESULT: credit card = 78% of payment value, boleto 18%.

-- Credit-card installments vs payment size
SELECT
    CASE
        WHEN payment_installments = 1  THEN '1'
        WHEN payment_installments <= 3 THEN '2-3'
        WHEN payment_installments <= 6 THEN '4-6'
        WHEN payment_installments <= 10 THEN '7-10'
        ELSE '11+'
    END                            AS installments,
    COUNT(*)                       AS payments,
    ROUND(AVG(payment_value), 2)   AS avg_payment
FROM payments
WHERE payment_type = 'credit_card'
  AND payment_installments >= 1
GROUP BY 1
ORDER BY MIN(payment_installments);
-- RESULT: 2 out of 3 credit-card payments use installments; average payment
-- rises from R$96 (1 installment) to R$334 (7-10 installments).


-- =====================================================================
-- Q10. Which established sellers hurt customer experience?
-- Sellers with >= 50 orders and their late rate / average review.
-- (An order with items from several sellers counts for each seller.)
-- =====================================================================
WITH seller_orders AS (
    SELECT DISTINCT oi.seller_id, oi.order_id
    FROM order_items oi
),
seller_perf AS (
    SELECT
        so.seller_id,
        COUNT(*)                                                    AS orders,
        AVG(CASE v.delivery_status WHEN 'late' THEN 1.0
                                   WHEN 'on_time' THEN 0.0 END)     AS late_rate,
        AVG(v.review_score)                                         AS avg_review
    FROM seller_orders so
    JOIN vw_order_summary v ON so.order_id = v.order_id
    GROUP BY so.seller_id
    HAVING COUNT(*) >= 50
)
SELECT
    CASE WHEN avg_review < 3.5 THEN 'below 3.5 stars' ELSE '3.5 stars or more' END AS seller_group,
    COUNT(*)                            AS sellers,
    ROUND(100.0 * AVG(late_rate), 1)    AS avg_late_rate_pct,
    ROUND(AVG(avg_review), 2)           AS avg_review
FROM seller_perf
GROUP BY 1;
-- RESULT: 19 of 429 established sellers average below 3.5 stars; their
-- late rate (15.7%) is about double that of the other established sellers (7.5%).
