-- =====================================================================
-- 02_load_data.sql
-- Loads the raw Olist CSVs into the tables from 01_create_tables.sql.
--
-- REQUIREMENTS
--   * Download the dataset from Kaggle ("Brazilian E-Commerce Public Dataset
--     by Olist") and place the 9 CSV files in data/raw/.
--   * Run psql FROM THE PROJECT ROOT: \copy reads files relative to the
--     directory psql was started in (client-side, so no superuser needed).
--       psql -d olist -f sql/02_load_data.sql
--   * If your CSVs live elsewhere, replace 'data/raw/' with your own path.
-- Load order respects the foreign keys (parents before children).
-- =====================================================================

\copy customers FROM 'data/raw/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy sellers FROM 'data/raw/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy product_category_translation FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true)
\copy products FROM 'data/raw/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy orders FROM 'data/raw/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy order_items FROM 'data/raw/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy payments FROM 'data/raw/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy reviews FROM 'data/raw/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy geolocation FROM 'data/raw/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;
