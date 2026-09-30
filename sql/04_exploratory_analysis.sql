
-- 1. Check order status distribution
-- WHY:
-- Understand the composition of orders before deciding how
-- different order statuses should be treated in analysis.

SELECT
    order_status,
    COUNT(*) AS order_count
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;


-- 2. Check the date range of orders
-- WHY:
-- Understand the time period covered by the dataset before
-- performing time-based analysis.

SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order
FROM orders;


-- 3. Examine monthly order volume
-- WHY:
-- Understand how order activity changes over time and identify
-- possible growth, seasonality, or unusual periods.

SELECT
    DATE_TRUNC('month', order_purchase_timestamp) AS month,
    COUNT(*) AS order_count
FROM orders
GROUP BY DATE_TRUNC('month', order_purchase_timestamp)
ORDER BY month;


-- 4. Investigate the unusual drop in orders after August 2018
-- WHY:
-- September and October 2018 showed an unusually low number of
-- orders. We inspect those records to understand whether this
-- represents normal activity or an unusual tail in the dataset.

SELECT
    order_purchase_timestamp,
    order_status
FROM orders
WHERE order_purchase_timestamp >= '2018-09-01'
ORDER BY order_purchase_timestamp;


-- Finding:
-- Only 20 orders occur after August 2018:
-- 19 are canceled and 1 is shipped.
-- Therefore, normal commercial activity effectively ends
-- around August 2018.


-- 5. Cross-check the unusual drop using order items
-- WHY:
-- We observed very few orders after August. We cross-check the
-- product-level order data to see whether the same pattern exists
-- in order_items.

SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
    COUNT(*) AS item_count
FROM order_items oi
JOIN orders o
    ON oi.order_id = o.order_id
WHERE o.order_purchase_timestamp >= '2018-08-01'
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
ORDER BY month;


-- Finding:
-- August 2018: 7,248 order items
-- September 2018: 1 order item
-- October 2018: 0 order items
-- This supports the observation that normal commercial activity
-- effectively ends around August 2018.


-- 6. Profile product prices and freight costs
-- WHY:
-- Before calculating sales or order value, understand the range
-- and typical values of product prices and shipping costs.

SELECT
    MIN(price) AS min_price,
    MAX(price) AS max_price,
    AVG(price) AS avg_price,
    MIN(freight_value) AS min_freight,
    MAX(freight_value) AS max_freight,
    AVG(freight_value) AS avg_freight
FROM order_items;


-- 7. Inspect the most expensive order items
-- WHY:
-- Determine whether extreme price values appear to be legitimate
-- products or obvious data-entry errors.

SELECT
    product_id,
    price,
    freight_value
FROM order_items
ORDER BY price DESC
LIMIT 10;


-- Finding:
-- High prices appear plausible, so they are not removed merely
-- because they are unusually high.


-- 8. Inspect the cheapest order items
-- WHY:
-- Check the opposite end of the price range for obviously
-- invalid or suspicious values.

SELECT
    product_id,
    price,
    freight_value
FROM order_items
ORDER BY price ASC
LIMIT 10;


-- Finding:
-- Very low prices exist, but they are not inherently invalid.
-- Some have relatively high freight costs, which may be unusual
-- but does not by itself indicate a data error.


-- 9. Investigate free shipping
-- WHY:
-- Explore whether free shipping appears to be associated with
-- particular product-price ranges.

SELECT
    COUNT(*) AS free_shipping_items,
    MIN(price) AS min_product_price,
    MAX(price) AS max_product_price,
    AVG(price) AS avg_product_price
FROM order_items
WHERE freight_value = 0;


-- Finding:
-- 383 items have zero freight.
-- Their prices range from 53.90 to 712.90.
-- This does not suggest a simple universal price threshold.


-- 10. Inspect free-shipping orders
-- WHY:
-- Look at actual free-shipping orders to investigate whether
-- price or customer geography might explain the pattern.

