-- ============================================================
-- Analysis queries — Sales Trend, Product Performance,
-- Customer Segmentation, Cancellation Rates, Regional Results
-- ============================================================

-- A. Monthly revenue, order count, AOV (completed orders only)
SELECT
    strftime('%Y-%m', o.invoice_date) AS year_month,
    ROUND(SUM(ol.line_revenue), 2)     AS revenue,
    COUNT(DISTINCT o.invoice_no)       AS orders,
    ROUND(SUM(ol.line_revenue) * 1.0 / COUNT(DISTINCT o.invoice_no), 2) AS aov
FROM orders o
JOIN order_lines ol ON ol.invoice_no = o.invoice_no
WHERE o.status_id = 1
GROUP BY year_month
ORDER BY year_month;

-- B. Top 10 products by total revenue
SELECT p.description, p.stock_code,
       ROUND(SUM(ol.line_revenue), 2) AS total_revenue,
       SUM(ol.quantity) AS total_units,
       COUNT(DISTINCT ol.invoice_no) AS orders
FROM order_lines ol
JOIN orders o ON o.invoice_no = ol.invoice_no
JOIN products p ON p.stock_code = ol.stock_code
WHERE o.status_id = 1
GROUP BY p.stock_code
ORDER BY total_revenue DESC
LIMIT 10;

-- C. Cancellation rate per product (top revenue products)
SELECT p.description, p.stock_code,
       SUM(CASE WHEN o.status_id = 2 THEN 1 ELSE 0 END) AS cancelled_lines,
       COUNT(*) AS total_lines,
       ROUND(100.0 * SUM(CASE WHEN o.status_id = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancel_rate_pct
FROM order_lines ol
JOIN orders o ON o.invoice_no = ol.invoice_no
JOIN products p ON p.stock_code = ol.stock_code
GROUP BY p.stock_code
HAVING total_lines >= 30
ORDER BY cancel_rate_pct DESC
LIMIT 15;

-- D. Revenue by region
SELECT g.region,
       ROUND(SUM(ol.line_revenue), 2) AS revenue,
       COUNT(DISTINCT o.invoice_no) AS orders,
       ROUND(100.0 * SUM(ol.line_revenue) / (SELECT SUM(line_revenue) FROM order_lines ol2
            JOIN orders o2 ON o2.invoice_no = ol2.invoice_no WHERE o2.status_id = 1), 2) AS pct_of_total
FROM order_lines ol
JOIN orders o ON o.invoice_no = ol.invoice_no
JOIN geo_lookup g ON g.country = o.country
WHERE o.status_id = 1
GROUP BY g.region
ORDER BY revenue DESC;

-- E. Customer segmentation: one-time vs repeat buyers (registered customers only)
WITH cust_orders AS (
    SELECT o.customer_id, COUNT(DISTINCT o.invoice_no) AS n_orders,
           SUM(ol.line_revenue) AS total_spend
    FROM orders o
    JOIN order_lines ol ON ol.invoice_no = o.invoice_no
    WHERE o.status_id = 1 AND o.customer_id <> 0
    GROUP BY o.customer_id
)
SELECT
    CASE WHEN n_orders = 1 THEN 'One-time' ELSE 'Repeat' END AS segment,
    COUNT(*) AS customers,
    ROUND(AVG(total_spend), 2) AS avg_customer_revenue,
    ROUND(AVG(total_spend / n_orders), 2) AS avg_order_value,
    ROUND(SUM(total_spend), 2) AS segment_revenue
FROM cust_orders
GROUP BY segment;

-- F. Quarterly revenue heat map input: top 5 products x quarter
WITH top5 AS (
    SELECT stock_code FROM (
        SELECT ol.stock_code, SUM(ol.line_revenue) rev
        FROM order_lines ol JOIN orders o ON o.invoice_no = ol.invoice_no
        WHERE o.status_id = 1
        GROUP BY ol.stock_code ORDER BY rev DESC LIMIT 5
    )
)
SELECT p.description,
       strftime('%Y', o.invoice_date) || '-Q' ||
       ((CAST(strftime('%m', o.invoice_date) AS INTEGER) + 2) / 3) AS quarter,
       ROUND(SUM(ol.line_revenue), 2) AS revenue
FROM order_lines ol
JOIN orders o ON o.invoice_no = ol.invoice_no
JOIN products p ON p.stock_code = ol.stock_code
WHERE o.status_id = 1 AND ol.stock_code IN (SELECT stock_code FROM top5)
GROUP BY p.description, quarter
ORDER BY p.description, quarter;
