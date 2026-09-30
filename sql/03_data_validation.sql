-- Check row counts for all tables
SELECT
    (SELECT COUNT(*) FROM orders) AS orders,
    (SELECT COUNT(*) FROM customers) AS customers,
    (SELECT COUNT(*) FROM sellers) AS sellers,
    (SELECT COUNT(*) FROM products) AS products,
    (SELECT COUNT(*) FROM payments) AS payments,
    (SELECT COUNT(*) FROM reviews) AS reviews,
    (SELECT COUNT(*) FROM order_items) AS order_items,
    (SELECT COUNT(*) FROM geolocation) AS geolocation,
    (SELECT COUNT(*) FROM product_category_translation) AS category_translation;


-- Check completeness of key order columns
SELECT
    COUNT(*) AS total_orders,
    COUNT(order_id) AS order_ids,
    COUNT(customer_id) AS customer_ids,
    COUNT(order_purchase_timestamp) AS purchase_dates,
    COUNT(order_approved_at) AS approved_dates,
    COUNT(order_delivered_customer_date) AS delivered_dates,
    COUNT(order_estimated_delivery_date) AS estimated_dates
FROM orders;

---------------------------*-------------------------*--------------------*-------------------------------*---------------------------
-- Check for orders without delivery dates (validating data integrity/nulls)
SELECT
    order_status,
    COUNT(*) AS orders_without_delivery_date
FROM orders
WHERE order_delivered_customer_date IS NULL
GROUP BY order_status
ORDER BY orders_without_delivery_date DESC;
-- 8 orders showed as delivered but have no delivery date, which is a data integrity issue. This needs to be investigated further.

-- Check for orders with order_status = 'delivered' but no order_delivered_customer_date
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

--CONCLUSION
-- Data quality check:
-- 8 orders have order_status = 'delivered' but no
-- order_delivered_customer_date.
-- These records represent ~0.008% of orders and are excluded
-- from delivery-time calculations rather than imputing a delivery date.

---------------------------*-------------------------*--------------------*-------------------------------*---------------------------
-- Check for orders without approval dates (validating data integrity/nulls)
SELECT
    order_status,
    COUNT(*) AS orders_without_approval_date
FROM orders
WHERE order_approved_at IS NULL
GROUP BY order_status
ORDER BY orders_without_approval_date DESC;

--Check for orders with order_status = 'delivered' but no order_approved_at (14 delivered but not approved)
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM orders
WHERE order_status = 'delivered'
  AND order_approved_at IS NULL;

--checking if all orderids are unique in the orders table
  SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_order_ids
FROM orders;

-- Validate orders → customers relationship
SELECT COUNT(*) AS orders_without_customer
FROM orders o
LEFT JOIN customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

 --- Validate orders → order_items relationship (checking if all orders have at least one order item)
SELECT COUNT(*) AS orders_without_items
FROM orders o
LEFT JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;
---99,441 total orders
---775 have no order_items
---98,666 have at least one order_item
 
---finally, check the orders without order_items by order_status to see if there is a pattern
SELECT
    o.order_status,
    COUNT(*) AS orders_without_items
FROM orders o
LEFT JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;
-- Data quality note:
-- 1 shipped order has no corresponding order_items record.
-- The order has a carrier timestamp but no item-level data.
-- Since this represents ~0.001% of orders, it is treated as
-- an isolated data-quality anomaly and no values are imputed.

---Validate order_items → products relationship
SELECT COUNT(*) AS items_without_product
FROM order_items oi
LEFT JOIN products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Validate order_items → sellers relationship
SELECT COUNT(*) AS items_without_seller
FROM order_items oi
LEFT JOIN sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- Validate payments → orders relationship
SELECT COUNT(*) AS payments_without_order
FROM payments p
LEFT JOIN orders o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Validate reviews → orders relationship
SELECT COUNT(*) AS reviews_without_order
FROM reviews r
LEFT JOIN orders o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Check for product categories without an English translation
SELECT DISTINCT
    p.product_category_name
FROM products p
LEFT JOIN product_category_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
ORDER BY p.product_category_name;