SELECT
    oi.order_id,
    oi.product_id,
    oi.price,
    oi.freight_value,
    o.customer_id,
    c.customer_city,
    c.customer_state
FROM order_items oi
JOIN orders o
    ON oi.order_id = o.order_id
JOIN customers c
    ON o.customer_id = c.customer_id
WHERE oi.freight_value = 0
ORDER BY oi.price
LIMIT 30;


-- Finding:
-- Free-shipping orders occur across many customer states.
-- Several free-shipping orders involve the same products,
-- suggesting that seller/product characteristics may matter.


-- 11. Identify products with the most free-shipping orders
-- WHY:
-- Determine whether free shipping is concentrated among
-- particular products rather than being purely price-based.

SELECT
    product_id,
    COUNT(*) AS free_shipping_orders,
    price
FROM order_items
WHERE freight_value = 0
GROUP BY product_id, price
ORDER BY free_shipping_orders DESC
LIMIT 10;


-- 12. Identify sellers with the most free-shipping orders
-- WHY:
-- Test whether free shipping may be associated with specific
-- sellers rather than being a universal price or geographic rule.

SELECT
    seller_id,
    COUNT(*) AS free_shipping_orders
FROM order_items
WHERE freight_value = 0
GROUP BY seller_id
ORDER BY free_shipping_orders DESC
LIMIT 10;


-- Finding:
-- Free shipping is highly concentrated among a small number
-- of sellers. This suggests seller-specific shipping policies
-- may be an important factor.


 --13. Calculate free-shipping rate by seller
  SELECT
    seller_id,
    COUNT(*) AS total_items,
    COUNT(*) FILTER (WHERE freight_value = 0) AS free_shipping_items,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE freight_value = 0) / COUNT(*),
        2
    ) AS free_shipping_rate
FROM order_items
GROUP BY seller_id
HAVING COUNT(*) >= 20
ORDER BY free_shipping_rate DESC;
-- FINDING:
-- Free-shipping rates vary considerably across sellers.
-- The highest observed seller rate is 27.34%, while many sellers
-- have no free-shipping orders at all. This suggests that
-- shipping behavior may vary by seller, although the underlying
-- reason is not established here.

--------------------------------------------------------------------
---------how is the ecommerce buisness performing overall-----------
--------------------------------------------------------------------
-- Payment method distribution
-- WHY: Understand how customers pay and the total payment
-- value associated with each payment method.

SELECT
    payment_type,
    COUNT(*) AS payment_count,
    SUM(payment_value) AS total_payment_value,
    AVG(payment_value) AS avg_payment_value
FROM payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- Orders with payment records
-- WHY: Check whether orders generally have associated payments
-- before using payment_value in our revenue/payment analysis.

SELECT
    COUNT(DISTINCT order_id) AS orders_with_payments,
    COUNT(*) AS total_payment_records,
    SUM(payment_value) AS total_payment_value
FROM payments;

-- Reconcile product + freight value with recorded payments
-- WHY: Check whether the amount paid by customers closely matches
-- the product and freight value recorded for each order.
-- Both tables are first aggregated to one row per order to avoid
-- double counting when an order has multiple items or payments.

WITH order_values AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_value
    FROM order_items
    GROUP BY order_id
),
order_payments AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_value
    FROM payments
    GROUP BY order_id
)
SELECT
    COUNT(*) AS orders_compared,
    SUM(ov.order_value) AS total_order_value,
    SUM(op.payment_value) AS total_payment_value,
    SUM(op.payment_value - ov.order_value) AS total_difference
FROM order_values ov
JOIN order_payments op
    ON ov.order_id = op.order_id;
-- FINDING:
-- 98,665 orders had both item and payment records.
-- Product + freight value = 15,843,409.78
-- Payment value = 15,846,280.17
-- Difference = 2,870.39
-- The two values closely reconcile, supporting the consistency
-- of the transactional data for these orders.

