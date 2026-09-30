import pandas as pd
import numpy as np

orders = pd.read_csv("data/raw/olist_orders_dataset.csv")
order_items = pd.read_csv("data/raw/olist_order_items_dataset.csv")
products = pd.read_csv("data/raw/olist_products_dataset.csv")
customers = pd.read_csv("data/raw/olist_customers_dataset.csv")
sellers = pd.read_csv("data/raw/olist_sellers_dataset.csv")
reviews = pd.read_csv("data/raw/olist_order_reviews_dataset.csv")
payments = pd.read_csv("data/raw/olist_order_payments_dataset.csv")


datasets = {
    "orders": orders,
    "order_items": order_items,
    "products": products,
    "customers": customers,
    "sellers": sellers,
    "reviews": reviews,
    "payments": payments
}

for name, df in datasets.items():
    print(f"\n{name}")
    print(df.isna().sum())

print(
    orders[orders["order_delivered_customer_date"].isna()]           
    ["order_status"]
    .value_counts()
)

print(
    orders[
        (orders["order_status"] == "delivered") &
        (orders["order_delivered_customer_date"].isna())
    ]
)
print(
    orders[
        (orders["order_status"] == "delivered") &
        (orders["order_delivered_customer_date"].isna())
    ][
        [
            "order_id",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date"
        ]
    ]
)
print(
    orders[
        (orders["order_status"] == "delivered") &
        (orders["order_delivered_customer_date"].isna())
    ][[
        "order_id",
        "order_delivered_carrier_date",
        "order_delivered_customer_date"
    ]].to_string(index=False)
)


orders_clean = orders[
    ~(
        (orders["order_status"] == "delivered") &
        (orders["order_delivered_customer_date"].isna())
    )
].copy()

print(orders.shape)
print(orders_clean.shape)

print(
    products[products["product_category_name"].isna()]
    .to_string(index=False)
)

sold_product_ids = order_items["product_id"].unique()

missing_category_products = products[
    products["product_category_name"].isna()
]

print(
    missing_category_products["product_id"].isin(sold_product_ids).sum()
)
print(
    order_items[
        order_items["product_id"].isin(
            products[products["product_category_name"].isna()]["product_id"]
        )
    ].head(10)
)
products["product_category_name"] = products["product_category_name"].fillna("unknown")

print(
    products[products["product_category_name"].isna()]
    .to_string(index=False)
)
print(
    products[
        products[
            ["product_weight_g", "product_length_cm", "product_height_cm", "product_width_cm"]
        ].isna().any(axis=1)
    ].to_string(index=False)
)
print(
    reviews[reviews["review_comment_message"].isna()]
    ["review_score"]
    .value_counts()
)
date_columns = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date"
]

for col in date_columns:
    orders[col] = pd.to_datetime(orders[col])

for name, df in datasets.items():
    print(name, "duplicates:", df.duplicated().sum())
    print(order_items[order_items["price"] <= 0])

    print(order_items[order_items["freight_value"] < 0])

invalid_delivery_dates = orders_clean[
    orders_clean["order_delivered_customer_date"] <
    orders_clean["order_purchase_timestamp"]
]

print("Invalid delivery dates:", len(invalid_delivery_dates))

invalid_approval_dates = orders[
    orders["order_approved_at"] <
    orders["order_purchase_timestamp"]
]

print("Invalid approval dates:", len(invalid_approval_dates))

invalid_carrier_dates = orders[
    orders["order_delivered_carrier_date"] <
    orders["order_approved_at"]
]

print("Invalid carrier dates:", len(invalid_carrier_dates))

print(
    orders[
        orders["order_delivered_carrier_date"] <
        orders["order_approved_at"]
    ][[
        "order_id",
        "order_approved_at",
        "order_delivered_carrier_date"
    ]].head(10)
)
carrier_gap = (
    orders["order_approved_at"]
    - orders["order_delivered_carrier_date"]
)

print(carrier_gap[carrier_gap > pd.Timedelta(0)].describe())

print(payments[payments["payment_value"] <= 0])
print(
    payments[payments["payment_value"] <= 0]
    .to_string(index=False)
)
print(
    orders[
        orders["order_id"].isin(
            payments[payments["payment_value"] <= 0]["order_id"]
        )
    ][["order_id", "order_status"]].to_string(index=False)
)
print(reviews[(reviews["review_score"] < 1) | (reviews["review_score"] > 5)])
print(payments[payments["payment_installments"] <= 0])
print(
    payments[payments["payment_installments"] <= 0]
    .to_string(index=False)
)
payments_clean = payments[
    payments["payment_installments"] > 0
].copy()
print(payments.shape)
print(payments_clean.shape)

print(payments[payments["payment_sequential"] <= 0])
print(orders["order_status"].value_counts())
print(payments["payment_type"].value_counts())
print(products["product_category_name"].value_counts().tail())
missing_products = ~order_items["product_id"].isin(products["product_id"])

print("Order items with missing product:", missing_products.sum())

missing_orders = ~order_items["order_id"].isin(orders["order_id"])

print("Order items with missing order:", missing_orders.sum())
missing_customers = ~orders["customer_id"].isin(customers["customer_id"])

print("Orders with missing customer:", missing_customers.sum())

print(
    "Order items with missing product:",
    (~order_items["product_id"].isin(products["product_id"])).sum()
)

