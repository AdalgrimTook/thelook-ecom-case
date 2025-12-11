-- ==========================================
-- Task A — Monthly Financials
-- One row per month with:
--   month, revenue, completed orders, units, AOV, MoM revenue growth
--
-- Completed sale: status = 'Complete' AND returned_at IS NULL
-- Month: DATE_TRUNC(DATE(created_at), MONTH)
-- ==========================================

-- Parameters
DECLARE start_date DATE DEFAULT DATE('2019-01-01');
DECLARE end_date DATE DEFAULT DATE('2022-12-31');

WITH completed_items AS (
  SELECT
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month,
    oi.order_id,
    oi.user_id,
    oi.sale_price
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  WHERE oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) BETWEEN start_date AND end_date
),

order_lvl AS (
  SELECT
    month,
    order_id,
    user_id,
    SUM(sale_price) AS order_rev,
    COUNT(*) AS units
  FROM completed_items
  GROUP BY 1,2,3
),

monthly AS (
  SELECT
    month,
    SUM(order_rev) AS revenue,
    COUNT(DISTINCT order_id) AS orders,
    SUM(units) AS units,
    SAFE_DIVIDE(SUM(order_rev), COUNT(DISTINCT order_id)) AS aov
  FROM order_lvl
  GROUP BY 1
)

SELECT
  month,
  revenue,
  orders,
  units,
  aov,
  SAFE_DIVIDE(revenue - LAG(revenue) OVER (ORDER BY month), LAG(revenue) OVER (ORDER BY month)) AS mom_revenue_growth
FROM monthly
ORDER BY month;

-- ==========================================
-- Task B — New vs Returning Mix
--
-- Per month:
--   active_customers (≥1 completed order in that month)
--   new_customers (first-ever completed order in that month)
--   returning_customers
--   revenue_new
--   revenue_returning
--   %_revenue_from_returnin
-- ==========================================

-- Parameters
DECLARE start_date DATE DEFAULT DATE('2019-01-01');
DECLARE end_date DATE DEFAULT DATE('2022-12-31');

WITH completed_items AS (
  SELECT
    oi.order_id,
    oi.user_id,
    DATE(oi.created_at) AS order_date,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS order_month,
    oi.sale_price
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  WHERE oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) BETWEEN start_date AND end_date
),
order_lvl AS (
  SELECT order_id, user_id, order_month, SUM(sale_price) AS order_rev
  FROM completed_items
  GROUP BY 1,2,3
),
first_purchase AS (
  SELECT user_id, MIN(order_month) AS first_order_month
  FROM order_lvl
  GROUP BY 1
),

orders_flagged AS (
  SELECT
    o.order_id,
    o.user_id,
    o.order_month,
    o.order_rev,
    f.first_order_month,
    CASE WHEN o.order_month = f.first_order_month THEN 1 ELSE 0 END AS is_new
  FROM order_lvl o
  JOIN first_purchase f USING (user_id)
),
user_month AS (
  SELECT
    order_month AS month,
    user_id,
    SUM(order_rev) AS user_rev,
    MAX(is_new) AS new_flag
  FROM orders_flagged
  GROUP BY 1,2
),

monthly_agg AS (
  SELECT
    month,
    COUNT(DISTINCT user_id) AS active_customers,
    COUNT(DISTINCT CASE WHEN new_flag = 1 THEN user_id END) AS new_customers,
    COUNT(DISTINCT CASE WHEN new_flag = 0 THEN user_id END) AS returning_customers,
    SUM(CASE WHEN new_flag = 1 THEN user_rev ELSE 0 END) AS revenue_new,
    SUM(CASE WHEN new_flag = 0 THEN user_rev ELSE 0 END) AS revenue_returning,
    SUM(user_rev) AS total_revenue
  FROM user_month
  GROUP BY 1
)