-- Investigate orders missing either items or payments
-- WHY: Understand why some orders could not be included in the
-- payment vs order-value reconciliation.

WITH order_values AS (
    SELECT
        order_id
    FROM order_items
    GROUP BY order_id
),
order_payments AS (
    SELECT
        order_id
    FROM payments
    GROUP BY order_id
)
SELECT
    CASE
        WHEN ov.order_id IS NULL THEN 'payment_without_items'
        WHEN op.order_id IS NULL THEN 'items_without_payment'
    END AS mismatch_type,
    COUNT(*) AS order_count
FROM order_values ov
FULL OUTER JOIN order_payments op
    ON ov.order_id = op.order_id
WHERE ov.order_id IS NULL
   OR op.order_id IS NULL
GROUP BY mismatch_type;
-- FINDING:
-- 1 order has items but no payment record.
-- 775 orders have payment records but no order items.
-- The 775 payment-only orders are primarily unavailable or
-- canceled orders.


-- Payment value associated with orders without order items
-- WHY: Determine whether these payment-only orders represent
-- a material amount that could affect our sales/revenue analysis.
SELECT
    o.order_status,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(p.payment_value) AS payment_value
FROM orders o
JOIN payments p
    ON o.order_id = p.order_id
LEFT JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY payment_value DESC;
-- FINDING:
-- The 775 payment-only orders contain approximately 162,592
-- in recorded payment value. Most are unavailable or canceled.
-- Because the dataset does not show whether these payments were
-- subsequently refunded, they will not automatically be treated
-- as completed sales revenue.

--How much product value is being sold over time, and what does the sales trend look like?
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
    SUM(oi.price) AS sales_value
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
ORDER BY month;
--The business experienced substantial sales growth through 2017, reached around 1M in monthly 
--product sales by late 2017/early 2018, and then remained relatively stable through August 2018

--Total product value of an order → then average that across orders
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(oi.price) AS sales_value,
    SUM(oi.price) / COUNT(DISTINCT o.order_id) AS avg_order_value
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
ORDER BY month;
--orders increased massively, while average order value stayed in roughly the ₹125–₹150 range.
--The growth in product sales was primarily driven by an increase in order volume, rather than a substantial increase in average order value.

--Which product categories sell the most items?
SELECT
    p.product_category_name,
    COUNT(*) AS items_sold
FROM order_items oi
JOIN products p
    ON oi.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY items_sold DESC
LIMIT 10;
--marketplace is heavily concentrated in home/lifestyle, beauty/health, sports, furniture, and electronics/accessories.

--Which categories generate the most product sales value?
SELECT
    p.product_category_name,
    COUNT(*) AS items_sold,
    SUM(oi.price) AS sales_value
FROM order_items oi
JOIN products p
    ON oi.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY sales_value DESC
LIMIT 10;
--Beleza/Saúde generated the highest product sales value among the categories examined, while Cama/Mesa/Banho had the highest item volume.


-- Top products by sales value
-- WHY: Identify the individual products contributing the most
-- to total product sales value.
SELECT
    oi.product_id,
    COUNT(*) AS items_sold,
    SUM(oi.price) AS sales_value
FROM order_items oi
GROUP BY oi.product_id
ORDER BY sales_value DESC
LIMIT 10;

-- the product can have high sales if its either expensive or been bought in higher quantity
-- Identify the categories of the top products by sales value
-- WHY: Make the top-product analysis interpretable by connecting
-- product IDs to their product categories.
SELECT
    oi.product_id,
    p.product_category_name,
    COUNT(*) AS items_sold,
    SUM(oi.price) AS sales_value
FROM order_items oi
JOIN products p
    ON oi.product_id = p.product_id
GROUP BY
    oi.product_id,
    p.product_category_name
ORDER BY sales_value DESC
LIMIT 10;
--There's a clear difference between high-volume products and high-value products.

