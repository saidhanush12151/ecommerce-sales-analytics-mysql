-- E-Commerce Sales Analytics: analysis queries (MySQL 8.0+; also run on SQLite)
--
-- REVENUE DEFINITION (used everywhere below)
--   line revenue  = order_items.quantity * order_items.unit_price   (price at time of sale)
--   order revenue = SUM(line revenue) over that order's items
--   net revenue   = only orders with status 'delivered' or 'shipped'
--                   (cancelled and returned orders are excluded; their payments are refunded)
--
-- DOUBLE-COUNTING RULE
--   order_items and payments are both "many rows per order". Joining both to orders
--   in one query multiplies rows (items x payments). So each one is aggregated to one
--   row per order in its own CTE first, and only then joined.
--
-- Month is computed with SUBSTR(order_date, 1, 7) -> 'YYYY-MM', which works in MySQL and SQLite.

-- name: q1_monthly_revenue_trend
-- Net revenue, orders, and average order value per month, with month-over-month growth.
WITH order_totals AS (
    SELECT o.order_id,
           SUBSTR(o.order_date, 1, 7)          AS month,
           SUM(oi.quantity * oi.unit_price)    AS order_revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status IN ('delivered', 'shipped')
    GROUP BY o.order_id, SUBSTR(o.order_date, 1, 7)
),
monthly AS (
    SELECT month,
           COUNT(*)            AS orders,
           SUM(order_revenue)  AS revenue
    FROM order_totals
    GROUP BY month
)
SELECT month,
       orders,
       ROUND(revenue, 2)                    AS revenue,
       ROUND(revenue / orders, 2)           AS avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- name: q2_top_products_by_revenue
-- Top 10 products by net revenue (grain: order_items, so no double counting).
SELECT p.product_id,
       p.product_name,
       p.category,
       SUM(oi.quantity)                           AS units_sold,
       COUNT(DISTINCT oi.order_id)                AS orders,
       ROUND(SUM(oi.quantity * oi.unit_price), 2) AS revenue
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.status IN ('delivered', 'shipped')
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue DESC, p.product_id
LIMIT 10;

-- name: q3_revenue_by_category
SELECT p.category,
       SUM(oi.quantity)                           AS units_sold,
       ROUND(SUM(oi.quantity * oi.unit_price), 2) AS revenue,
       ROUND(100.0 * SUM(oi.quantity * oi.unit_price)
             / (SELECT SUM(oi2.quantity * oi2.unit_price)
                FROM order_items oi2 JOIN orders o2 ON o2.order_id = oi2.order_id
                WHERE o2.status IN ('delivered', 'shipped')), 1) AS revenue_share_pct
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.status IN ('delivered', 'shipped')
GROUP BY p.category
ORDER BY revenue DESC;

-- name: q4_repeat_customer_summary
-- A repeat customer has 2 or more net (delivered/shipped) orders.
WITH customer_orders AS (
    SELECT customer_id, COUNT(*) AS n_orders
    FROM orders
    WHERE status IN ('delivered', 'shipped')
    GROUP BY customer_id
)
SELECT COUNT(*)                                              AS purchasing_customers,
       SUM(CASE WHEN n_orders >= 2 THEN 1 ELSE 0 END)        AS repeat_customers,
       SUM(CASE WHEN n_orders = 1  THEN 1 ELSE 0 END)        AS one_time_customers,
       ROUND(100.0 * SUM(CASE WHEN n_orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1)
                                                             AS repeat_rate_pct
FROM customer_orders;

-- name: q5_top_repeat_customers
-- Top 10 repeat customers by lifetime net revenue.
WITH order_totals AS (
    SELECT o.order_id, o.customer_id, o.order_date,
           SUM(oi.quantity * oi.unit_price) AS order_revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status IN ('delivered', 'shipped')
    GROUP BY o.order_id, o.customer_id, o.order_date
)
SELECT c.customer_id,
       c.full_name,
       c.city,
       COUNT(*)                            AS orders,
       ROUND(SUM(ot.order_revenue), 2)     AS lifetime_revenue,
       ROUND(AVG(ot.order_revenue), 2)     AS avg_order_value,
       MIN(ot.order_date)                  AS first_order,
       MAX(ot.order_date)                  AS last_order
FROM order_totals ot
JOIN customers c ON c.customer_id = ot.customer_id
GROUP BY c.customer_id, c.full_name, c.city
HAVING COUNT(*) >= 2
ORDER BY lifetime_revenue DESC, c.customer_id
LIMIT 10;

-- name: q6_payment_methods
-- Completed payments by method. Split payments mean one order can count under two methods,
-- so orders_using_method can add up to more than the number of orders.
SELECT payment_method,
       COUNT(*)                   AS payments,
       COUNT(DISTINCT order_id)   AS orders_using_method,
       ROUND(SUM(amount), 2)      AS amount_collected,
       ROUND(100.0 * SUM(amount) / (SELECT SUM(amount) FROM payments
                                    WHERE payment_status = 'completed'), 1) AS share_of_amount_pct
FROM payments
WHERE payment_status = 'completed'
GROUP BY payment_method
ORDER BY amount_collected DESC;

-- name: q7_reconciliation_items_vs_payments
-- Each table is aggregated to one row per order *before* the join, so nothing is double-counted.
-- Expect 0 mismatched orders, and net revenue = completed payments.
WITH item_totals AS (
    SELECT order_id, SUM(quantity * unit_price) AS items_total
    FROM order_items GROUP BY order_id
),
payment_totals AS (
    SELECT order_id,
           SUM(CASE WHEN payment_status = 'completed' THEN amount ELSE 0 END) AS paid_total,
           COUNT(*) AS payment_rows
    FROM payments GROUP BY order_id
)
SELECT COUNT(*)                                                    AS net_orders,
       SUM(CASE WHEN pt.payment_rows > 1 THEN 1 ELSE 0 END)        AS split_payment_orders,
       ROUND(SUM(it.items_total), 2)                               AS net_revenue_from_items,
       ROUND(SUM(pt.paid_total), 2)                                AS completed_payments,
       SUM(CASE WHEN ABS(it.items_total - pt.paid_total) > 0.01 THEN 1 ELSE 0 END) AS mismatched_orders
FROM orders o
JOIN item_totals    it ON it.order_id = o.order_id
JOIN payment_totals pt ON pt.order_id = o.order_id
WHERE o.status IN ('delivered', 'shipped');

-- name: q8_double_counting_pitfall
-- WRONG vs RIGHT. Joining order_items AND payments directly repeats each item once per
-- payment row, so orders with split payments are counted twice.
SELECT 'naive join (WRONG)' AS method,
       ROUND(SUM(oi.quantity * oi.unit_price), 2) AS reported_revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN payments    p  ON p.order_id  = o.order_id
WHERE o.status IN ('delivered', 'shipped')
UNION ALL
SELECT 'items only (CORRECT)',
       ROUND(SUM(oi.quantity * oi.unit_price), 2)
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status IN ('delivered', 'shipped');

-- name: q9_order_status_breakdown
-- Context: how much gross order value was lost to cancellations and returns.
WITH order_totals AS (
    SELECT o.order_id, o.status, SUM(oi.quantity * oi.unit_price) AS order_value
    FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.order_id, o.status
)
SELECT status,
       COUNT(*)                    AS orders,
       ROUND(SUM(order_value), 2)  AS order_value
FROM order_totals
GROUP BY status
ORDER BY orders DESC;
