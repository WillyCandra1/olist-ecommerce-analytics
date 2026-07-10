# DAX measures

Create each measure on the `fact_order_items` table (Modeling > New measure, paste the code). Two rules explain most of what follows.

First, delivered-only filtering lives inside the measures, not in page filters. `is_delivered = 1` means the order has status delivered and a real delivery date, which excludes 8 delivered orders with no date, the same rule every notebook and query in this project uses. Baking it into the measures means no chart can accidentally count canceled orders because someone forgot a filter.

Second, the fact table has one row per item, but delivery days and review score belong to the whole order and repeat on every item row. A plain AVERAGE would overweight multi-item orders. The pattern `AVERAGEX(VALUES(order_id), CALCULATE(MAX(column)))` fixes that: build the list of distinct orders in the current filter context, fetch each order's single value, then average with one vote per order.

## Total Revenue

```dax
Total Revenue =
CALCULATE(
    SUM(fact_order_items[revenue]),
    fact_order_items[is_delivered] = 1
)
```

Format: currency, R$. Revenue is price plus freight, the project-wide definition.

## Total Orders

```dax
Total Orders =
CALCULATE(
    DISTINCTCOUNT(fact_order_items[order_id]),
    fact_order_items[is_delivered] = 1
)
```

Format: whole number. DISTINCTCOUNT because an order spans several item rows.

## Average Order Value

```dax
Average Order Value =
DIVIDE([Total Revenue], [Total Orders])
```

Format: currency, R$, 2 decimals. DIVIDE returns blank instead of an error when a filter context has no orders.

## Average Delivery Days

```dax
Average Delivery Days =
CALCULATE(
    AVERAGEX(
        VALUES(fact_order_items[order_id]),
        CALCULATE(MAX(fact_order_items[delivery_days]))
    ),
    fact_order_items[is_delivered] = 1
)
```

Format: decimal, 1 decimal. One vote per order, as explained above.

## Percent Late Deliveries

```dax
Percent Late Deliveries =
VAR LateOrders =
    CALCULATE(
        DISTINCTCOUNT(fact_order_items[order_id]),
        fact_order_items[is_delivered] = 1,
        fact_order_items[is_late] = 1
    )
RETURN
    DIVIDE(LateOrders, [Total Orders])
```

Format: percentage, 1 decimal. Late means the delivery date beat the promised date by at least one calendar day; arriving late in the evening of the promised day still counts as on time.

## Average Review Score

```dax
Average Review Score =
CALCULATE(
    AVERAGEX(
        VALUES(fact_order_items[order_id]),
        CALCULATE(MAX(fact_order_items[review_score]))
    ),
    fact_order_items[is_delivered] = 1
)
```

Format: decimal, 2 decimals. Orders without a review return blank and AVERAGEX skips blanks, so the average covers reviewed orders only, same as the notebooks.

## MoM Revenue Growth Percent

```dax
MoM Revenue Growth Percent =
VAR PrevMonthRevenue =
    CALCULATE([Total Revenue], DATEADD(dim_date[date], -1, MONTH))
RETURN
    DIVIDE([Total Revenue] - PrevMonthRevenue, PrevMonthRevenue)
```

Format: percentage, 1 decimal. The variable cannot be called PreviousMonth: DAX rejects a variable named after a built-in function, and PREVIOUSMONTH is one. DATEADD only works after dim_date is marked as the date table (step 6 in the connection guide). Expect absurd values around the near-empty months of late 2016; that is the data, not a bug.

## Repeat Customer Rate

```dax
Repeat Customer Rate =
VAR OrdersPerPerson =
    ADDCOLUMNS(
        CALCULATETABLE(
            VALUES(dim_customer[customer_unique_id]),
            fact_order_items[is_delivered] = 1
        ),
        "@orders",
        CALCULATE(
            DISTINCTCOUNT(fact_order_items[order_id]),
            fact_order_items[is_delivered] = 1
        )
    )
RETURN
    DIVIDE(
        COUNTROWS(FILTER(OrdersPerPerson, [@orders] > 1)),
        COUNTROWS(OrdersPerPerson)
    )
```

Format: percentage, 1 decimal. Counts people through `customer_unique_id`, never `customer_id`, which changes on every order and would make the rate exactly zero.

## Validation targets

With no filters applied, the measures must reproduce the numbers the notebooks computed. If a card disagrees, check the relationships and the is_delivered logic before anything else.

| Measure | Expected value |
|---|---|
| Total Revenue | R$15,418,395 |
| Total Orders | 96,470 |
| Average Order Value | R$159.83 |
| Average Delivery Days | 12.1 |
| Percent Late Deliveries | 6.8% |
| Average Review Score | 4.16 |
| MoM Revenue Growth Percent (Feb 2017 selected) | 112.8% |
| Repeat Customer Rate | 3.0% |
