import pandas as pd

orders = pd.read_csv(
    "data/cleaned/orders_clean.csv",
    parse_dates=[
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_estimated_delivery_date"
    ]
)

order_items = pd.read_csv("data/cleaned/order_items_clean.csv")
products = pd.read_csv("data/cleaned/products_clean.csv")
customers = pd.read_csv("data/cleaned/customers_clean.csv")
sellers = pd.read_csv("data/cleaned/sellers_clean.csv")
reviews = pd.read_csv("data/cleaned/reviews_clean.csv")
payments = pd.read_csv("data/cleaned/payments_clean.csv")

#late deliveries relation to customer reviews
print(orders["late_delivery"].value_counts())
delivery_reviews = orders.merge(
    reviews[["order_id", "review_score"]],
    on="order_id",
    how="inner"
)
print(
    delivery_reviews
    .groupby("late_delivery")["review_score"]
    .mean()
)

#Revenue by product category
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

print(category_revenue.head(10))
category_units_sold = (
    category_sales
    .groupby("product_category_name")
    .size()
    .sort_values(ascending=False)
)

print(category_units_sold.head(10))
category_avg_price = (
    category_sales
    .groupby("product_category_name")["price"]
    .mean()
    .sort_values(ascending=False)
)

print(category_avg_price.head(10))
category_summary = pd.DataFrame({
    "revenue": category_revenue,
    "units_sold": category_units_sold,
    "avg_price": category_avg_price
})

print(
    category_summary
    .sort_values("revenue", ascending=False)
    .head(10)
)

#How many unique customers are one-time buyers vs repeat buyers?
customer_orders = orders.merge(
    customers[["customer_id", "customer_unique_id"]],
    on="customer_id",
    how="left"
)
customer_order_count = (
    customer_orders
    .groupby("customer_unique_id")["order_id"]
    .count()
)

print(customer_order_count.value_counts().sort_index())

customer_type = customer_order_count.apply(
    lambda x: "repeat" if x > 1 else "one_time"
)

print(customer_type.value_counts())

#revenue contribution by customer type.
customer_orders["customer_type"] = customer_orders[
    "customer_unique_id"
].map(customer_type)

customer_revenue = (
    customer_orders
    .groupby("customer_type")["order_value"]
    .sum()
)

print(customer_revenue)
#average revenue per customer type
customer_value = (
    customer_orders
    .groupby("customer_unique_id")["order_value"]
    .sum()
    .reset_index()
)
customer_value["customer_type"] = customer_value[
    "customer_unique_id"
].map(customer_type)
average_revenue = (
    customer_value
    .groupby("customer_type")["order_value"]
    .mean()
)

print(average_revenue)

#customer order frequency
print(
    customer_order_count
    .value_counts()
    .sort_index()
)
# Late delivery rate by product category

order_categories = order_items[
    ["order_id", "product_id"]
].merge(
    products[["product_id", "product_category_name"]],
    on="product_id",
    how="left"
).merge(
    orders[["order_id", "late_delivery"]],
    on="order_id",
    how="left"
)
order_categories = order_categories.drop_duplicates(
    ["order_id", "product_category_name"]
)
category_late_rate = (
    order_categories
    .groupby("product_category_name")["late_delivery"]
    .mean()
    .sort_values(ascending=False)
    * 100
)

print(category_late_rate.head(10))

category_delivery = (
    order_categories
    .groupby("product_category_name")
    .agg(
        orders=("order_id", "count"),
        late_rate=("late_delivery", "mean")
    )
)

category_delivery["late_rate"] = (
    category_delivery["late_rate"] * 100
)

print(
    category_delivery
    .sort_values("orders", ascending=False)
    .head(10)
)
# Monthly orders and revenue

orders["order_month"] = (
    orders["order_purchase_timestamp"].dt.to_period("M")
)

monthly_performance = (
    orders
    .groupby("order_month")
    .agg(
        orders=("order_id", "count"),
        revenue=("order_value", "sum")
    )
)

print(monthly_performance)
# Revenue and usage by payment type

payment_summary = (
    payments
    .groupby("payment_type")
    .agg(
        transactions=("order_id", "count"),
        payment_value=("payment_value", "sum")
    )
    .sort_values("payment_value", ascending=False)
)

print(payment_summary)
# Review score distribution

review_distribution = (
    reviews["review_score"]
    .value_counts()
    .sort_index()
)

print(review_distribution)
category_review_delivery = (
    order_categories
    .merge(
        reviews[["order_id", "review_score"]],
        on="order_id",
        how="left"
    )
    .groupby("product_category_name")
    .agg(
        orders=("order_id", "count"),
        late_rate=("late_delivery", "mean"),
        avg_review=("review_score", "mean")
    )
)

category_review_delivery["late_rate"] *= 100

category_review_delivery = category_review_delivery.sort_values(
    "orders",
    ascending=False
)

print(category_review_delivery.head(15))