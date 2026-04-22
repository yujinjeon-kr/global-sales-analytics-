DROP TABLE IF EXISTS transactions_mart;

CREATE TABLE transactions_mart AS
WITH raw AS (
    SELECT
        CAST(transaction_id AS TEXT) AS transaction_id,
        CAST(user_id AS TEXT) AS user_id,
        country,
        DATE(transaction_date) AS transaction_date,
        CAST(amount AS REAL) AS amount,
        payment_method
    FROM transactions
),

/* 1) 완전 중복 제거 */
dedup AS (
    SELECT
        transaction_id,
        user_id,
        country,
        transaction_date,
        amount,
        payment_method
    FROM (
        SELECT
            r.*,
            ROW_NUMBER() OVER (
                PARTITION BY transaction_id, user_id, country, transaction_date, amount, payment_method
                ORDER BY transaction_id
            ) AS rn
        FROM raw r
    )
    WHERE rn = 1
),

/* 2) 날짜 이상치 제거 */
date_clean AS (
    SELECT *
    FROM dedup
    WHERE transaction_date IS NOT NULL
      AND transaction_date >= '2020-01-01'
),

/* 3) 0 amount 제거 */
amount_clean AS (
    SELECT *
    FROM date_clean
    WHERE amount > 0
),

/* 4) exact IQR 계산용 ordered amounts (pandas linear quantile 방식) */
ordered_amounts AS (
    SELECT
        amount,
        ROW_NUMBER() OVER (ORDER BY amount) AS rn,
        COUNT(*) OVER () AS cnt
    FROM amount_clean
),

quartile_positions AS (
    SELECT
        ((cnt - 1) * 0.25) + 1 AS q1_pos,
        ((cnt - 1) * 0.75) + 1 AS q3_pos
    FROM ordered_amounts
    LIMIT 1
),

quartile_values AS (
    SELECT
        q1_low.amount AS q1_low,
        q1_high.amount AS q1_high,
        q3_low.amount AS q3_low,
        q3_high.amount AS q3_high,
        qp.q1_pos,
        qp.q3_pos,
        CAST(qp.q1_pos AS INTEGER) AS q1_floor,
        CAST(qp.q3_pos AS INTEGER) AS q3_floor
    FROM quartile_positions qp
    LEFT JOIN ordered_amounts q1_low
        ON q1_low.rn = CAST(qp.q1_pos AS INTEGER)
    LEFT JOIN ordered_amounts q1_high
        ON q1_high.rn = CASE
            WHEN qp.q1_pos > CAST(qp.q1_pos AS INTEGER) THEN CAST(qp.q1_pos AS INTEGER) + 1
            ELSE CAST(qp.q1_pos AS INTEGER)
        END
    LEFT JOIN ordered_amounts q3_low
        ON q3_low.rn = CAST(qp.q3_pos AS INTEGER)
    LEFT JOIN ordered_amounts q3_high
        ON q3_high.rn = CASE
            WHEN qp.q3_pos > CAST(qp.q3_pos AS INTEGER) THEN CAST(qp.q3_pos AS INTEGER) + 1
            ELSE CAST(qp.q3_pos AS INTEGER)
        END
),

iqr_stats AS (
    SELECT
        q1_low + ((q1_pos - q1_floor) * (q1_high - q1_low)) AS q1,
        q3_low + ((q3_pos - q3_floor) * (q3_high - q3_low)) AS q3
    FROM quartile_values
),

/* 5) IQR 상단 이상치 제거 */
cleaned_lines AS (
    SELECT a.*
    FROM amount_clean a
    CROSS JOIN iqr_stats i
    WHERE a.amount <= (i.q3 + 1.5 * (i.q3 - i.q1))
),

