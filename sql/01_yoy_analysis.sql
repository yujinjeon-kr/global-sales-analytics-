DROP TABLE IF EXISTS summary_country_month;

CREATE TABLE summary_country_month AS
SELECT
    country,
    year,
    year_month,

    COUNT(DISTINCT transaction_id) AS orders,
    COUNT(DISTINCT user_id) AS users,
    SUM(amount) AS revenue,

    -- 핵심 KPI
    SUM(amount) * 1.0 / COUNT(DISTINCT transaction_id) AS AOV,
    SUM(amount) * 1.0 / COUNT(DISTINCT user_id) AS revenue_per_user,

    -- Returning 구조
    SUM(CASE WHEN user_type = 'Returning' THEN 1 ELSE 0 END) * 1.0
        / COUNT(*) AS returning_order_share,

    -- Low value 구조
    SUM(low_value_flag) * 1.0 / COUNT(*) AS low_value_order_share

FROM core_transactions_enriched
GROUP BY country, year, year_month;