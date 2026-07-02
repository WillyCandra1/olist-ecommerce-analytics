-- Schema for the olist database, SQL Server 2016 LocalDB.
-- Types are sized from measured data, not guessed: every id is exactly 32 hex
-- chars, the longest city name is 40 chars, the largest payment is 13,664.08,
-- installments max out at 24. Load order and FK direction follow the star:
-- customers, sellers, products, geolocation first, then orders, then the
-- three tables that hang off orders.

DROP TABLE IF EXISTS dbo.reviews;
DROP TABLE IF EXISTS dbo.payments;
DROP TABLE IF EXISTS dbo.order_items;
DROP TABLE IF EXISTS dbo.orders;
DROP TABLE IF EXISTS dbo.products;
DROP TABLE IF EXISTS dbo.sellers;
DROP TABLE IF EXISTS dbo.customers;
DROP TABLE IF EXISTS dbo.geolocation;

-- grain: one row per order-side customer record; customer_unique_id is the person
CREATE TABLE dbo.customers (
    customer_id              CHAR(32)     NOT NULL PRIMARY KEY,
    customer_unique_id       CHAR(32)     NOT NULL,
    customer_zip_code_prefix INT          NOT NULL,
    customer_city            NVARCHAR(50) NOT NULL,
    customer_state           CHAR(2)      NOT NULL
);

-- grain: one row per seller
CREATE TABLE dbo.sellers (
    seller_id              CHAR(32)     NOT NULL PRIMARY KEY,
    seller_zip_code_prefix INT          NOT NULL,
    seller_city            NVARCHAR(50) NOT NULL,
    seller_state           CHAR(2)      NOT NULL
);

-- grain: one row per product; category is null for 610 products from a broken feed
CREATE TABLE dbo.products (
    product_id                    CHAR(32)    NOT NULL PRIMARY KEY,
    product_category_name         VARCHAR(50) NULL,
    product_category_name_english VARCHAR(50) NULL,
    product_name_length           SMALLINT    NULL,
    product_description_length    SMALLINT    NULL,
    product_photos_qty            TINYINT     NULL,
    product_weight_g              INT         NULL,
    product_length_cm             SMALLINT    NULL,
    product_height_cm             SMALLINT    NULL,
    product_width_cm              SMALLINT    NULL
);

-- grain: one row per zip prefix; no FK from customers or sellers because 278
-- customer zips have no coordinates in the source data
CREATE TABLE dbo.geolocation (
    geolocation_zip_code_prefix INT   NOT NULL PRIMARY KEY,
    geolocation_lat             FLOAT NOT NULL,
    geolocation_lng             FLOAT NOT NULL
);

-- grain: one row per order; progression dates are null until the order reaches
-- that step, so delivery analyses filter on status plus a non-null delivery date
CREATE TABLE dbo.orders (
    order_id                      CHAR(32)    NOT NULL PRIMARY KEY,
    customer_id                   CHAR(32)    NOT NULL REFERENCES dbo.customers (customer_id),
    order_status                  VARCHAR(15) NOT NULL,
    order_purchase_timestamp      DATETIME2(0) NOT NULL,
    order_approved_at             DATETIME2(0) NULL,
    order_delivered_carrier_date  DATETIME2(0) NULL,
    order_delivered_customer_date DATETIME2(0) NULL,
    order_estimated_delivery_date DATETIME2(0) NOT NULL
);

-- grain: one row per physical unit in an order; row count is quantity
CREATE TABLE dbo.order_items (
    order_id            CHAR(32)      NOT NULL REFERENCES dbo.orders (order_id),
    order_item_id       TINYINT       NOT NULL,
    product_id          CHAR(32)      NOT NULL REFERENCES dbo.products (product_id),
    seller_id           CHAR(32)      NOT NULL REFERENCES dbo.sellers (seller_id),
    shipping_limit_date DATETIME2(0)  NOT NULL,
    price               DECIMAL(10, 2) NOT NULL,
    freight_value       DECIMAL(10, 2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

-- grain: one row per payment leg; one order can split across several legs
CREATE TABLE dbo.payments (
    order_id             CHAR(32)      NOT NULL REFERENCES dbo.orders (order_id),
    payment_sequential   TINYINT       NOT NULL,
    payment_type         VARCHAR(15)   NOT NULL,
    payment_installments TINYINT       NOT NULL,
    payment_value        DECIMAL(10, 2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- grain: one row per reviewed order; keyed on order_id because review_id is not
-- unique in the source (a few ids span two orders)
CREATE TABLE dbo.reviews (
    order_id                CHAR(32)      NOT NULL PRIMARY KEY REFERENCES dbo.orders (order_id),
    review_id               CHAR(32)      NOT NULL,
    review_score            TINYINT       NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title    NVARCHAR(50)  NULL,
    review_comment_message  NVARCHAR(300) NULL,
    review_creation_date    DATETIME2(0)  NOT NULL,
    review_answer_timestamp DATETIME2(0)  NOT NULL
);