/* 6) 날짜 파생 */
date_features AS (
    SELECT
        cl.*,
        CAST(STRFTIME('%Y', cl.transaction_date) AS INTEGER) AS year,
        CAST(STRFTIME('%m', cl.transaction_date) AS INTEGER) AS month,
        STRFTIME('%Y-%m', cl.transaction_date) AS year_month,
        DATE(STRFTIME('%Y-%m-01', cl.transaction_date)) AS year_month_date,
        CAST(STRFTIME('%d', cl.transaction_date) AS INTEGER) AS day_of_month,
        CASE CAST(STRFTIME('%m', cl.transaction_date) AS INTEGER)
            WHEN 1 THEN 'Jan'
            WHEN 2 THEN 'Feb'
            WHEN 3 THEN 'Mar'
            WHEN 4 THEN 'Apr'
            WHEN 5 THEN 'May'
            WHEN 6 THEN 'Jun'
            WHEN 7 THEN 'Jul'
            WHEN 8 THEN 'Aug'
            WHEN 9 THEN 'Sep'
            WHEN 10 THEN 'Oct'
            WHEN 11 THEN 'Nov'
            ELSE 'Dec'
        END AS month_name,
        CASE
            WHEN CAST(STRFTIME('%m', cl.transaction_date) AS INTEGER) BETWEEN 1 AND 3 THEN 'Q1'
            WHEN CAST(STRFTIME('%m', cl.transaction_date) AS INTEGER) BETWEEN 4 AND 6 THEN 'Q2'
            WHEN CAST(STRFTIME('%m', cl.transaction_date) AS INTEGER) BETWEEN 7 AND 9 THEN 'Q3'
            ELSE 'Q4'
        END AS quarter,
        CASE STRFTIME('%w', cl.transaction_date)
            WHEN '1' THEN 'Mon'
            WHEN '2' THEN 'Tue'
            WHEN '3' THEN 'Wed'
            WHEN '4' THEN 'Thu'
            WHEN '5' THEN 'Fri'
            WHEN '6' THEN 'Sat'
            ELSE 'Sun'
        END AS weekday_name,
        CASE STRFTIME('%w', cl.transaction_date)
            WHEN '0' THEN 7
            ELSE CAST(STRFTIME('%w', cl.transaction_date) AS INTEGER)
        END AS weekday_num_mon_start
    FROM cleaned_lines cl
),

/* 7) 주문 단위 spine 생성: multi-SKU를 하나의 order로 묶음 */
order_spine AS (
    SELECT
        transaction_id,
        MIN(user_id) AS user_id,
        MIN(country) AS country,
        MIN(payment_method) AS payment_method,
        MIN(transaction_date) AS transaction_date,
        SUM(amount) AS order_amount
    FROM date_features
    GROUP BY transaction_id
),

/* 8) 사용자 첫 주문일 */
first_order AS (
    SELECT
        user_id,
        MIN(transaction_date) AS first_purchase_date
    FROM order_spine
    GROUP BY user_id
),

/* 9) 주문 순번 / 직전 주문일 / 최신 주문일 */
ordered_orders AS (
    SELECT
        os.*,
        fo.first_purchase_date,
        ROW_NUMBER() OVER (
            PARTITION BY os.user_id
            ORDER BY os.transaction_date, os.transaction_id
        ) AS order_sequence,
        LAG(os.transaction_date) OVER (
            PARTITION BY os.user_id
            ORDER BY os.transaction_date, os.transaction_id
        ) AS prev_purchase_date,
        MAX(os.transaction_date) OVER (
            PARTITION BY os.user_id
        ) AS latest_purchase_date,
        ROW_NUMBER() OVER (
            PARTITION BY os.user_id
            ORDER BY os.transaction_date DESC, os.transaction_id DESC
        ) AS latest_order_rank
    FROM order_spine os
    LEFT JOIN first_order fo
        ON os.user_id = fo.user_id
),

/* 10) 주문 이력 파생 */
order_features AS (
    SELECT
        oo.*,
        CASE
            WHEN oo.prev_purchase_date IS NULL THEN NULL
            ELSE CAST(JULIANDAY(oo.transaction_date) - JULIANDAY(oo.prev_purchase_date) AS INTEGER)
        END AS days_since_last_purchase,
        CAST(JULIANDAY(oo.transaction_date) - JULIANDAY(oo.first_purchase_date) AS INTEGER) AS days_since_first_purchase,
        (
            (CAST(STRFTIME('%Y', oo.transaction_date) AS INTEGER) - CAST(STRFTIME('%Y', oo.first_purchase_date) AS INTEGER)) * 12
            + (CAST(STRFTIME('%m', oo.transaction_date) AS INTEGER) - CAST(STRFTIME('%m', oo.first_purchase_date) AS INTEGER))
        ) AS months_since_first_purchase,
        STRFTIME('%Y-%m', oo.first_purchase_date) AS cohort_month,
        CASE WHEN oo.order_sequence = 1 THEN 'New' ELSE 'Returning' END AS user_type,
        CASE WHEN oo.order_sequence = 1 THEN 1 ELSE 0 END AS is_first_order_flag,
        CASE WHEN oo.order_sequence > 1 THEN 1 ELSE 0 END AS is_repeat_order_flag,
        CASE
            WHEN oo.order_amount < 50 THEN 'Low'
            WHEN oo.order_amount < 150 THEN 'Mid'
            ELSE 'High'
        END AS order_value_bucket,
        CASE WHEN oo.order_amount < 50 THEN 1 ELSE 0 END AS low_value_flag,
        CASE WHEN oo.order_amount >= 150 THEN 1 ELSE 0 END AS high_value_flag,
        CASE WHEN oo.latest_order_rank = 1 THEN 1 ELSE 0 END AS latest_order_flag
    FROM ordered_orders oo
),

