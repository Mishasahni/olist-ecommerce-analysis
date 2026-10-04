"""
Olist data cleaning & validation.

Reads the raw Olist CSVs from data/raw/, runs data-quality checks, adds the
derived columns used throughout the project, and writes Power-BI-ready files
to data/cleaned/.

Run from the project root:
    python python/data_cleaning.py

Cleaning decisions (see docs/notes.md for full reasoning):
- No orders or payments are dropped. Anomalies are flagged instead, so that
  Python totals reconcile with the SQL analysis run on the raw tables.
- Missing product categories -> "unknown"; categories translated to English.
- Delivery status is only evaluated for orders with status "delivered" that
  have both a customer delivery date and an estimated delivery date
  (otherwise "not_applicable"). Same rule is used in SQL and Power BI.
- Customer retention uses customer_unique_id (customer_id is per-order).
"""

from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
CLEAN = ROOT / "data" / "cleaned"

DATE_COLUMNS = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date",
]


def load_raw():
    orders = pd.read_csv(RAW / "olist_orders_dataset.csv", parse_dates=DATE_COLUMNS)
    order_items = pd.read_csv(
        RAW / "olist_order_items_dataset.csv", parse_dates=["shipping_limit_date"]
    )
    products = pd.read_csv(RAW / "olist_products_dataset.csv")
    customers = pd.read_csv(RAW / "olist_customers_dataset.csv")
    sellers = pd.read_csv(RAW / "olist_sellers_dataset.csv")
    reviews = pd.read_csv(
        RAW / "olist_order_reviews_dataset.csv",
        parse_dates=["review_creation_date", "review_answer_timestamp"],
    )
    payments = pd.read_csv(RAW / "olist_order_payments_dataset.csv")
    translation = pd.read_csv(RAW / "product_category_name_translation.csv")
    return orders, order_items, products, customers, sellers, reviews, payments, translation


def run_quality_checks(orders, order_items, products, customers, sellers, reviews, payments):
    """Print data-quality findings. Nothing is modified here."""
    tables = {
        "orders": orders, "order_items": order_items, "products": products,
        "customers": customers, "sellers": sellers, "reviews": reviews,
        "payments": payments,
    }
    print("=== Row counts / duplicate rows / columns with nulls ===")
    for name, df in tables.items():
        nulls = df.isna().sum()
        print(f"{name:12s} rows={len(df):>7,}  dup_rows={df.duplicated().sum()}  "
              f"null_cols={dict(nulls[nulls > 0])}")

    print("\n=== Key uniqueness ===")
    print("orders.order_id unique:", orders["order_id"].is_unique)
    print("customers.customer_id unique:", customers["customer_id"].is_unique)
    print("orders with >1 review:", reviews["order_id"].duplicated().sum())

    print("\n=== Referential integrity ===")
    print("orders without customer:", (~orders["customer_id"].isin(customers["customer_id"])).sum())
    print("items without order:", (~order_items["order_id"].isin(orders["order_id"])).sum())
    print("items without product:", (~order_items["product_id"].isin(products["product_id"])).sum())
    print("items without seller:", (~order_items["seller_id"].isin(sellers["seller_id"])).sum())
    print("payments without order:", (~payments["order_id"].isin(orders["order_id"])).sum())
    print("reviews without order:", (~reviews["order_id"].isin(orders["order_id"])).sum())
    print("orders without items:", (~orders["order_id"].isin(order_items["order_id"])).sum())

    print("\n=== Date / value checks ===")
    delivered_no_date = (orders["order_status"] == "delivered") & orders["order_delivered_customer_date"].isna()
    print("status=delivered but no delivery date:", delivered_no_date.sum())
    print("delivered before purchase:",
          (orders["order_delivered_customer_date"] < orders["order_purchase_timestamp"]).sum())
    print("approved before purchase:",
          (orders["order_approved_at"] < orders["order_purchase_timestamp"]).sum())
    print("handed to carrier before approval:",
          (orders["order_delivered_carrier_date"] < orders["order_approved_at"]).sum())
    print("items with price <= 0:", (order_items["price"] <= 0).sum())
    print("items with freight < 0:", (order_items["freight_value"] < 0).sum())
    print("payments with installments <= 0:", (payments["payment_installments"] <= 0).sum())
    print("payments with value <= 0:", (payments["payment_value"] <= 0).sum())
    print("review scores outside 1-5:", (~reviews["review_score"].between(1, 5)).sum())
    print("products with no category:", products["product_category_name"].isna().sum())


def clean_products(products, translation):
    products = products.copy()
    products["product_category_name"] = products["product_category_name"].fillna("unknown")
    products = products.merge(translation, on="product_category_name", how="left")
    # Two Portuguese categories have no English translation; keep the original name.
    products["product_category_name_english"] = products[
        "product_category_name_english"
    ].fillna(products["product_category_name"])
    return products


