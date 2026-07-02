# Power BI connection guide

Follow top to bottom. Everything happens on this machine; no credentials are typed anywhere because LocalDB trusts the Windows login.

## 1. Make sure the database is up

Open a terminal in the project root:

```
sqllocaldb start MSSQLLocalDB
```

If this machine was rebuilt or the database is empty, reload it (takes about a minute) and recreate the views:

```
.venv\Scripts\python.exe src\load_to_sql.py
sqlcmd -S "(localdb)\MSSQLLocalDB" -d olist -i sql\03_powerbi_views.sql
```

Quick check that the views exist:

```
sqlcmd -S "(localdb)\MSSQLLocalDB" -d olist -Q "SELECT name FROM sys.views ORDER BY name;"
```

Expected: dim_customer, dim_date, dim_product, dim_seller, fact_order_items.

## 2. Connect from Power BI Desktop

1. Open Power BI Desktop, blank report.
2. Home > Get data > SQL Server.
3. Server: `(localdb)\MSSQLLocalDB`
4. Database: `olist`
5. Data Connectivity mode: **Import**. Click OK.
6. If asked for credentials: left tab **Windows**, "Use my current credentials", Connect.
7. If an encryption warning appears, click OK; LocalDB runs on this machine only.

## 3. Pick the views

In the Navigator window, tick exactly these five, nothing else:

- `fact_order_items`
- `dim_customer`
- `dim_date`
- `dim_product`
- `dim_seller`

Do not tick the base tables (orders, order_items, customers, ...). The views are the model. Click **Load**.

## 4. Relationships

Open the Model view (third icon on the left rail). Power BI autodetects some relationships; verify every one of these exists, create the missing ones by dragging the fact column onto the dim column, and delete anything else it invented:

| From (many side) | To (one side) | Cardinality | Direction |
|---|---|---|---|
| fact_order_items[customer_id] | dim_customer[customer_id] | Many to one | Single |
| fact_order_items[product_id] | dim_product[product_id] | Many to one | Single |
| fact_order_items[seller_id] | dim_seller[seller_id] | Many to one | Single |
| fact_order_items[order_date] | dim_date[date] | Many to one | Single |

## 5. Mark the date table

Click `dim_date` in the Model or Data view, then Table tools > Mark as date table > choose the `date` column > OK. The MoM measure fails without this step.

## 6. Sort month names

Click the `month_name` column in `dim_date`, then Column tools > Sort by column > `month_number`. Otherwise months sort alphabetically (April first).

## 7. Add the measures

Select `fact_order_items` in the Fields pane, then Modeling > New measure, and paste each of the eight measures from `dax_measures.md`, one at a time. Set the format of each measure right after creating it (the format list is in that file next to each measure).

## 8. Validate before building anything

Drop four cards on the empty page: `[Total Revenue]`, `[Total Orders]`, `[Average Delivery Days]`, `[Repeat Customer Rate]`. They must read R$15,418,395, 96470, 12.1, and 3.0%. If they do, the model is correct; delete the cards and build the pages from `dashboard_spec.md`.

## If something fails

- "Cannot connect" or timeout: the instance is asleep. Run `sqllocaldb start MSSQLLocalDB` and press Retry.
- "Login failed": the credentials dialog is on the Database tab; switch to the Windows tab, current credentials.
- Views missing in Navigator: run the sqlcmd line from step 1.
- Cards show wrong numbers: check step 4 (a missing or bidirectional relationship) and step 5. The most common miss is the order_date to date relationship, because the column names differ.
- MoM measure errors: dim_date is not marked as date table (step 5).