print(
    "Order items with missing order:",
    (~order_items["order_id"].isin(orders["order_id"])).sum()
)

print(
    "Orders with missing customer:",
    (~orders["customer_id"].isin(customers["customer_id"])).sum()
)

print(
    "Order items with missing seller:",
    (~order_items["seller_id"].isin(sellers["seller_id"])).sum()
)

print(
    "Reviews with missing order:",
    (~reviews["order_id"].isin(orders["order_id"])).sum()
)

print(
    "Payments with missing order:",
    (~payments["order_id"].isin(orders["order_id"])).sum()
)

# Fill missing product categories
products["product_category_name"] = products["product_category_name"].fillna("unknown")

# Remove the 8 delivered orders with no customer delivery date
orders_clean = orders[
    ~(
        (orders["order_status"] == "delivered") &
        (orders["order_delivered_customer_date"].isna())
    )
].copy()

# Remove the 2 payment records with invalid installments
payments_clean = payments[
    payments["payment_installments"] > 0
].copy()

print("Orders:", orders.shape, "→", orders_clean.shape)
print("Payments:", payments.shape, "→", payments_clean.shape)

orders_clean.to_csv("data/cleaned/orders_clean.csv", index=False)
payments_clean.to_csv("data/cleaned/payments_clean.csv", index=False)
products.to_csv("data/cleaned/products_clean.csv", index=False)

orders_clean["delivery_time"] = (
    orders_clean["order_delivered_customer_date"]
    - orders_clean["order_purchase_timestamp"]
)
orders_clean["late_delivery"] = (
    orders_clean["order_delivered_customer_date"]
    > orders_clean["order_estimated_delivery_date"]
)
order_value = (
    order_items.groupby("order_id")["price"]
    .sum()
)

orders_clean = orders_clean.merge(
    order_value.rename("order_value"),
    on="order_id",
    how="left"
)
freight_cost = (
    order_items.groupby("order_id")["freight_value"]
    .sum()
)
orders_clean = orders_clean.merge(
    freight_cost.rename("freight_cost"),
    on="order_id",
    how="left"
)
customer_order_count = (
    orders_clean.groupby("customer_id")["order_id"]
    .count()
)

orders_clean = orders_clean.merge(
    customer_order_count.rename("customer_order_count"),
    on="customer_id",
    how="left"
)

orders_clean["repeat_customer"] = (
    orders_clean["customer_order_count"] > 1
)
orders_clean.to_csv(
    "data/cleaned/orders_clean.csv",
    index=False
)
print(orders_clean.columns.tolist())
order_items.to_csv("data/cleaned/order_items_clean.csv", index=False)
products.to_csv("data/cleaned/products_clean.csv", index=False)
customers.to_csv("data/cleaned/customers_clean.csv", index=False)
sellers.to_csv("data/cleaned/sellers_clean.csv", index=False)
reviews.to_csv("data/cleaned/reviews_clean.csv", index=False)
payments_clean.to_csv("data/cleaned/payments_clean.csv", index=False)

category_sales = order_items.merge(
    products[["product_id", "product_category_name"]],
    on="product_id",
    how="left"
)
category_revenue = (
    category_sales
    .groupby("product_category_name")["price"]
    .sum()
    .sort_values(ascending=False)
)

print(category_revenue)

category_units_sold = (
    category_sales
    .groupby("product_category_name")
    .size()
    .sort_values(ascending=False)
)

print(category_units_sold)

category_avg_price = (
    category_sales
    .groupby("product_category_name")["price"]
    .mean()
    .sort_values(ascending=False)
)

print(category_avg_price)

category_summary = pd.DataFrame({
    "revenue": category_revenue,
    "units_sold": category_units_sold,
    "avg_price": category_avg_price
})

print(category_summary.sort_values("revenue", ascending=False).head(10))

customer_orders = orders_clean.merge(
    customers[["customer_id", "customer_unique_id"]],
    on="customer_id",
    how="left"
)
unique_customers = customer_orders["customer_unique_id"].nunique()

customer_order_count = (
    customer_orders.groupby("customer_unique_id")["order_id"]
    .count()
)

customer_summary = customer_order_count.reset_index(
    name="customer_order_count"
)

print(customer_summary.head())

print(
    customer_summary["customer_order_count"]
    .apply(lambda x: "repeat" if x > 1 else "one_time")
    .value_counts()
)
customer_orders = customer_orders.merge(
    customer_summary,
    on="customer_unique_id",
    how="left"
)
customer_orders = customer_orders.merge(
    customer_summary,
    on="customer_unique_id",
    how="left"
)
customer_revenue = (
    customer_orders
    .assign(
        customer_type=lambda x:
        x["customer_order_count"].apply(
            lambda n: "repeat" if n > 1 else "one_time"
        )
    )
    .groupby("customer_type")["order_value"]
    .sum()
)

print(customer_revenue)
customer_value = (
    customer_orders
    .groupby("customer_unique_id")["order_value"]
    .sum()
    .reset_index()
)

customer_value = customer_value.merge(
    customer_summary,
    on="customer_unique_id",
    how="left"
)

customer_value["customer_type"] = customer_value["customer_order_count"].apply(
    lambda x: "repeat" if x > 1 else "one_time"
)
average_revenue = (
    customer_value
    .groupby("customer_type")["order_value"]
    .mean()
)

print(average_revenue)
print(
    customer_summary["customer_order_count"]
    .value_counts()
    .sort_index()
)