/* 11) 최신 데이터 기준일 */
latest_date AS (
    SELECT MAX(transaction_date) AS max_date
    FROM order_spine
),

/* 12) 사용자 누적 지표: 주문 수는 COUNT(*) over orders */
user_metrics AS (
    SELECT
        ofe.user_id,
        SUM(ofe.order_amount) AS user_lifetime_revenue,
        COUNT(*) AS user_lifetime_orders,
        MAX(ofe.latest_purchase_date) AS latest_purchase_date,
        CAST(JULIANDAY(ld.max_date) - JULIANDAY(MAX(ofe.latest_purchase_date)) AS INTEGER) AS days_since_latest_purchase
    FROM order_features ofe
    CROSS JOIN latest_date ld
    GROUP BY ofe.user_id
),

/* 13) 유저 상위 20% */
user_ranked AS (
    SELECT
        um.*,
        NTILE(5) OVER (ORDER BY um.user_lifetime_revenue DESC) AS revenue_ntile
    FROM user_metrics um
),

/* 14) 전역 주문 평균 */
global_metrics AS (
    SELECT AVG(order_amount) AS global_avg_order_value
    FROM order_spine
),

/* 15) 국가별 매출 순위 */
country_ranked AS (
    SELECT
        country,
        DENSE_RANK() OVER (ORDER BY SUM(order_amount) DESC) AS country_revenue_rank
    FROM order_spine
    GROUP BY country
),

/* 16) 주문 파생 + 유저 현재 상태 파생 */
order_enriched AS (
    SELECT
        ofe.transaction_id,
        ofe.user_id,
        ofe.country,
        ofe.payment_method,
        ofe.transaction_date,
        ofe.order_amount,
        ofe.first_purchase_date,
        ofe.prev_purchase_date,
        ofe.latest_purchase_date,
        ofe.order_sequence,
        ofe.days_since_last_purchase,
        ofe.days_since_first_purchase,
        ofe.months_since_first_purchase,
        ofe.cohort_month,
        ofe.user_type,
        ofe.is_first_order_flag,
        ofe.is_repeat_order_flag,
        ofe.order_value_bucket,
        ofe.low_value_flag,
        ofe.high_value_flag,
        ofe.latest_order_flag,
        um.user_lifetime_revenue,
        um.user_lifetime_orders,
        um.days_since_latest_purchase,
        CASE
		-- 1순위: 90일 넘었으면 무조건 At-Risk (KPI와 동일 기준)
			WHEN um.days_since_latest_purchase > 90 THEN 'At-Risk' 
			-- 2순위: 90일 이내 활동 중인 유저들을 주문 수에 따라 분류
			WHEN um.user_lifetime_orders = 1 THEN 'New'
			WHEN um.user_lifetime_orders = 2 THEN 'Early Repeat'
			WHEN um.user_lifetime_orders >= 3 THEN 'Loyal'
			ELSE 'Other'
		END AS lifecycle_stage,
        CASE
            WHEN um.days_since_latest_purchase <= 7 THEN '0-7d'
            WHEN um.days_since_latest_purchase <= 30 THEN '8-30d'
            WHEN um.days_since_latest_purchase <= 90 THEN '31-90d'
            ELSE '90d+'
        END AS recency_bucket,
        CASE
            WHEN um.user_lifetime_orders = 1 THEN 'One-time'
            WHEN um.user_lifetime_orders <= 3 THEN 'Low Frequency'
            WHEN um.user_lifetime_orders <= 6 THEN 'Mid Frequency'
            ELSE 'High Frequency'
        END AS frequency_segment,
        CASE WHEN um.days_since_latest_purchase > 90 THEN 'At-Risk' ELSE 'Active' END AS pseudo_churn_flag,
		-- 아래 플래그들은 위 로직과 자동으로 싱크가 맞게 됩니다.
		CASE WHEN um.days_since_latest_purchase > 90 THEN 1 ELSE 0 END AS at_risk_user_flag,
		CASE WHEN um.days_since_latest_purchase <= 90 THEN 1 ELSE 0 END AS active_user_flag,
        CASE
            WHEN um.user_lifetime_revenue < 500 THEN 'Low Value'
            WHEN um.user_lifetime_revenue < 1500 THEN 'Mid Value'
            ELSE 'High Value'
        END AS user_value_segment,
        CASE WHEN ur.revenue_ntile = 1 THEN 1 ELSE 0 END AS top20_flag
    FROM order_features ofe
    LEFT JOIN user_metrics um
        ON ofe.user_id = um.user_id
    LEFT JOIN user_ranked ur
        ON ofe.user_id = ur.user_id
)

