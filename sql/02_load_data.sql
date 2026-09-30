-- Load orders
\copy orders FROM '/Users/nimishasahni/Downloads/archive/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Load customers
\copy customers FROM '/Users/nimishasahni/Downloads/archive/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Load sellers
\copy sellers FROM '/Users/nimishasahni/Downloads/archive/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Load products
\copy products FROM '/Users/nimishasahni/Downloads/archive/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Load payments
\copy payments FROM '/Users/nimishasahni/Downloads/archive/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Load reviews
\copy reviews FROM '/Users/nimishasahni/Downloads/archive/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Load order items
\copy order_items FROM '/Users/nimishasahni/Downloads/archive/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Load geolocation
\copy geolocation FROM '/Users/nimishasahni/Downloads/archive/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Load product category translation
\copy product_category_translation
FROM '/Users/nimishasahni/Downloads/archive/product_category_name_translation.csv'
WITH (FORMAT csv, HEADER true);