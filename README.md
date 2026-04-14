# Revenue Growth Quality Analysis

## 1. Problem

Revenue is increasing across markets, but top-line growth alone does not indicate sustainable performance.

This project evaluates whether growth is driven by scalable value (AOV) or short-term volume expansion.

---

## 2. Approach

To assess growth quality, revenue is decomposed into two core drivers:

* **Volume** → number of orders
* **Value** → Average Order Value (AOV)

A **YTD-aligned year-over-year framework** is applied to ensure consistent comparison across markets.

---

## 3. Market Segmentation

Markets are classified based on growth structure:

* **At Risk** → revenue ↓, AOV ↓
* **Volume-driven** → revenue ↑, AOV ↓
* **Healthy** → revenue ↑, AOV ↑

This segmentation highlights differences between sustainable growth and monetization risk.

---

## 4. Key Insight

A significant portion of revenue growth is **volume-driven**, indicating increased transaction frequency but declining monetization efficiency.

This suggests that growth is not fully supported by pricing power or customer value.

---

## 5. Business Implication

* High-growth markets require **pricing optimization** to recover AOV
* At-risk markets need **root-cause analysis** on demand quality and discount dependency
* Healthy markets should be prioritized for **premium positioning and expansion**

---

## 6. Data Pipeline

The analysis is built on a structured data pipeline:

```
Raw Transactions
    ↓
core_transactions_enriched (data cleaning & feature engineering)
    ↓
summary_country_month (monthly aggregation)
summary_country_yoy (YTD-aligned YoY metrics)
    ↓
Tableau Dashboard
```

---

## 7. Repository Structure

```
data/
├── raw/
│   └── core_transactions_sample.csv
│
└── processed/
    ├── summary_country_month.csv
    └── summary_country_yoy.csv

sql/
├── 00_core_transactions_enriched.sql
├── 01_yoy_analysis.sql
├── 02_monthly_aggregation.sql

dashboard/
└── tableau_link.txt

images/
└── dashboard_preview.png
```

---

## 8. Tools

* **SQL** → data modeling, aggregation, YTD alignment
* **Tableau** → interactive dashboard design and visualization

---

## 9. Dashboard

👉 Tableau Public:
[(https://public.tableau.com/views/Global_Sales_Analytics_Monetization_YujinJeon/ExecutiveOverview?:language=en-US&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)]

---

## 10. Notes

Due to file size constraints, only a sample of raw data is provided.
All transformations are fully reproducible using the SQL scripts in this repository.