-- Top spending customers and their location
-- WHY: Identify the highest-value customers and check whether
-- they show any geographic concentration.

SELECT
    o.customer_id,
    c.customer_city,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(oi.price) AS total_spent
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
GROUP BY
    o.customer_id,
    c.customer_city,
    c.customer_state
ORDER BY total_spent DESC
LIMIT 20;

-- Customer purchase frequency
-- WHY: Understand whether customers typically place one order
-- or return and place multiple orders.

SELECT
    order_count,
    COUNT(*) AS customer_count
FROM (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS order_count
    FROM orders
    GROUP BY customer_id
) customer_orders
GROUP BY order_count
ORDER BY order_count;
--Each order is associated with a unique customer ID in the provided dataset, so repeat-purchase behavior cannot be reliably analyzed using customer_id alone.

-- Orders by customer state
-- WHY: Identify where the marketplace's customer demand is concentrated.

SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS order_count
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY order_count DESC;
--Customer demand is geographically concentrated, with São Paulo contributing by far the largest share of orders.

-- Product sales value by customer state
-- WHY: Compare geographic order volume with financial contribution.
-- This helps determine whether high-order states also generate
-- high product sales value.

SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(oi.price) AS sales_value
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
GROUP BY c.customer_state
ORDER BY sales_value DESC;

--Does the state with the most orders also generate the most sales?
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(oi.price) AS sales_value
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
GROUP BY c.customer_state
ORDER BY sales_value DESC;
--Customer demand and product sales are strongly concentrated in São Paulo, followed by Rio de Janeiro and Minas Gerais.

--do sales per order differs significantly by state.
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(oi.price) AS sales_value,
    SUM(oi.price) / COUNT(DISTINCT o.order_id) AS avg_order_value
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
GROUP BY c.customer_state
ORDER BY avg_order_value DESC;

-- Seller sales performance
-- WHY: Identify sellers contributing the most product sales value
-- and compare their sales with order/item volume.

SELECT
    oi.seller_id,
    COUNT(*) AS items_sold,
    COUNT(DISTINCT oi.order_id) AS order_count,
    SUM(oi.price) AS sales_value
FROM order_items oi
GROUP BY oi.seller_id
ORDER BY sales_value DESC
LIMIT 10;
--Sales are distributed across multiple high-performing sellers, 
--with no obvious single-seller dominance among the top sellers.
--Seller sales value varies with both item volume and product value.

-------delivery performance --------

-- Delivery time
-- WHY: Measure how long customers typically wait between
-- purchase and delivery.
SELECT
    AVG(
        order_delivered_customer_date - order_purchase_timestamp
    ) AS avg_delivery_time
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

  -- Late delivery rate
-- WHY: Measure whether orders are arriving later than the
-- estimated delivery date promised to customers.

SELECT
    COUNT(*) AS delivered_orders,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date > order_estimated_delivery_date
    ) AS late_orders,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE order_delivered_customer_date > order_estimated_delivery_date
        ) / COUNT(*),
        2
    ) AS late_delivery_rate
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;
--Average delivery time → 12.6 days
--Late delivery rate → 8.11%


-----How satisfied are customers, and does satisfaction vary with delivery performance?------

-- Review score distribution
-- WHY: Understand overall customer satisfaction.
SELECT
    review_score,
    COUNT(*) AS review_count
FROM eviews
GROUP BY review_score
ORDER BY review_score;

-- Review score vs delivery performance
-- WHY: Check whether late delivery is associated with
-- lower customer satisfaction.

SELECT
    r.review_score,
    COUNT(*) AS review_count,
    COUNT(*) FILTER (
        WHERE o.order_delivered_customer_date > o.order_estimated_delivery_date
    ) AS late_orders
FROM reviews r
JOIN orders o
    ON r.order_id = o.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY r.review_score
ORDER BY r.review_score;