def add_delivery_columns(orders):
    orders = orders.copy()
    delivered = orders["order_delivered_customer_date"]
    estimated = orders["order_estimated_delivery_date"]
    evaluable = (
        (orders["order_status"] == "delivered") & delivered.notna() & estimated.notna()
    )

    orders["delivery_status"] = np.select(
        [evaluable & (delivered > estimated), evaluable],
        ["late", "on_time"],
        default="not_applicable",
    )
    # 1 = late, 0 = on time, empty = not evaluable (undelivered / missing dates)
    orders["is_late"] = pd.Series(
        np.where(evaluable, (delivered > estimated).astype(int), np.nan), index=orders.index
    ).astype("Int64")
    delivered = delivered.where(evaluable)
    orders["delivery_days"] = (
        (delivered - orders["order_purchase_timestamp"]).dt.total_seconds() / 86400
    ).round(2)
    orders["days_vs_estimate"] = ((delivered - estimated).dt.total_seconds() / 86400).round(2)
    return orders


def build_orders(orders, order_items, customers, reviews, payments):
    orders = add_delivery_columns(orders)
    orders["purchase_month"] = orders["order_purchase_timestamp"].dt.to_period("M").astype(str)

    item_totals = order_items.groupby("order_id").agg(
        items_count=("order_item_id", "count"),
        product_value=("price", "sum"),
        freight_value=("freight_value", "sum"),
    )
    payment_totals = payments.groupby("order_id").agg(
        payment_value=("payment_value", "sum"),
        payment_installments=("payment_installments", "max"),
    )
    # Main payment type = the type carrying the largest share of the order's value.
    main_payment_type = (
        payments.sort_values("payment_value", ascending=False)
        .drop_duplicates("order_id")
        .set_index("order_id")["payment_type"]
        .rename("main_payment_type")
    )
    # ~0.6% of orders have more than one review; use the average score per order.
    review_scores = reviews.groupby("order_id")["review_score"].mean().rename("review_score")

    orders = (
        orders.merge(customers[["customer_id", "customer_unique_id", "customer_state"]],
                     on="customer_id", how="left")
        .merge(item_totals, on="order_id", how="left")
        .merge(payment_totals, on="order_id", how="left")
        .merge(main_payment_type, on="order_id", how="left")
        .merge(review_scores, on="order_id", how="left")
    )
    orders["items_count"] = orders["items_count"].fillna(0).astype(int)
    orders["order_total_value"] = orders["product_value"] + orders["freight_value"]

    # Customer retention: count orders per real customer (customer_unique_id).
    order_counts = orders.groupby("customer_unique_id")["order_id"].nunique()
    orders["customer_order_count"] = orders["customer_unique_id"].map(order_counts)
    orders["customer_type"] = np.where(orders["customer_order_count"] > 1, "repeat", "one_time")
    return orders


def build_customer_segments(orders):
    """One row per customer_unique_id (Power BI customer dimension)."""
    seg = orders.groupby("customer_unique_id").agg(
        customer_state=("customer_state", "first"),
        order_count=("order_id", "nunique"),
        product_value=("product_value", "sum"),
        payment_value=("payment_value", "sum"),
        first_purchase=("order_purchase_timestamp", "min"),
        last_purchase=("order_purchase_timestamp", "max"),
    ).reset_index()
    seg["customer_type"] = np.where(seg["order_count"] > 1, "repeat", "one_time")
    return seg


def validate(orders, segments):
    print("\n=== Validation of derived logic ===")
    freq = segments["order_count"].value_counts().sort_index()
    print("Customer order-frequency distribution (customer_unique_id):")
    print(freq.to_string())
    print("Customer types:", segments["customer_type"].value_counts().to_dict())

    per_order_id = orders.groupby("customer_id")["order_id"].nunique()
    print("customer_id with >1 order (shows why customer_id can't be used):",
          (per_order_id > 1).sum())

    status = orders["delivery_status"].value_counts()
    evaluated = status.get("late", 0) + status.get("on_time", 0)
    print("Delivery status:", status.to_dict())
    print(f"Late rate among delivered orders: {status.get('late', 0) / evaluated:.2%}")
    assert not (orders.loc[orders["order_delivered_customer_date"].isna(), "delivery_status"]
                != "not_applicable").any(), "undelivered orders must not be classified"
    assert orders["order_id"].is_unique
    assert segments["customer_unique_id"].is_unique


def main():
    orders, order_items, products, customers, sellers, reviews, payments, translation = load_raw()
    run_quality_checks(orders, order_items, products, customers, sellers, reviews, payments)

    products_clean = clean_products(products, translation)
    orders_clean = build_orders(orders, order_items, customers, reviews, payments)
    segments = build_customer_segments(orders_clean)
    validate(orders_clean, segments)

    CLEAN.mkdir(parents=True, exist_ok=True)
    outputs = {
        "orders_clean.csv": orders_clean,
        "order_items_clean.csv": order_items,
        "products_clean.csv": products_clean,
        "customers_clean.csv": customers,
        "customer_segments.csv": segments,
        "sellers_clean.csv": sellers,
        "reviews_clean.csv": reviews,
        "payments_clean.csv": payments,
    }
    print("\n=== Writing cleaned files ===")
    for filename, df in outputs.items():
        df.to_csv(CLEAN / filename, index=False)
        print(f"{filename:24s} {df.shape}")


if __name__ == "__main__":
    main()