SELECT
  month,
  active_customers,
  new_customers,
  returning_customers,
  revenue_new,
  revenue_returning,
  SAFE_DIVIDE(revenue_returning, total_revenue) AS pct_revenue_from_returning
FROM monthly_agg
ORDER BY month;

-- ==========================================
-- Task C — 90-Day Churn
-- For each month: active_customers, churned_customers_90d, churn_rate_90d
-- ==========================================

-- Parameters
DECLARE start_date DATE DEFAULT DATE('2019-01-01');
DECLARE end_date DATE DEFAULT DATE('2022-12-31');
DECLARE churn_window_days INT64 DEFAULT 90;

WITH orders_base AS (
  SELECT
    oi.order_id,
    oi.user_id,
    DATE(oi.created_at) AS order_date,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS order_month
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  WHERE oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) BETWEEN start_date AND DATE_ADD(end_date, INTERVAL churn_window_days DAY)
),

user_month_activity AS (
  SELECT
    user_id,
    order_month AS month,
    MAX(order_date) AS last_order_in_month
  FROM orders_base
  WHERE order_date BETWEEN start_date AND end_date
  GROUP BY 1,2
),

-- check if user has any order in next 90 days after their last order that month
with_future_flag AS (
  SELECT
    uma.user_id,
    uma.month,
    uma.last_order_in_month,
    EXISTS (
      SELECT 1 FROM orders_base co
      WHERE co.user_id = uma.user_id
        AND co.order_date > uma.last_order_in_month
        AND co.order_date <= DATE_ADD(uma.last_order_in_month, INTERVAL churn_window_days DAY)
    ) AS has_future_order
  FROM user_month_activity uma
),

churn_flags AS (
  SELECT
    user_id, month, last_order_in_month, has_future_order,
    CASE WHEN has_future_order = FALSE THEN 1 ELSE 0 END AS churned_flag
  FROM with_future_flag
),

monthly_churn AS (
  SELECT
    month,
    COUNT(DISTINCT user_id) AS active_customers,
    COUNT(DISTINCT CASE WHEN churned_flag = 1 THEN user_id END) AS churned_customers_90d
  FROM churn_flags
  GROUP BY 1
)

SELECT
  month,
  active_customers,
  churned_customers_90d,
  SAFE_DIVIDE(churned_customers_90d, active_customers) AS churn_rate_90d
FROM monthly_churn
ORDER BY month;

-- ==========================================
-- Task D — Product Change Impact
--
-- Hypothetical change: On '2022-01-15', new header:
--   "Free shipping for orders over $100"
-- ==========================================

-- Parameters
DECLARE pre_start DATE DEFAULT DATE('2021-10-15');
DECLARE post_end DATE DEFAULT DATE('2022-04-15');
DECLARE launch_date DATE DEFAULT DATE('2022-01-15');
DECLARE high_value_threshold FLOAT64 DEFAULT 100.0;

WITH completed_items AS (
  SELECT
    oi.order_id,
    DATE(oi.created_at) AS order_date,
    oi.sale_price
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  WHERE oi.status = 'Complete' 
  AND oi.returned_at IS NULL
    AND DATE(oi.created_at) BETWEEN pre_start AND post_end
),

order_lvl AS (
  SELECT order_id, order_date, SUM(sale_price) AS order_val
  FROM completed_items
  GROUP BY 1,2
),

flagged AS (
  SELECT 
    order_id, 
    order_val,
    CASE WHEN order_val >= high_value_threshold THEN TRUE ELSE FALSE END AS high_value_flag,
    CASE WHEN order_date < launch_date THEN 'Pre' ELSE 'Post' END AS period
  FROM order_lvl
)

SELECT 
  period, 
  high_value_flag,
  COUNT(DISTINCT order_id) AS orders,
  SUM(order_val) AS revenue,
  SAFE_DIVIDE(SUM(order_val), COUNT(DISTINCT order_id)) AS aov
FROM flagged
GROUP BY 1,2
ORDER BY period, high_value_flag
