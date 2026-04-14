DROP TABLE IF EXISTS core_transactions_enriched;
DROP TABLE IF EXISTS qc_summary;

CREATE TABLE core_transactions_enriched AS
WITH
-- 1) raw 표준화
base AS (
    SELECT
        CAST(transaction_id AS INTEGER) AS transaction_id,
        CAST(user_id AS INTEGER) AS user_id,
        TRIM(country) AS country,
        TRIM(transaction_date) AS transaction_date_raw,
        CAST(amount AS REAL) AS amount,
        TRIM(payment_method) AS payment_method
    FROM transactions
),

-- 2) exact duplicate 제거
-- transaction_id가 같아도 amount 등 다른 값이면 유지됨
deduped AS (
    SELECT DISTINCT
        transaction_id,
        user_id,
        country,
        transaction_date_raw,
        amount,
        payment_method
    FROM base
),

-- 3) invalid date 제거
-- DATE() 파싱 불가 or placeholder 1970-01-01 제거
valid_dates AS (
    SELECT
        transaction_id,
        user_id,
        country,
        DATE(transaction_date_raw) AS transaction_date,
        amount,
        payment_method
    FROM deduped
    WHERE DATE(transaction_date_raw) IS NOT NULL
      AND DATE(transaction_date_raw) <> '1970-01-01'
),

-- 4) zero / negative amount 제거
positive_amounts AS (
    SELECT
        transaction_id,
        user_id,
        country,
        transaction_date,
        amount,
        payment_method
    FROM valid_dates
    WHERE amount > 0
),

-- 5) IQR 계산용 정렬
ordered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY amount) AS rn,
        COUNT(*) OVER () AS n
    FROM positive_amounts
),

-- 6) quartile position 계산
quartile_pos AS (
    SELECT DISTINCT
        n,
        CAST(((n - 1) * 0.25) + 1 AS INTEGER) AS q1_pos,
        CAST(((n - 1) * 0.75) + 1 AS INTEGER) AS q3_pos
    FROM ordered
),

-- 7) Q1 / Q3 추출
quartiles AS (
    SELECT
        MAX(CASE WHEN o.rn = qp.q1_pos THEN o.amount END) AS q1,
        MAX(CASE WHEN o.rn = qp.q3_pos THEN o.amount END) AS q3
    FROM ordered o
    CROSS JOIN quartile_pos qp
),

-- 8) outlier flag 부여
flagged AS (
    SELECT
        p.*,
        q.q1,
        q.q3,
        (q.q3 - q.q1) AS iqr,
        (q.q1 - 1.5 * (q.q3 - q.q1)) AS lower_bound,
        (q.q3 + 1.5 * (q.q3 - q.q1)) AS upper_bound,
        CASE
            WHEN p.amount < (q.q1 - 1.5 * (q.q3 - q.q1))
              OR p.amount > (q.q3 + 1.5 * (q.q3 - q.q1))
            THEN 1 ELSE 0
        END AS outlier_flag
    FROM positive_amounts p
    CROSS JOIN quartiles q
),

-- 9) core dataset = outlier 제거 완료본
core AS (
    SELECT
        transaction_id,
        user_id,
        country,
        transaction_date,
        amount,
        payment_method
    FROM flagged
    WHERE outlier_flag = 0
),

-- 10) user-level 파생변수 생성
user_enriched AS (
    SELECT
        c.*,

        MIN(transaction_date) OVER (
            PARTITION BY user_id
        ) AS first_purchase_date,

        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY transaction_date, transaction_id
        ) AS order_sequence,

        LAG(transaction_date) OVER (
            PARTITION BY user_id
            ORDER BY transaction_date, transaction_id
        ) AS prev_purchase_date

    FROM core c
)

-- 11) Tableau용 최종 컬럼
SELECT
    transaction_id,
    user_id,
    country,
    transaction_date,
    amount,
    payment_method,

    CAST(strftime('%Y', transaction_date) AS INTEGER) AS year,
    CAST(strftime('%m', transaction_date) AS INTEGER) AS month,
    strftime('%Y-%m', transaction_date) AS year_month,
    CAST(strftime('%d', transaction_date) AS INTEGER) AS day_of_month,

    CASE strftime('%w', transaction_date)
        WHEN '0' THEN 'Sun'
        WHEN '1' THEN 'Mon'
        WHEN '2' THEN 'Tue'
        WHEN '3' THEN 'Wed'
        WHEN '4' THEN 'Thu'
        WHEN '5' THEN 'Fri'
        WHEN '6' THEN 'Sat'
    END AS weekday_name,

    CASE strftime('%w', transaction_date)
        WHEN '0' THEN 7
        WHEN '1' THEN 1
        WHEN '2' THEN 2
        WHEN '3' THEN 3
        WHEN '4' THEN 4
        WHEN '5' THEN 5
        WHEN '6' THEN 6
    END AS weekday_num_mon_start,

    first_purchase_date,
    strftime('%Y-%m', first_purchase_date) AS cohort_month,

    order_sequence,

    CASE
        WHEN order_sequence = 1 THEN 'New'
        ELSE 'Returning'
    END AS user_type,

    prev_purchase_date,

    CASE
        WHEN prev_purchase_date IS NULL THEN NULL
        ELSE CAST(julianday(transaction_date) - julianday(prev_purchase_date) AS INTEGER)
    END AS days_since_last_purchase,

    CASE
        WHEN amount < 50 THEN 'Low'
        WHEN amount < 150 THEN 'Mid'
        ELSE 'High'
    END AS order_value_bucket,

    CASE
        WHEN amount < 50 THEN 1 ELSE 0
    END AS low_value_flag,

    CASE
        WHEN amount >= 150 THEN 1 ELSE 0
    END AS high_value_flag

FROM user_enriched
;