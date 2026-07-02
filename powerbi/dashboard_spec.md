# Dashboard spec

Three pages, built on the five imported views and the measures from `dax_measures.md`. Every visual lists its exact field wells so the build needs no guessing. Shared conventions: slicers sit in a left rail on every page, blue for neutral series, red to flag problems, and no visual-level filters on order status because the measures already enforce delivered-only.

## Page 1: Executive Overview

The one-screen answer to "how is the business doing." Anchors on BQ1.

Visuals:

1. Four KPI cards across the top:
   - Card, field: `[Total Revenue]`
   - Card, field: `[Total Orders]`
   - Card, field: `[Average Order Value]`
   - Card, field: `[Average Review Score]`
2. Line chart, "Monthly revenue":
   - X-axis: `dim_date[year_month]` (continuous)
   - Y-axis: `[Total Revenue]`
   - Tooltip: add `[MoM Revenue Growth Percent]`
   - Add a text box over the late-2016 area: "sparse launch months". Add one at the right edge: "series ends Aug 2018, later orders still in transit". Both facts come from the EDA; without them the chart reads as a crash.
3. Bar chart, "Revenue by category, top 10":
   - Y-axis: `dim_product[category]`
   - X-axis: `[Total Revenue]`
   - Filter on this visual: Top N = 10 by `[Total Revenue]`
4. Bar chart, "Revenue by state, top 10":
   - Y-axis: `dim_customer[customer_state]`
   - X-axis: `[Total Revenue]`
   - Filter on this visual: Top N = 10 by `[Total Revenue]`

Slicers: `dim_date[year]`, `dim_customer[customer_state]` (dropdown).

Layout:

```
+--------+--------------------------------------------------------------+
| year   |  [Revenue]  [Orders]  [Avg Order Value]  [Avg Review Score]  |
| state  +--------------------------------------------------------------+
|        |                Monthly revenue (line)                        |
|        +------------------------------+-------------------------------+
|        |  Revenue by category (bar)   |  Revenue by state (bar)       |
+--------+------------------------------+-------------------------------+
```

Expected on open, no filters: revenue R$15,418,395, orders 96,470, AOV R$159.83, score 4.16. Peak month Nov 2017 at R$1.15M.

## Page 2: Customer Analytics

Who buys, what they are worth, and whether they come back. Anchors on BQ2.

Visuals:

1. Three cards:
   - Card, field: `[Repeat Customer Rate]`
   - Card, field: `[Average Order Value]`
   - Card, field: `[Total Orders]`
2. Line chart, "Orders per month":
   - X-axis: `dim_date[year_month]`, Y-axis: `[Total Orders]`
3. Map (filled map), "Orders by state":
   - Location: `dim_customer[customer_state]`
   - Color saturation / tooltip: `[Total Orders]`
   - If the filled map misbehaves with two-letter states, fall back to a bar chart with the same fields.
4. Table, "Category economics":
   - Columns: `dim_product[category]`, `[Total Revenue]`, `[Total Orders]`, `[Average Order Value]`, `[Average Review Score]`
   - Sort by `[Total Revenue]` descending.

Slicers: `dim_date[year]`, `dim_product[category]`.

Layout:

```
+--------+----------------------------------------------------------- --+
| year   |  [Repeat Rate]     [Avg Order Value]     [Orders]            |
| categ. +--------------------------------+------------------------------+
|        |  Orders per month (line)       |  Orders by state (map)       |
|        +--------------------------------+------------------------------+
|        |  Category economics (table)                                  |
+--------+---------------------------------------------------------------+
```

Expected on open: repeat rate 3.0%. The story to tell with this page: 96,096 people bought at least once, almost nobody twice, and the EDA showed half of all second orders arrive within 28 days of the first.

## Page 3: Delivery Operations

Where deliveries are slow or late and what that does to satisfaction. Anchors on BQ3.

Visuals:

1. Three cards:
   - Card, field: `[Average Delivery Days]`
   - Card, field: `[Percent Late Deliveries]`
   - Card, field: `[Average Review Score]`
2. Bar chart, "Average delivery days by state":
   - Y-axis: `dim_customer[customer_state]`, X-axis: `[Average Delivery Days]`
   - Sort descending. The North (RR, AP, AM) sits on top with about double the SP time.
3. Line chart, "Late deliveries over time":
   - X-axis: `dim_date[year_month]`, Y-axis: `[Percent Late Deliveries]`
   - Three real spikes to expect: Nov 2017 at 12.4%, Feb 2018 at 14.1%, Mar 2018 at 19.0% (Black Friday load and early-2018 carrier trouble). A text box on the March peak is worth it.
4. Column chart, "Review score by delivery delay":
   - Create a grouping column first: right-click `fact_order_items[delivery_delay_days]` > New group, bin size 7, name it `delay_bin_7d`.
   - X-axis: `delay_bin_7d`, Y-axis: `[Average Review Score]`
   - This reproduces the EDA finding: early orders average 4.29, a week-plus late averages about 1.7.

Slicers: `dim_date[year]`, `dim_customer[customer_state]`.

Layout:

```
+--------+---------------------------------------------------------------+
| year   |  [Avg Delivery Days]  [% Late]  [Avg Review Score]            |
| state  +-------------------------------+-------------------------------+
|        | Delivery days by state (bar)  | Late deliveries (line)        |
|        +-------------------------------+-------------------------------+
|        | Review score by delay bin (column)                            |
+--------+---------------------------------------------------------------+
```

Expected on open: 12.1 days average, 6.8% late, score 4.16.
