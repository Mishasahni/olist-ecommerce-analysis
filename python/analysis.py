"""
Olist business analysis (Python/Pandas).

Answers the project's business questions using the cleaned files produced by
python/data_cleaning.py. Summary tables are printed and saved to outputs/.

Run from anywhere:
    python python/analysis.py

Metric definitions (identical in SQL and Power BI, see docs/notes.md):
- GMV (product sales value) = SUM(order_items.price)
- Freight value             = SUM(order_items.freight_value)
- Payment value             = SUM(payments.payment_value)
- AOV                       = GMV / number of orders with at least one item
- Late delivery             = delivered date > estimated date, evaluated only for
                              status "delivered" orders with both dates present
"""

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CLEAN = ROOT / "data" / "cleaned"
OUT = ROOT / "outputs"

# Sep-2016 to Dec-2016 contain very few orders and Sep/Oct-2018 contain almost
# only canceled orders (data extract ends), so monthly trends use this window.
TREND_START, TREND_END = "2017-01", "2018-08"

pd.set_option("display.width", 140)
pd.set_option("display.max_columns", 20)
pd.set_option("display.float_format", "{:,.2f}".format)


def load():
    orders = pd.read_csv(CLEAN / "orders_clean.csv",
                         parse_dates=["order_purchase_timestamp", "order_delivered_customer_date",
                                      "order_estimated_delivery_date"])
    items = pd.read_csv(CLEAN / "order_items_clean.csv")
    products = pd.read_csv(CLEAN / "products_clean.csv")
    segments = pd.read_csv(CLEAN / "customer_segments.csv")
    sellers = pd.read_csv(CLEAN / "sellers_clean.csv")
    payments = pd.read_csv(CLEAN / "payments_clean.csv")
    items = items.merge(products[["product_id", "product_category_name_english"]],
                        on="product_id", how="left").rename(
        columns={"product_category_name_english": "category"})
    return orders, items, segments, sellers, payments


def section(title):
    print(f"\n{'=' * 70}\n{title}\n{'=' * 70}")


def save(df, name):
    OUT.mkdir(exist_ok=True)
    df.to_csv(OUT / f"{name}.csv")


def overall_kpis(orders, items, segments, payments):
    section("A. Overall performance")
    orders_with_items = orders.loc[orders["items_count"] > 0, "order_id"].nunique()
    gmv = items["price"].sum()
    kpis = pd.Series({
        "Total orders (all statuses)": len(orders),
        "Orders with items": orders_with_items,
        "Unique customers (customer_unique_id)": segments["customer_unique_id"].nunique(),
        "GMV / product sales value": gmv,
        "Freight value": items["freight_value"].sum(),
        "Payment value": payments["payment_value"].sum(),
        "Units sold (order items)": len(items),
        "AOV (GMV / orders with items)": gmv / orders_with_items,
        "Average item price": items["price"].mean(),
        "Active sellers": items["seller_id"].nunique(),
    })
    print(kpis.to_string(float_format="{:,.2f}".format))

    status = orders["order_status"].value_counts().to_frame("orders")
    status["share_pct"] = status["orders"] / status["orders"].sum() * 100
    print("\nOrder status distribution:\n", status)
    canceled_gmv = orders.loc[orders["order_status"].isin(["canceled", "unavailable"]),
                              "product_value"].sum()
    print(f"\nGMV from canceled/unavailable orders: {canceled_gmv:,.2f} "
          f"({canceled_gmv / gmv:.2%} of GMV)")
    save(kpis.to_frame("value"), "kpis")
    save(status, "order_status")


def monthly_trends(orders):
    section(f"B. Monthly trends ({TREND_START} to {TREND_END})")
    monthly = (
        orders[orders["items_count"] > 0]
        .groupby("purchase_month")
        .agg(orders=("order_id", "nunique"), gmv=("product_value", "sum"))
    )
    print("Months excluded from trend (partial data):")
    print(monthly[(monthly.index < TREND_START) | (monthly.index > TREND_END)])
    monthly = monthly.loc[TREND_START:TREND_END].copy()
    monthly["aov"] = monthly["gmv"] / monthly["orders"]
    print(monthly)

    gmv_2017 = monthly.loc["2017-01":"2017-08", "gmv"].sum()
    gmv_2018 = monthly.loc["2018-01":"2018-08", "gmv"].sum()
    print(f"\nGMV Jan-Aug 2018 vs Jan-Aug 2017: {gmv_2018 / gmv_2017 - 1:+.1%}")
    print(f"Peak month by orders: {monthly['orders'].idxmax()} ({monthly['orders'].max():,})")
    print(f"AOV range across months: {monthly['aov'].min():,.2f} - {monthly['aov'].max():,.2f}")
    save(monthly, "monthly_trends")


