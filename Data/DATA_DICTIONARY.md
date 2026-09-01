# Data Dictionary
### Small Business Profit and Margin Analysis | Rose City Roasters (Portland, OR)

Currency: USD. Dates: ISO format (YYYY-MM-DD). Month keys: YYYY-MM.
Keys marked PK are primary keys. FK notes give the related table.

---

## 1. dim_products.csv  (404 rows)

Product and SKU master. One row per SKU.

| Column | Type | Description | Notes |
|---|---|---|---|
| product_id | int | Product identifier | PK |
| product_name | string | Descriptive SKU name | Bag weights are in oz and lb |
| category | string | One of: Brewed Beverage, Food, Retail Beans, Wholesale Beans, Equipment, Merch, Subscription | Main analysis grouping |
| subcategory | string | Finer grouping (for example Single Origin, Blend, Wholesale, Bakery, Brewing Gear) | |
| origin | string | Bean origin or blend name, else NA | Only meaningful for bean categories |
| list_price | float | Catalogue selling price per unit, USD | Fixed per SKU. A few zero-price situations appear at line level in sales, not here |
| base_unit_cost | float | Baseline cost per unit at start of window, USD | Actual cost at sale is time-adjusted, see fact table |
| launch_date | date | When the SKU became available | Some SKUs launched mid-window |
| active_flag | int | 1 active, 0 discontinued | About one in five is discontinued |

Planted issue: a small number of SKUs have base_unit_cost at or above list_price
(mispriced, negative margin). These are intended culprits for product margin analysis.

---

## 2. dim_customers.csv  (15,200 rows)

Customer master across retail, online, and wholesale.

| Column | Type | Description | Notes |
|---|---|---|---|
| customer_id | int | Customer identifier | PK |
| customer_name | string | Person or business name | Some values are upper-cased with a trailing space (planted text issue) |
| segment | string | One of: Retail, Online, Wholesale-Cafe, Wholesale-Office, Wholesale-Restaurant | Drives terms and buying pattern |
| payment_terms | string | Immediate, Net-15, Net-30, or Net-45 | Retail and Online are Immediate |
| channel | string | In-Store, Online, or Wholesale | |
| city | string | Customer city (Portland metro and Pacific Northwest) | Some values have a leading space and lower case (planted text issue) |
| signup_date | date | First registered date | |

Note: a few hundred wholesale accounts drive a large share of wholesale orders
(whale accounts). Retail and Online are many small buyers.

---

## 3. dim_locations.csv  (7 rows)

Physical and virtual selling locations.

| Column | Type | Description | Notes |
|---|---|---|---|
| location_id | int | Location identifier | PK |
| location_name | string | Location label | |
| location_type | string | Roastery, Cafe, or Online | |
| city | string | City | All Portland in this dataset |
| area | string | Neighbourhood, else NA | Portland neighborhoods (Pearl District, Hawthorne, and so on) |
| open_date | date | When the location opened | Cafes open at different times across the window |

---

## 4. fact_sales_line_items.csv  (about 1,051,816 rows)

The core transaction fact. One row per order line. This is the 1M-plus table.

| Column | Type | Description | Notes |
|---|---|---|---|
| line_id | bigint | Line identifier | PK, but duplicates were planted, so it is not perfectly unique until cleaned |
| order_id | int | Order the line belongs to | Links to fact_invoices_payments |
| order_date | date | Date of the order | |
| customer_id | int | Buyer | FK to dim_customers |
| product_id | int | SKU sold | FK to dim_products |
| location_id | int | Where the sale happened | FK to dim_locations |
| quantity | int | Units on the line | Contains rare extreme outliers (fat-finger) |
| unit_list_price | float | List price per unit at sale, USD | A small share is 0 (comps and freebies) |
| discount_pct | float | Discount as a fraction (0.10 is ten percent) | About 2 percent are null, meaning zero |
| unit_cost_at_sale | float | Cost per unit at time of sale, USD | Time-adjusted: bean SKUs track the green coffee index, others track mild inflation |
| returned_qty | int | Units returned from this line | 0 for most lines. Returns are not negative rows |
| return_date | date | When the return happened | Null when nothing was returned |

Derived metrics (compute downstream, not shipped):
- revenue = quantity * unit_list_price * (1 - discount_pct)
- cogs = quantity * unit_cost_at_sale
- gross_profit = revenue - cogs
- net_units = quantity - returned_qty

Planted issues in this file: duplicate rows, null discount_pct, zero unit_list_price,
and extreme quantity outliers. See README for the intended handling.

---

## 5. fact_invoices_payments.csv  (494,000 rows)

Invoice and payment fact, one row per order. Supports the cash-timing view.

| Column | Type | Description | Notes |
|---|---|---|---|
| invoice_id | bigint | Invoice identifier | PK |
| order_id | int | Order billed | Links to fact_sales_line_items |
| customer_id | int | Billed customer | FK to dim_customers |
| segment | string | Customer segment at time of sale | Denormalized for convenience |
| invoice_date | date | Invoice raised (same day as order) | |
| due_date | date | Payment due date | invoice_date plus terms |
| invoice_amount | float | Net invoiced value after discount, USD | Does not net out returns. That is a downstream decision |
| payment_terms | string | Immediate, Net-15, Net-30, Net-45 | |
| payment_date | date | When paid | Null if still Open or Overdue |
| days_to_pay | float | Days from invoice to payment | Null if unpaid. Can be slightly negative for early payers on terms |
| payment_status | string | Paid, Open, or Overdue | Open and Overdue are legitimately unpaid at period end |

Notes: Immediate-terms orders (retail and online) are paid the same day. Net-terms
orders (wholesale) pay late on average, and a share remains open or overdue at the
end of the window, skewed toward recent months. Null payment_date on Open or
Overdue invoices is expected, not dirty.

---

## 6. fact_operating_expenses.csv  (672 rows)

Monthly operating expenses by category, USD. This is the cost-creep table.

| Column | Type | Description | Notes |
|---|---|---|---|
| expense_id | int | Row identifier | PK |
| month | string | Month of the expense (YYYY-MM) | Join key to the sales side by month |
| expense_category | string | Expense line (see list below) | |
| amount | float | Expense amount for that month, USD | |

Expense categories: Rent, Salaries and Labor, Packaging, Freight and Delivery,
Marketing, Card Processing Fees, Utilities, Spoilage and Waste, Equipment
Maintenance, Software and SaaS, Insurance, Professional Fees, Cleaning and
Supplies, Misc.

Behaviour to expect: Salaries and Labor is the largest line and grows with the
business. Rent steps up with new cafes and periodic increases. Freight, packaging,
and spoilage rise faster than revenue (the quiet creep). Card Processing Fees track
card revenue (retail and online) at a roughly fixed percentage, so they scale
without anyone deciding to spend more. Software and SaaS drifts up steadily.

---

## Relationships summary

- fact_sales_line_items.customer_id  ->  dim_customers.customer_id
- fact_sales_line_items.product_id   ->  dim_products.product_id
- fact_sales_line_items.location_id  ->  dim_locations.location_id
- fact_invoices_payments.order_id    ->  fact_sales_line_items.order_id (order grain)
- fact_invoices_payments.customer_id ->  dim_customers.customer_id
- fact_operating_expenses.month      ->  join on calendar month (YYYY-MM), no FK
