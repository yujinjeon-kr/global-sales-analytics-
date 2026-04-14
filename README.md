
# Growth Quality & Monetization Analysis

## Overview

This project analyzes multi-country transaction data to evaluate whether revenue growth is driven by **scalable value (AOV)** or short-term **volume expansion**.

Rather than relying on top-line growth, the analysis focuses on **growth quality** and **monetization efficiency** across markets.

---

## Key Question

> Is revenue growth truly sustainable, or is it driven by declining value per transaction?

---

## Approach

### 1. Growth Decomposition

Revenue is broken down into two core drivers:

* **Volume** → number of orders
* **Value** → Average Order Value (AOV)

This allows identification of whether growth is structurally healthy or driven by discount-led expansion.

---

### 2. YTD-Aligned YoY Framework

To ensure fair comparison across markets:

* Year-to-date (YTD) periods are aligned
* Growth is calculated on consistent time windows

---

### 3. Market Segmentation

Markets are classified based on growth structure:

* **At Risk** → revenue ↓, AOV ↓
* **Volume-driven** → revenue ↑, AOV ↓
* **Healthy** → revenue ↑, AOV ↑

This segmentation highlights differences between sustainable growth and monetization risk.

---

## Key Insights

* A large portion of growth is **volume-driven**, indicating declining monetization efficiency
* Growth is heavily dependent on **existing users and increased transaction frequency**
* Several markets show strong revenue growth but weakening value capture

---

## Business Implications

* High-growth markets require **pricing and AOV optimization**
* At-risk markets need **root-cause analysis on demand quality and discount dependency**
* Healthy markets should be prioritized for **premium positioning and expansion**

---

## Data Pipeline

The analysis is built on a structured data pipeline:

```id="pipeline"
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

## Repository Structure

```id="structure"
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
├── tableau_link.txt
└── dashboard_preview.pdf

presentation/
└── monetization_analysis.pdf
```


---

## Dashboard

Interactive Tableau dashboard:

👉 [https://public.tableau.com/views/Global_Sales_Analytics_Monetization_YujinJeon/ExecutiveOverview?:language=en-US&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link]

Features:

* KPI overview (Revenue, Orders, Users, AOV)
* Monthly trends
* Growth decomposition by country
* Market segmentation (At Risk / Volume-driven / Healthy)
* Interactive filtering across views

---

## Presentation

A structured business analysis is provided separately:

👉 [Download PDF](./03_presentation/Growth Quality & Monetization Analysis.pdf)

This complements the dashboard by explaining:

* Growth driver breakdown
* Market-level behavior
* Monetization risk interpretation

---

## Tools

* **SQL (SQLite)** → data modeling, feature engineering, aggregation
* **Tableau** → interactive dashboard and visualization
* **Python** → exploratory analysis and business interpretation (presentation)

---

## Notes

* Only a sample of raw data is included due to file size limitations
* All transformations are fully reproducible using the SQL scripts in this repository

---

