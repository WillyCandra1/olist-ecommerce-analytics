-- Star schema views for Power BI. Import these five views, nothing else.
-- Order-level facts (delivery days, review score) repeat on every item row of
-- an order, so any order-grain measure must aggregate over distinct order_id;
-- the DAX in powerbi/dax_measures.md does exactly that.

DROP VIEW IF EXISTS dbo.fact_order_items;
GO

-- grain: one row per physical unit in an order (order_id + order_item_id)
CREATE VIEW dbo.fact_order_items AS
SELECT
    oi.order_id,
    oi.order_item_id,
    o.customer_id,
    oi.product_id,
    oi.seller_id,
    CAST(o.order_purchase_timestamp AS DATE) AS order_date,
    o.order_status,
    CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
         THEN 1 ELSE 0 END AS is_delivered,
    oi.price,
    oi.freight_value,
    oi.price + oi.freight_value AS revenue,
    DATEDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_customer_date) AS delivery_days,
    -- dates, not timestamps: arriving 22:00 on the promised day is on time
    DATEDIFF(DAY, CAST(o.order_estimated_delivery_date AS DATE),
                  CAST(o.order_delivered_customer_date AS DATE)) AS delivery_delay_days,
    CASE WHEN CAST(o.order_delivered_customer_date AS DATE)
              > CAST(o.order_estimated_delivery_date AS DATE)
         THEN 1 ELSE 0 END AS is_late,
    r.review_score
FROM dbo.order_items AS oi
JOIN dbo.orders AS o ON o.order_id = oi.order_id
LEFT JOIN dbo.reviews AS r ON r.order_id = oi.order_id;
GO

DROP VIEW IF EXISTS dbo.dim_customer;
GO

-- grain: one row per order-side customer record; customer_unique_id is the person
CREATE VIEW dbo.dim_customer AS
SELECT
    c.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,
    g.geolocation_lat,
    g.geolocation_lng
FROM dbo.customers AS c
LEFT JOIN dbo.geolocation AS g
    ON g.geolocation_zip_code_prefix = c.customer_zip_code_prefix;
GO

DROP VIEW IF EXISTS dbo.dim_product;
GO

-- grain: one row per product
CREATE VIEW dbo.dim_product AS
SELECT
    product_id,
    COALESCE(product_category_name_english, 'unknown') AS category,
    product_photos_qty,
    product_weight_g
FROM dbo.products;
GO

DROP VIEW IF EXISTS dbo.dim_seller;
GO

-- grain: one row per seller
CREATE VIEW dbo.dim_seller AS
SELECT
    s.seller_id,
    s.seller_city,
    s.seller_state,
    g.geolocation_lat,
    g.geolocation_lng
FROM dbo.sellers AS s
LEFT JOIN dbo.geolocation AS g
    ON g.geolocation_zip_code_prefix = s.seller_zip_code_prefix;
GO

DROP VIEW IF EXISTS dbo.dim_date;
GO

-- grain: one row per calendar day, 2016-09-01 through 2018-12-31.
-- Built from a cross-joined digits table because a recursive CTE inside a view
-- cannot raise MAXRECURSION past 100 and the spine needs 852 days.
CREATE VIEW dbo.dim_date AS
WITH digits AS (
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
day_offsets AS (
    SELECT ones.n + 10 * tens.n + 100 * hundreds.n + 1000 * thousands.n AS day_offset
    FROM digits AS ones
    CROSS JOIN digits AS tens
    CROSS JOIN digits AS hundreds
    CROSS JOIN digits AS thousands
)
SELECT
    d.[date],
    YEAR(d.[date]) AS [year],
    DATEPART(QUARTER, d.[date]) AS [quarter],
    MONTH(d.[date]) AS month_number,
    DATENAME(MONTH, d.[date]) AS month_name,
    DATEFROMPARTS(YEAR(d.[date]), MONTH(d.[date]), 1) AS year_month,
    DATENAME(WEEKDAY, d.[date]) AS day_name,
    CASE WHEN DATENAME(WEEKDAY, d.[date]) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END AS is_weekend
FROM day_offsets
CROSS APPLY (VALUES (CAST(DATEADD(DAY, day_offset, '2016-09-01') AS DATE))) AS d([date])
WHERE d.[date] <= '2018-12-31';
GO
