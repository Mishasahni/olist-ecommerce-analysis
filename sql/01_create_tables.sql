-- =====================================================================
-- 01_create_tables.sql
-- PostgreSQL schema for the raw Olist dataset.
-- Column names match the raw CSV headers exactly (including the original
-- "lenght" spelling in products) so the files load without transformation.
--
-- Run (from the project root):
--   psql -d olist -f sql/01_create_tables.sql
-- =====================================================================

DROP TABLE IF EXISTS order_items, payments, reviews, orders, customers,
    sellers, products, product_category_translation, geolocation CASCADE;

CREATE TABLE customers (
    customer_id              VARCHAR(32) PRIMARY KEY,   -- one per ORDER
    customer_unique_id       VARCHAR(32) NOT NULL,      -- the real customer
    customer_zip_code_prefix VARCHAR(5),
    customer_city            TEXT,
    customer_state           CHAR(2)
);
CREATE INDEX idx_customers_unique_id ON customers (customer_unique_id);

CREATE TABLE sellers (
    seller_id              VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5),
    seller_city            TEXT,
    seller_state           CHAR(2)
);

CREATE TABLE product_category_translation (
    product_category_name         TEXT PRIMARY KEY,
    product_category_name_english TEXT NOT NULL
);

-- No FK to product_category_translation: 2 categories have no translation
-- and 610 products have no category at all (checked in 03_data_validation).
CREATE TABLE products (
    product_id                 VARCHAR(32) PRIMARY KEY,
    product_category_name      TEXT,
    product_name_lenght        INTEGER,
    product_description_lenght INTEGER,
    product_photos_qty         INTEGER,
    product_weight_g           INTEGER,
    product_length_cm          INTEGER,
    product_height_cm          INTEGER,
    product_width_cm           INTEGER
);

CREATE TABLE orders (
    order_id                      VARCHAR(32) PRIMARY KEY,
    customer_id                   VARCHAR(32) NOT NULL REFERENCES customers (customer_id),
    order_status                  VARCHAR(20) NOT NULL,
    order_purchase_timestamp      TIMESTAMP NOT NULL,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE TABLE order_items (
    order_id            VARCHAR(32) NOT NULL REFERENCES orders (order_id),
    order_item_id       INTEGER NOT NULL,           -- 1..n within an order
    product_id          VARCHAR(32) NOT NULL REFERENCES products (product_id),
    seller_id           VARCHAR(32) NOT NULL REFERENCES sellers (seller_id),
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10, 2) NOT NULL,
    freight_value       NUMERIC(10, 2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);
CREATE INDEX idx_order_items_product ON order_items (product_id);
CREATE INDEX idx_order_items_seller ON order_items (seller_id);

CREATE TABLE payments (
    order_id             VARCHAR(32) NOT NULL REFERENCES orders (order_id),
    payment_sequential   INTEGER NOT NULL,
    payment_type         VARCHAR(20) NOT NULL,
    payment_installments INTEGER NOT NULL,
    payment_value        NUMERIC(10, 2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- review_id is NOT unique in the raw data (the same review can be linked to
-- several orders) and some orders have several reviews, so the key is the pair.
CREATE TABLE reviews (
    review_id               VARCHAR(32) NOT NULL,
    order_id                VARCHAR(32) NOT NULL REFERENCES orders (order_id),
    review_score            SMALLINT NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    PRIMARY KEY (review_id, order_id)
);

CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(5),
    geolocation_lat             DOUBLE PRECISION,
    geolocation_lng             DOUBLE PRECISION,
    geolocation_city            TEXT,
    geolocation_state           CHAR(2)
);