def category_performance(items):
    section("C. Category performance")
    cat = items.groupby("category").agg(
        gmv=("price", "sum"), units=("order_item_id", "count"),
        orders=("order_id", "nunique"), avg_price=("price", "mean"),
    ).sort_values("gmv", ascending=False)
    cat["gmv_share_pct"] = cat["gmv"] / cat["gmv"].sum() * 100
    cat["cumulative_share_pct"] = cat["gmv_share_pct"].cumsum()
    print(cat.head(15))
    print(f"\nCategories: {len(cat)}. Top 10 categories = "
          f"{cat['gmv_share_pct'].head(10).sum():.1f}% of GMV")
    print("\nTop 10 by units sold:\n", cat.sort_values("units", ascending=False).head(10)[["units", "gmv"]])
    save(cat, "category_performance")


def customer_analysis(orders, segments):
    section("D. Customer retention (customer_unique_id)")
    freq = segments["order_count"].value_counts().sort_index().rename("customers")
    print("Order-frequency distribution:\n", freq.to_string())

    by_type = segments.groupby("customer_type").agg(
        customers=("customer_unique_id", "count"),
        orders=("order_count", "sum"),
        gmv=("product_value", "sum"),
        avg_gmv_per_customer=("product_value", "mean"),
    )
    by_type["customer_share_pct"] = by_type["customers"] / by_type["customers"].sum() * 100
    by_type["gmv_share_pct"] = by_type["gmv"] / by_type["gmv"].sum() * 100
    print("\n", by_type)
    ratio = by_type.loc["repeat", "avg_gmv_per_customer"] / by_type.loc["one_time", "avg_gmv_per_customer"]
    print(f"\nRepeat customers spend {ratio:.1f}x more per customer than one-time customers "
          f"(over the dataset window).")

    # Per-order value: are repeat customers' individual orders bigger?
    aov = orders[orders["items_count"] > 0].groupby("customer_type")["product_value"].mean()
    print("Average GMV per order by customer type:\n", aov.to_string())
    save(freq.to_frame(), "customer_frequency")
    save(by_type, "customer_type_summary")


def delivery_and_reviews(orders):
    section("E/F. Delivery performance & customer satisfaction")
    delivered = orders[orders["delivery_status"].isin(["on_time", "late"])]
    print(f"Delivered orders evaluated: {len(delivered):,} "
          f"(excluded, not delivered / missing dates: "
          f"{(orders['delivery_status'] == 'not_applicable').sum():,})")
    print(f"Late delivery rate: {delivered['is_late'].mean():.2%}")
    print(f"Average delivery time: {delivered['delivery_days'].mean():.1f} days "
          f"(median {delivered['delivery_days'].median():.1f})")

    perf = delivered.groupby("delivery_status").agg(
        orders=("order_id", "count"),
        avg_delivery_days=("delivery_days", "mean"),
        avg_review=("review_score", "mean"),
        pct_1_or_2_star=("review_score", lambda s: (s.dropna() <= 2).mean() * 100),
        pct_5_star=("review_score", lambda s: (s.dropna() == 5).mean() * 100),
    )
    print("\n", perf)
    print("\nLate deliveries are strongly associated with lower review scores "
          "(association, not proven causation).")

    reviews_dist = orders["review_score"].round().value_counts().sort_index()
    print("\nReview score distribution (order level):\n", reviews_dist.to_string())

    # Review score by how late the order arrived
    # Estimated dates have no time component, so an order delivered later on
    # the estimated day counts as late (0-1 days late falls in the first bucket).
    labels = ["1-3 days late", "4-7 days late", "8-14 days late", "15+ days late"]
    days_late = (delivered["order_delivered_customer_date"]
                 - delivered["order_estimated_delivery_date"]).dt.total_seconds() / 86400
    late_bucket = pd.cut(days_late, [-1, 3, 7, 14, 10_000], labels=labels).astype(str)
    lateness = delivered.assign(lateness=pd.Categorical(
        late_bucket.where(delivered["is_late"] == 1, "on time"), ["on time"] + labels, ordered=True))
    by_lateness = lateness.groupby("lateness", observed=True).agg(
        orders=("order_id", "count"), avg_review=("review_score", "mean"))
    print("\n", by_lateness)

    monthly_late = delivered.groupby("purchase_month")["is_late"].mean().mul(100).loc[TREND_START:TREND_END]
    print("\nMonthly late rate (%) — highest months:\n", monthly_late.sort_values(ascending=False).head(4).to_string())
    by_state = delivered.groupby("customer_state").agg(
        orders=("order_id", "count"), late_rate=("is_late", "mean"),
        avg_delivery_days=("delivery_days", "mean"))
    by_state["late_rate"] *= 100
    print("\nDelivery by customer state (top 10 by orders):\n",
          by_state.sort_values("orders", ascending=False).head(10))
    save(perf, "delivery_vs_reviews")
    save(by_lateness, "review_by_lateness")
    save(monthly_late.to_frame("late_rate_pct"), "monthly_late_rate")
    save(by_state, "delivery_by_state")


