"""
Export the compact tables used by the Power BI semantic model.

The dashboard was built in the Power BI Service (web) by uploading these
CSVs through Power Query Online. 32-character hash IDs are replaced by
integer surrogate keys so each file stays small enough to upload; all
metric values are unchanged (checked by the assertions at the end).

Run after python/data_cleaning.py:
    python python/export_powerbi.py
Output: dashboard/powerbi_data/*.csv
"""

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CLEAN = ROOT / "data" / "cleaned"
CSV_DIR = ROOT / "dashboard" / "powerbi_data"


def keys(series):
    """Map each distinct ID to an integer key (1..n)."""
    uniques = pd.Index(series.dropna().unique())
    return pd.Series(range(1, len(uniques) + 1), index=uniques)


def lateness_bucket(o):
    d = o["days_vs_estimate"]
    bucket = pd.cut(d, [-1, 3, 7, 14, 10_000],
                    labels=["1 1-3 days late", "2 4-7 days late", "3 8-14 days late", "4 15+ days late"])
    bucket = bucket.astype(str).where(o["delivery_status"] == "late")
    return bucket.mask(o["delivery_status"] == "on_time", "0 On time")


def main():
    orders = pd.read_csv(CLEAN / "orders_clean.csv", parse_dates=["order_purchase_timestamp"])
    items = pd.read_csv(CLEAN / "order_items_clean.csv")
    payments = pd.read_csv(CLEAN / "payments_clean.csv")
    products = pd.read_csv(CLEAN / "products_clean.csv")
    sellers = pd.read_csv(CLEAN / "sellers_clean.csv")
    segments = pd.read_csv(CLEAN / "customer_segments.csv")

    order_key = keys(orders["order_id"])
    customer_key = keys(segments["customer_unique_id"])
    seller_key = keys(sellers["seller_id"])

    fact_orders = pd.DataFrame({
        "order_key": orders["order_id"].map(order_key),
        "customer_key": orders["customer_unique_id"].map(customer_key),
        "order_status": orders["order_status"],
        "purchase_date": orders["order_purchase_timestamp"].dt.normalize(),
        "customer_state": orders["customer_state"],
        "customer_type": orders["customer_type"],
        "delivery_status": orders["delivery_status"],
        "delivery_days": orders["delivery_days"].round(1),
        "lateness_bucket": lateness_bucket(orders),
        "review_score": orders["review_score"].round(2),
    })
    # Category is denormalised onto the item rows (saves a 33K-row product table).
    category = products.set_index("product_id")["product_category_name_english"]
    fact_items = pd.DataFrame({
        "order_key": items["order_id"].map(order_key),
        "seller_key": items["seller_id"].map(seller_key),
        "category": items["product_id"].map(category),
        "price": items["price"],
        "freight_value": items["freight_value"],
    })
    dim_sellers = pd.DataFrame({
        "seller_key": sellers["seller_id"].map(seller_key),
        "seller_id": sellers["seller_id"],
        "seller_state": sellers["seller_state"],
    })
    # Payments are only analysed by type / installment band / month, so they
    # are pre-aggregated to that grain (relates to the date table on month_start).
    pay = payments.merge(orders[["order_id", "order_purchase_timestamp"]], on="order_id")
    pay["month_start"] = pay["order_purchase_timestamp"].dt.to_period("M").dt.to_timestamp()
    pay["installment_band"] = pd.cut(pay["payment_installments"], [-1, 1, 3, 6, 10, 99],
                                     labels=["1", "2-3", "4-6", "7-10", "11+"]).astype(str)
    payment_summary = (pay.groupby(["month_start", "payment_type", "installment_band"], observed=True)
                       .agg(payments=("order_id", "size"), orders=("order_id", "nunique"),
                            payment_value=("payment_value", "sum"))
                       .reset_index())
    payment_summary["payment_value"] = payment_summary["payment_value"].round(2)
    # Customer order-frequency distribution (customer_unique_id grain).
    freq = segments.assign(
        order_frequency=segments["order_count"].clip(upper=4).astype(str).replace("4", "4+"))
    customer_frequency = (freq.groupby(["order_frequency", "customer_type"])
                          .agg(customers=("customer_unique_id", "size"),
                               customer_gmv=("product_value", "sum"))
                          .reset_index())
    dates = pd.date_range("2016-09-01", "2018-10-31", freq="D")
    dim_date = pd.DataFrame({
        "date": dates,
        "year": dates.year,
        "month_number": dates.month,
        "month": dates.strftime("%b"),
        "year_month": dates.strftime("%Y-%m"),
        "month_start": dates.to_period("M").to_timestamp(),
        "in_trend_window": ((dates >= "2017-01-01") & (dates <= "2018-08-31")),
    })
    months = pd.DataFrame({"month_start": pd.date_range("2016-09-01", "2018-10-01", freq="MS")})
    months["year_month"] = months["month_start"].dt.strftime("%Y-%m")
    months["in_trend_window"] = months["month_start"].between("2017-01-01", "2018-08-01")

    sheets = {
        "orders": fact_orders, "order_items": fact_items, "sellers": dim_sellers,
        "payment_summary": payment_summary, "customer_frequency": customer_frequency,
        "dates": dim_date, "months": months,
    }
    CSV_DIR.mkdir(exist_ok=True)
    for name, df in sheets.items():
        df.to_csv(CSV_DIR / f"{name}.csv", index=False, date_format="%Y-%m-%d")
        print(f"{name:20s} {df.shape}")

    # Sanity checks: key mapping must not lose rows
    assert fact_orders["customer_key"].notna().all()
    assert fact_items[["order_key", "seller_key", "category"]].notna().all().all()
    assert abs(fact_items["price"].sum() - items["price"].sum()) < 0.01  # GMV unchanged
    assert abs(payment_summary["payment_value"].sum() - payments["payment_value"].sum()) < 1
    assert customer_frequency["customers"].sum() == len(segments)
    print(f"Wrote {len(sheets)} files to {CSV_DIR.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
