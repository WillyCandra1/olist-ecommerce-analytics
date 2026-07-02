# Data dictionary

Cleaned tables in `data/processed/`, produced by `notebooks/01_data_audit_cleaning.ipynb` from the 9 raw Kaggle CSVs. All later phases read these parquet files, never the raw CSVs. The raw translation table is not saved separately: its content lives inside `products` as the English category column.

## orders.parquet

One row per order. 99,441 rows, unchanged from raw.

| Column | Type | Meaning | Cleaning |
|---|---|---|---|
| order_id | text | Order key, unique | none |
| customer_id | text | Order-side customer record, changes every order; joins to customers | none |
| order_status | text | delivered (96,478), shipped, canceled, unavailable, invoiced, processing, created, approved | none |
| order_purchase_timestamp | datetime | When the customer placed the order | parsed from text |
| order_approved_at | datetime | Payment approval; 160 nulls | parsed; nulls kept |
| order_delivered_carrier_date | datetime | Hand-off to carrier; 1,783 nulls | parsed; nulls kept |
| order_delivered_customer_date | datetime | Customer received the order; 2,965 nulls, only 8 of them on delivered orders | parsed; nulls kept |
| order_estimated_delivery_date | datetime | Delivery promise shown at purchase | parsed from text |

Known quirks, kept and documented: 23 delivered orders show customer delivery before carrier hand-off, and 6 canceled orders carry a delivery date. Progression-date nulls follow order status, so they carry information. Delivery analyses must filter to delivered status with a non-null delivery date.

## order_items.parquet

One row per physical unit in an order. `order_item_id` counts 1 to n within the order, so quantity is the row count. 112,650 rows, unchanged.

| Column | Type | Meaning | Cleaning |
|---|---|---|---|
| order_id | text | Joins to orders | none |
| order_item_id | int | Unit sequence within the order; (order_id, order_item_id) is the key | none |
| product_id | text | Joins to products | none |
| seller_id | text | Joins to sellers | none |
| shipping_limit_date | datetime | Seller's contractual ship-by deadline; 4 rows dated 2020, past the dataset window, harmless because no metric uses this column | parsed from text |
| price | float | Item price in BRL; min 0.85, max 6,735 | none |
| freight_value | float | Freight charged for this unit; 383 rows at exactly 0 are free shipping | none |

## payments.parquet

One row per payment transaction. One order can split across several rows (card plus vouchers), so aggregate to order level before joining. 103,883 rows, 3 removed.

| Column | Type | Meaning | Cleaning |
|---|---|---|---|
| order_id | text | Joins to orders; not unique here | none |
| payment_sequential | int | Payment leg number within the order | none |
| payment_type | text | credit_card (76,795), boleto, voucher, debit_card | dropped 3 `not_defined` rows with value 0.00 |
| payment_installments | int | Number of installments, minimum 1 | 2 rows at 0 set to 1 |
| payment_value | float | Amount of this leg in BRL; 6 zero-value voucher legs kept, they change no sums | none |

## reviews.parquet

One row per order after cleaning. 98,673 rows, 551 removed.

| Column | Type | Meaning | Cleaning |
|---|---|---|---|
| review_id | text | Review key in the source; still not unique, a few ids span two orders | none |
| order_id | text | Joins to orders; unique after cleaning, use as the key | kept only the latest review per order |
| review_score | int | 1 to 5 | none |
| review_comment_title | text | Optional; null means the customer wrote nothing | nulls kept |
| review_comment_message | text | Optional free text | nulls kept |
| review_creation_date | datetime | Survey sent | parsed from text |
| review_answer_timestamp | datetime | Customer answered; used to pick the latest review per order | parsed from text |

Both timestamp columns exist only after the review, so the review model (BQ4) must not use them as features.

## customers.parquet

One row per order-side customer record, not per person. 99,441 rows, unchanged.

| Column | Type | Meaning | Cleaning |
|---|---|---|---|
| customer_id | text | Per-order record, joins to orders | none |
| customer_unique_id | text | The actual person; 96,096 distinct, 2,997 of them (3.1%) placed more than one order. Use this for RFM, cohorts, repeat rate | none |
| customer_zip_code_prefix | int | First 5 digits of the zip; stored as int in every table, leading zeros lost on display only | none |
| customer_city | text | Lowercase city name | none |
| customer_state | text | Two-letter state code | none |

## products.parquet

One row per product. 32,951 rows, unchanged; one column added, two renamed.

| Column | Type | Meaning | Cleaning |
|---|---|---|---|
| product_id | text | Product key | none |
| product_category_name | text | Portuguese category; 610 nulls from one broken upstream feed | nulls kept |
| product_category_name_english | text | English category, 73 values; use this everywhere downstream | added via translation merge; 2 categories missing from the translation file translated by hand (`pc_gamer`, `portable_kitchen_food_preparers`) |
| product_name_length | int | Length of the product name; null on the same 610 rows | renamed from misspelled `product_name_lenght` |
| product_description_length | int | Length of the description | renamed from misspelled `product_description_lenght` |
| product_photos_qty | int | Number of listing photos | none |
| product_weight_g | float | Weight in grams; 2 nulls, 4 zeros, kept because no analysis uses weight | none |
| product_length_cm / product_height_cm / product_width_cm | float | Package dimensions; 2 nulls each | none |

## sellers.parquet

One row per seller. 3,095 rows across 23 states, unchanged.

| Column | Type | Meaning | Cleaning |
|---|---|---|---|
| seller_id | text | Seller key | none |
| seller_zip_code_prefix | int | Zip prefix, same convention as customers | none |
| seller_city | text | City name | none |
| seller_state | text | Two-letter state code | none |

## geolocation.parquet

One row per zip prefix, reduced from 1,000,163 raw address points to 19,010. Only needed to put zips on a map.

| Column | Type | Meaning | Cleaning |
|---|---|---|---|
| geolocation_zip_code_prefix | int | Zip prefix, joins to customers and sellers | none |
| geolocation_lat | float | Median latitude of all points in the prefix | dropped 261,831 exact duplicates and 42 points outside Brazil, then median per prefix |
| geolocation_lng | float | Median longitude | same |

278 customer zips and 7 seller zips have no row here, so maps miss those points. City and state columns were dropped: customers and sellers carry their own, with more consistent spelling.