SELECT
    CAST(
        ROW_NUMBER() OVER (
            ORDER BY df.transaction_date, df.transaction_id, df.user_id, df.amount, df.country, df.payment_method
        ) AS INTEGER
    ) AS line_id,

    /* 원천 row */
    df.transaction_id,
    df.user_id,
    df.country,
    df.transaction_date,
    df.amount,
    df.payment_method,

    /* 날짜 */
    df.year,
    df.quarter,
    df.month,
    df.month_name,
    df.year_month,
    df.year_month_date,
    df.day_of_month,
    df.weekday_name,
    df.weekday_num_mon_start,

    /* 주문 단위 파생 */
    oe.order_amount,
    oe.first_purchase_date,
    oe.prev_purchase_date,
    oe.latest_purchase_date,
    oe.order_sequence,
    oe.days_since_last_purchase,
    oe.days_since_first_purchase,
    oe.days_since_latest_purchase,
    oe.months_since_first_purchase,

    /* cohort / 유저타입 */
    oe.cohort_month,
    oe.user_type,
    oe.is_first_order_flag,
    oe.is_repeat_order_flag,

    /* 주문 가치 */
    oe.order_value_bucket,
    oe.low_value_flag,
    oe.high_value_flag,

    /* 사용자 누적 */
    oe.user_lifetime_revenue,
    oe.user_lifetime_orders,

    /* 사용자 현재 상태 세그먼트 */
    oe.lifecycle_stage,
    oe.recency_bucket,
    oe.frequency_segment,
    oe.pseudo_churn_flag,
    oe.at_risk_user_flag,
    oe.active_user_flag,
    oe.user_value_segment,
    oe.top20_flag,
    oe.latest_order_flag,

    /* YTD */
    CASE
        WHEN
            CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) < CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
            OR (
                CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) = CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                AND CAST(STRFTIME('%d', df.transaction_date) AS INTEGER) <= CAST(STRFTIME('%d', ld.max_date) AS INTEGER)
            )
        THEN 1 ELSE 0
    END AS ytd_aligned_flag,

    CASE
        WHEN df.year = CAST(STRFTIME('%Y', ld.max_date) AS INTEGER)
             AND (
                CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) < CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                OR (
                    CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) = CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                    AND CAST(STRFTIME('%d', df.transaction_date) AS INTEGER) <= CAST(STRFTIME('%d', ld.max_date) AS INTEGER)
                )
             )
            THEN 'Current YTD'
        WHEN df.year = CAST(STRFTIME('%Y', ld.max_date) AS INTEGER) - 1
             AND (
                CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) < CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                OR (
                    CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) = CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                    AND CAST(STRFTIME('%d', df.transaction_date) AS INTEGER) <= CAST(STRFTIME('%d', ld.max_date) AS INTEGER)
                )
             )
            THEN 'Prior YTD'
        ELSE 'Other'
    END AS comparison_year_group,

    CASE
        WHEN df.year = CAST(STRFTIME('%Y', ld.max_date) AS INTEGER)
             AND (
                CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) < CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                OR (
                    CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) = CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                    AND CAST(STRFTIME('%d', df.transaction_date) AS INTEGER) <= CAST(STRFTIME('%d', ld.max_date) AS INTEGER)
                )
             )
        THEN 1 ELSE 0
    END AS is_current_ytd_flag,

    CASE
        WHEN df.year = CAST(STRFTIME('%Y', ld.max_date) AS INTEGER) - 1
             AND (
                CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) < CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                OR (
                    CAST(STRFTIME('%m', df.transaction_date) AS INTEGER) = CAST(STRFTIME('%m', ld.max_date) AS INTEGER)
                    AND CAST(STRFTIME('%d', df.transaction_date) AS INTEGER) <= CAST(STRFTIME('%d', ld.max_date) AS INTEGER)
                )
             )
        THEN 1 ELSE 0
    END AS is_prior_ytd_flag,

    /* 참고 지표 */
    gm.global_avg_order_value,
    cr.country_revenue_rank

FROM date_features df
LEFT JOIN order_enriched oe
    ON df.transaction_id = oe.transaction_id
CROSS JOIN latest_date ld
CROSS JOIN global_metrics gm
LEFT JOIN country_ranked cr
    ON df.country = cr.country
;