def payment_analysis(orders, payments):
    section("G. Payment behaviour")
    by_type = payments.groupby("payment_type").agg(
        payments=("order_id", "count"), orders=("order_id", "nunique"),
        payment_value=("payment_value", "sum"), avg_payment=("payment_value", "mean"))
    by_type["value_share_pct"] = by_type["payment_value"] / by_type["payment_value"].sum() * 100
    print(by_type.sort_values("payment_value", ascending=False))

    cc = payments[payments["payment_type"] == "credit_card"]
    print(f"\nCredit-card payments using >1 installment: {(cc['payment_installments'] > 1).mean():.1%}")
    inst = cc.groupby(pd.cut(cc["payment_installments"], [0, 1, 3, 6, 10, 24],
                             labels=["1", "2-3", "4-6", "7-10", "11+"]), observed=True).agg(
        payments=("order_id", "count"), avg_payment=("payment_value", "mean"))
    print("Credit-card installments vs average payment:\n", inst)
    multi = orders["main_payment_type"].notna() & (
        payments.groupby("order_id")["payment_type"].nunique().reindex(orders["order_id"]).values > 1)
    print(f"Orders paid with more than one payment method: {multi.sum():,}")
    save(by_type, "payment_types")
    save(inst, "credit_card_installments")


def seller_analysis(orders, items, sellers):
    section("H. Seller performance")
    seller = items.groupby("seller_id").agg(
        gmv=("price", "sum"), units=("order_item_id", "count"), orders=("order_id", "nunique"))
    seller = seller.sort_values("gmv", ascending=False)
    n = len(seller)
    top10pct = seller["gmv"].head(int(n * 0.1)).sum() / seller["gmv"].sum()
    print(f"Sellers with sales: {n:,}. Top 10% of sellers = {top10pct:.1%} of GMV")
    print(f"Sellers with fewer than 10 orders: {(seller['orders'] < 10).mean():.1%}")

    # Seller delivery & review performance (an order with items from several
    # sellers is attributed to each of them).
    seller_orders = items[["order_id", "seller_id"]].drop_duplicates().merge(
        orders[["order_id", "is_late", "review_score"]], on="order_id")
    quality = seller_orders.groupby("seller_id").agg(
        late_rate=("is_late", "mean"), avg_review=("review_score", "mean"))
    seller = seller.join(quality).join(sellers.set_index("seller_id")["seller_state"])
    seller["late_rate"] *= 100
    print("\nTop 10 sellers by GMV:\n", seller.head(10))

    established = seller[seller["orders"] >= 50]
    low = established[established["avg_review"] < 3.5]
    print(f"\nSellers with >=50 orders: {len(established):,}; of these {len(low)} average "
          f"below 3.5 stars and they account for {low['gmv'].sum() / seller['gmv'].sum():.1%} of GMV")
    others = established[established["avg_review"] >= 3.5]
    print(f"Avg late rate of those low-rated sellers: {low['late_rate'].mean():.1f}% "
          f"vs {others['late_rate'].mean():.1f}% for the other established sellers")
    save(seller, "seller_performance")


def main():
    orders, items, segments, sellers, payments = load()
    overall_kpis(orders, items, segments, payments)
    monthly_trends(orders)
    category_performance(items)
    customer_analysis(orders, segments)
    delivery_and_reviews(orders)
    payment_analysis(orders, payments)
    seller_analysis(orders, items, sellers)
    print(f"\nSummary tables saved to {OUT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
