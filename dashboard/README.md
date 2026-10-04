# Dashboard

The Power BI dashboard **Olist E-Commerce Performance Dashboard** (4 pages) is published in the Power BI Service, along with its semantic model **Olist E-Commerce Analytics**. It was built in the browser; see [docs/powerbi_implementation.md](../docs/powerbi_implementation.md) for the model, relationships, DAX measures, page layout and verification.

- `powerbi_data/` holds the 7 CSVs the semantic model was built from. Regenerate them with `python python/export_powerbi.py`.
- Page screenshots are in [`../images/`](../images/) (`dashboard_page*.png`).
- `powerbi_dashboard.pbix` is the report and its imported data, downloaded from the Service (*File → Download this file → A copy of your report and data*). Open it in Power BI Desktop (Windows).
