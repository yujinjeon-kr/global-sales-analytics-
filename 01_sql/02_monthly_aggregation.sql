DROP TABLE IF EXISTS summary_country_yoy;

CREATE TABLE summary_country_yoy AS
WITH latest_cutoff AS (
    SELECT
        MAX(transaction_date) AS latest_date,
        strftime('%m-%d', MAX(transaction_date)) AS cutoff_mmdd
    FROM core_transactions_enriched
),

aligned_ytd AS (
    SELECT
        country,
        year,
        SUM(amount) AS revenue,
        COUNT(DISTINCT transaction_id) AS orders,
        COUNT(DISTINCT user_id) AS users
    FROM core_transactions_enriched
    WHERE strftime('%m-%d', transaction_date) <= (SELECT cutoff_mmdd FROM latest_cutoff)
    GROUP BY country, year
),

calc AS (
    SELECT
        country,
        year,
        revenue,
        orders,
        users,
        revenue * 1.0 / NULLIF(orders, 0) AS AOV,

        LAG(revenue) OVER (PARTITION BY country ORDER BY year) AS prev_revenue,
        LAG(orders) OVER (PARTITION BY country ORDER BY year) AS prev_orders,
        LAG(users) OVER (PARTITION BY country ORDER BY year) AS prev_users,
        LAG(revenue * 1.0 / NULLIF(orders, 0)) OVER (PARTITION BY country ORDER BY year) AS prev_AOV,
        LAG(year) OVER (PARTITION BY country ORDER BY year) AS prev_year
    FROM aligned_ytd
),

filtered AS (
    SELECT
        country,
        year,
        revenue,
        orders,
        users,
        AOV,
        prev_revenue,
        prev_orders,
        prev_users,
        prev_AOV,
        prev_year
    FROM calc
    WHERE prev_revenue IS NOT NULL
      AND prev_year >= 2023
)
SELECT
    country,
    year,
    revenue,
    orders,
    users,
    AOV,

    (revenue - prev_revenue) * 1.0 / NULLIF(prev_revenue, 0) AS revenue_growth,
    (orders - prev_orders) * 1.0 / NULLIF(prev_orders, 0) AS orders_growth,
    (AOV - prev_AOV) * 1.0 / NULLIF(prev_AOV, 0) AS AOV_change

FROM filtered;