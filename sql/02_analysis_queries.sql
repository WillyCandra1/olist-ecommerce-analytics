-- Analysis queries against the olist database. Revenue is defined once for the
-- whole project as SUM(price + freight_value) on delivered orders: what the
-- customer paid for goods plus shipping. Sample outputs: sql/02_query_results.md.

-- Q1: How is monthly revenue trending, and what is the month-over-month growth rate? (BQ1)
WITH monthly AS (
    SELECT
        DATEFROMPARTS(YEAR(o.order_purchase_timestamp), MONTH(o.order_purchase_timestamp), 1) AS order_month,
        COUNT(DISTINCT o.order_id) AS orders,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM dbo.orders AS o
    JOIN dbo.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATEFROMPARTS(YEAR(o.order_purchase_timestamp), MONTH(o.order_purchase_timestamp), 1)
)
SELECT
    order_month,
    orders,
    CAST(revenue AS DECIMAL(12, 2)) AS revenue,
    -- DECIMAL(12,1): the near-empty Dec 2016 makes the Jan 2017 growth rate
    -- absurdly large, and clipping it here would hide a real data property
    CAST(100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
         / NULLIF(LAG(revenue) OVER (ORDER BY order_month), 0) AS DECIMAL(12, 1)) AS mom_growth_pct
FROM monthly
ORDER BY order_month;

-- Q2: Which product categories bring the most revenue, and how concentrated is it? (BQ1)
SELECT
    COALESCE(p.product_category_name_english, 'unknown') AS category,
    COUNT(*) AS items_sold,
    CAST(SUM(oi.price + oi.freight_value) AS DECIMAL(12, 2)) AS revenue,
    CAST(100.0 * SUM(oi.price + oi.freight_value)
         / SUM(SUM(oi.price + oi.freight_value)) OVER () AS DECIMAL(5, 2)) AS revenue_share_pct
FROM dbo.order_items AS oi
JOIN dbo.orders AS o ON o.order_id = oi.order_id
JOIN dbo.products AS p ON p.product_id = oi.product_id
WHERE o.order_status = 'delivered'
GROUP BY COALESCE(p.product_category_name_english, 'unknown')
ORDER BY revenue DESC;

-- Q3: How do delivery time, delay against the promise, and late share vary by customer state? (BQ3)
SELECT
    c.customer_state,
    COUNT(*) AS delivered_orders,
    -- full elapsed days, floored, same definition as the notebooks and the BI views
    CAST(AVG(DATEDIFF(SECOND, o.order_purchase_timestamp, o.order_delivered_customer_date) / 86400 * 1.0)
         AS DECIMAL(5, 1)) AS avg_delivery_days,
    CAST(AVG(DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date) * 1.0)
         AS DECIMAL(5, 1)) AS avg_days_vs_estimate,
    -- dates, not timestamps: arriving on the promised day at 18:00 is on time
    CAST(100.0 * SUM(CASE WHEN CAST(o.order_delivered_customer_date AS DATE)
                               > CAST(o.order_estimated_delivery_date AS DATE)
                          THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 2)) AS late_pct
FROM dbo.orders AS o
JOIN dbo.customers AS c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;

-- Q4: Which sellers generate the most revenue, and how well are their orders reviewed? (BQ1)
WITH seller_orders AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        SUM(oi.price + oi.freight_value) AS order_revenue
    FROM dbo.order_items AS oi
    JOIN dbo.orders AS o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id, oi.order_id
)
SELECT TOP 10
    so.seller_id,
    s.seller_state,
    COUNT(*) AS orders,
    CAST(SUM(so.order_revenue) AS DECIMAL(12, 2)) AS revenue,
    CAST(AVG(r.review_score * 1.0) AS DECIMAL(3, 2)) AS avg_review_score
FROM seller_orders AS so
JOIN dbo.sellers AS s ON s.seller_id = so.seller_id
LEFT JOIN dbo.reviews AS r ON r.order_id = so.order_id
GROUP BY so.seller_id, s.seller_state
ORDER BY revenue DESC;

-- Q5: What share of each monthly cohort of first-time buyers ever purchases again? (BQ2)
WITH person_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp
    FROM dbo.orders AS o
    JOIN dbo.customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
person_stats AS (
    SELECT
        customer_unique_id,
        MIN(order_purchase_timestamp) AS first_purchase,
        COUNT(*) AS order_count
    FROM person_orders
    GROUP BY customer_unique_id
)
SELECT
    DATEFROMPARTS(YEAR(first_purchase), MONTH(first_purchase), 1) AS cohort_month,
    COUNT(*) AS cohort_customers,
    SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    CAST(100.0 * SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 2)) AS repeat_rate_pct
FROM person_stats
GROUP BY DATEFROMPARTS(YEAR(first_purchase), MONTH(first_purchase), 1)
ORDER BY cohort_month;

-- Q6: RFM base table, one row per person, for customer segmentation (BQ2)
WITH person_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM dbo.orders AS o
    JOIN dbo.customers AS c ON c.customer_id = o.customer_id
    JOIN dbo.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, o.order_id, o.order_purchase_timestamp
),
anchor AS (
    SELECT MAX(order_purchase_timestamp) AS max_purchase FROM person_orders
),
rfm AS (
    SELECT
        po.customer_unique_id,
        DATEDIFF(DAY, MAX(po.order_purchase_timestamp), a.max_purchase) AS recency_days,
        COUNT(*) AS frequency,
        CAST(SUM(po.order_value) AS DECIMAL(12, 2)) AS monetary
    FROM person_orders AS po
    CROSS JOIN anchor AS a
    GROUP BY po.customer_unique_id, a.max_purchase
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
    -- 96.9% of customers bought exactly once, so quintiles on frequency would
    -- split identical values arbitrarily; fixed thresholds instead
    CASE WHEN frequency >= 3 THEN 5 WHEN frequency = 2 THEN 3 ELSE 1 END AS f_score,
    NTILE(5) OVER (ORDER BY monetary) AS m_score
FROM rfm
ORDER BY monetary DESC;
