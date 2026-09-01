/* Rose City Roasters - data cleaning (SQL Server)
   Cleans the raw imported tables before analysis. Run top to bottom. */

USE RoseCityRoasters;
SET NOCOUNT ON;


-- row counts after import
SELECT 'dim_products' AS table_name, COUNT(*) AS row_count FROM dim_products
UNION ALL SELECT 'dim_customers', COUNT(*) FROM dim_customers
UNION ALL SELECT 'dim_locations', COUNT(*) FROM dim_locations
UNION ALL SELECT 'fact_sales_line_items', COUNT(*) FROM fact_sales_line_items
UNION ALL SELECT 'fact_invoices_payments', COUNT(*) FROM fact_invoices_payments
UNION ALL SELECT 'fact_operating_expenses', COUNT(*) FROM fact_operating_expenses;


-- integrity: every sales row should match a dimension, and each order
-- should have one invoice. these should all come back 0.
SELECT 'sales customer_id not in dim_customers' AS check_name, COUNT(*) AS bad_rows
FROM fact_sales_line_items s
LEFT JOIN dim_customers c ON s.customer_id = c.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'sales product_id not in dim_products', COUNT(*)
FROM fact_sales_line_items s
LEFT JOIN dim_products p ON s.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'sales location_id not in dim_locations', COUNT(*)
FROM fact_sales_line_items s
LEFT JOIN dim_locations l ON s.location_id = l.location_id
WHERE l.location_id IS NULL
UNION ALL
SELECT 'invoice order_id not in sales', COUNT(*)
FROM fact_invoices_payments i
LEFT JOIN (SELECT DISTINCT order_id FROM fact_sales_line_items) o ON i.order_id = o.order_id
WHERE o.order_id IS NULL;

SELECT COUNT(*) AS orders_with_multiple_invoices
FROM (SELECT order_id FROM fact_invoices_payments GROUP BY order_id HAVING COUNT(*) > 1) x;


-- some line_ids are repeated. check how many, look at a few to confirm
-- they are exact repeats, then keep one copy and delete the rest.
SELECT COUNT(*) AS duplicate_line_ids
FROM (SELECT line_id FROM fact_sales_line_items GROUP BY line_id HAVING COUNT(*) > 1) d;

SELECT TOP 6 * FROM fact_sales_line_items
WHERE line_id IN (SELECT line_id FROM fact_sales_line_items GROUP BY line_id HAVING COUNT(*) > 1)
ORDER BY line_id;

WITH ranked AS (
    SELECT line_id, ROW_NUMBER() OVER (PARTITION BY line_id ORDER BY (SELECT NULL)) AS rn
    FROM fact_sales_line_items
)
DELETE FROM ranked WHERE rn > 1;

SELECT COUNT(*) AS duplicate_line_ids_after
FROM (SELECT line_id FROM fact_sales_line_items GROUP BY line_id HAVING COUNT(*) > 1) d;


-- the null discounts are just sales with no discount (every real
-- discount is above 0). set them to 0 so the column is clean.
SELECT
    SUM(CASE WHEN discount_pct IS NULL THEN 1 ELSE 0 END) AS null_discounts,
    MIN(discount_pct) AS min_present,
    MAX(discount_pct) AS max_present
FROM fact_sales_line_items;

UPDATE fact_sales_line_items SET discount_pct = 0 WHERE discount_pct IS NULL;

SELECT COUNT(*) AS null_discounts_after FROM fact_sales_line_items WHERE discount_pct IS NULL;


-- normal quantities are small, but a few run from 400 up to ~2000,
-- which look like typing errors. move them to a backup table, then drop them.
SELECT MIN(quantity) AS min_qty, AVG(quantity*1.0) AS avg_qty, MAX(quantity) AS max_qty,
       SUM(CASE WHEN quantity >= 400 THEN 1 ELSE 0 END) AS qty_over_400
FROM fact_sales_line_items;

SELECT TOP 10 line_id, order_id, product_id, quantity
FROM fact_sales_line_items ORDER BY quantity DESC;

DROP TABLE IF EXISTS quarantine_qty_outliers;
SELECT * INTO quarantine_qty_outliers FROM fact_sales_line_items WHERE quantity >= 400;
DELETE FROM fact_sales_line_items WHERE quantity >= 400;

SELECT
    (SELECT COUNT(*) FROM quarantine_qty_outliers) AS rows_moved,
    (SELECT COUNT(*) FROM fact_sales_line_items WHERE quantity >= 400) AS left_in_main;


-- free/comped items have a 0 list price. they are real, so flag them
-- instead of deleting, so reports can include or exclude them later.
IF COL_LENGTH('fact_sales_line_items','is_comp') IS NULL
    ALTER TABLE fact_sales_line_items ADD is_comp BIT NULL;
GO
UPDATE fact_sales_line_items SET is_comp = CASE WHEN unit_list_price = 0 THEN 1 ELSE 0 END;
SELECT is_comp, COUNT(*) AS lines FROM fact_sales_line_items GROUP BY is_comp;


-- customer names and cities are stored inconsistently (extra spaces,
-- caps, ' portland' vs 'Portland'). clean both to trimmed proper case.
SELECT city, COUNT(*) AS customers FROM dim_customers GROUP BY city ORDER BY city;

-- proper case helper (SQL Server has no built-in). dbo. is needed to call a function.
DROP FUNCTION IF EXISTS dbo.ProperCase;
GO
CREATE FUNCTION dbo.ProperCase (@s VARCHAR(200))
RETURNS VARCHAR(200)
AS
BEGIN
    IF @s IS NULL RETURN NULL;
    DECLARE @out VARCHAR(200) = LOWER(LTRIM(RTRIM(@s)));
    DECLARE @i INT = 1, @prev CHAR(1) = ' ';
    WHILE @i <= LEN(@out)
    BEGIN
        IF @prev = ' ' OR @prev = '-' OR @prev = ''''
            SET @out = STUFF(@out, @i, 1, UPPER(SUBSTRING(@out, @i, 1)));
        SET @prev = SUBSTRING(@out, @i, 1);
        SET @i += 1;
    END
    RETURN @out;
END
GO

UPDATE dim_customers
SET customer_name = dbo.ProperCase(customer_name),
    city = dbo.ProperCase(city);

SELECT COUNT(DISTINCT city) AS distinct_cities_after FROM dim_customers;


-- these products are priced at or below cost. don't guess the right
-- price, just list them for the business to review.
SELECT product_id, product_name, category, list_price, base_unit_cost
FROM dim_products WHERE base_unit_cost >= list_price ORDER BY product_id;


-- keep on purpose: a null payment_date means the invoice is still unpaid,
-- and lines sold below cost are the actual profit leak we want to measure.
SELECT payment_status, COUNT(*) AS invoices,
       SUM(CASE WHEN payment_date IS NULL THEN 1 ELSE 0 END) AS unpaid
FROM fact_invoices_payments GROUP BY payment_status;

SELECT COUNT(*) AS loss_making_lines
FROM fact_sales_line_items
WHERE is_comp = 0 AND unit_cost_at_sale >= unit_list_price;


-- final check on the cleaned data
SELECT 'sales rows' AS metric, CAST(COUNT(*) AS VARCHAR(20)) AS value FROM fact_sales_line_items
UNION ALL SELECT 'quarantined', CAST(COUNT(*) AS VARCHAR(20)) FROM quarantine_qty_outliers
UNION ALL SELECT 'comp lines', CAST(COUNT(*) AS VARCHAR(20)) FROM fact_sales_line_items WHERE is_comp = 1
UNION ALL SELECT 'null discounts', CAST(COUNT(*) AS VARCHAR(20)) FROM fact_sales_line_items WHERE discount_pct IS NULL
UNION ALL SELECT 'distinct cities', CAST(COUNT(DISTINCT city) AS VARCHAR(20)) FROM dim_customers;



-- base view: one row per sales line with revenue, cost and profit worked out.
-- net of returns. discount_pct is a fraction (e.g. 0.15 = 15% off).
DROP VIEW IF EXISTS vw_sales_enriched;
GO
CREATE VIEW vw_sales_enriched AS
SELECT
    s.line_id, s.order_id, s.order_date,
    s.customer_id, c.customer_name, c.segment, c.channel, c.city AS customer_city,
    s.product_id, p.product_name, p.category, p.subcategory,
    s.location_id, l.location_name, l.location_type, l.city AS store_city,
    s.quantity, s.returned_qty, s.discount_pct,
    s.unit_list_price, s.unit_cost_at_sale, s.is_comp,
    (s.quantity - ISNULL(s.returned_qty, 0)) AS net_quantity,
    CAST((s.quantity - ISNULL(s.returned_qty, 0)) * s.unit_list_price * (1 - s.discount_pct) AS DECIMAL(18,2)) AS net_revenue,
    CAST((s.quantity - ISNULL(s.returned_qty, 0)) * s.unit_cost_at_sale AS DECIMAL(18,2)) AS cost_amount,
    CAST((s.quantity - ISNULL(s.returned_qty, 0)) * (s.unit_list_price * (1 - s.discount_pct) - s.unit_cost_at_sale) AS DECIMAL(18,2)) AS gross_profit,
    CASE WHEN s.is_comp = 0 AND s.unit_list_price * (1 - s.discount_pct) < s.unit_cost_at_sale
         THEN 1 ELSE 0 END AS is_loss_making
FROM fact_sales_line_items s
JOIN dim_products  p ON s.product_id  = p.product_id
JOIN dim_customers c ON s.customer_id = c.customer_id
JOIN dim_locations l ON s.location_id = l.location_id;
GO


-- monthly profit and loss: sales profit against operating expenses
DROP VIEW IF EXISTS vw_monthly_pnl;
GO
CREATE VIEW vw_monthly_pnl AS
WITH sales AS (
    SELECT CONVERT(CHAR(7), order_date, 126) AS month,
           SUM(net_revenue)  AS revenue,
           SUM(cost_amount)  AS cogs,
           SUM(gross_profit) AS gross_profit
    FROM vw_sales_enriched
    GROUP BY CONVERT(CHAR(7), order_date, 126)
),
opex AS (
    SELECT month, SUM(amount) AS operating_expenses
    FROM fact_operating_expenses
    GROUP BY month
)
SELECT s.month, s.revenue, s.cogs, s.gross_profit,
       ISNULL(o.operating_expenses, 0) AS operating_expenses,
       s.gross_profit - ISNULL(o.operating_expenses, 0) AS operating_profit,
       CAST(s.gross_profit / NULLIF(s.revenue, 0) * 100 AS DECIMAL(5,2)) AS gross_margin_pct
FROM sales s
LEFT JOIN opex o ON s.month = o.month;
GO


-- profit by product, plus how many lines sold below cost
DROP VIEW IF EXISTS vw_product_profitability;
GO
CREATE VIEW vw_product_profitability AS
SELECT
    category, subcategory, product_id, product_name,
    SUM(net_quantity)  AS units_sold,
    SUM(net_revenue)   AS revenue,
    SUM(cost_amount)   AS cost,
    SUM(gross_profit)  AS gross_profit,
    CAST(SUM(gross_profit) / NULLIF(SUM(net_revenue), 0) * 100 AS DECIMAL(5,2)) AS margin_pct,
    SUM(is_loss_making) AS loss_making_lines
FROM vw_sales_enriched
GROUP BY category, subcategory, product_id, product_name;
GO


-- profit by store location
DROP VIEW IF EXISTS vw_location_performance;
GO
CREATE VIEW vw_location_performance AS
SELECT
    location_id, location_name, location_type, store_city,
    SUM(net_revenue)  AS revenue,
    SUM(gross_profit) AS gross_profit,
    CAST(SUM(gross_profit) / NULLIF(SUM(net_revenue), 0) * 100 AS DECIMAL(5,2)) AS margin_pct
FROM vw_sales_enriched
GROUP BY location_id, location_name, location_type, store_city;
GO


-- payment behavior by customer: how much they owe and how late they pay
DROP VIEW IF EXISTS vw_customer_payments;
GO
CREATE VIEW vw_customer_payments AS
SELECT
    i.customer_id, c.customer_name, c.segment, c.channel, c.payment_terms,
    COUNT(*)                AS invoices,
    SUM(i.invoice_amount)   AS total_billed,
    SUM(CASE WHEN i.payment_date IS NULL THEN 1 ELSE 0 END)                AS unpaid_invoices,
    SUM(CASE WHEN i.payment_date > i.due_date THEN 1 ELSE 0 END)           AS paid_late,
    CAST(AVG(CASE WHEN i.payment_date > i.due_date
             THEN CAST(DATEDIFF(DAY, i.due_date, i.payment_date) AS DECIMAL(6,2)) END) AS DECIMAL(6,2)) AS avg_days_late
FROM fact_invoices_payments i
JOIN dim_customers c ON i.customer_id = c.customer_id
GROUP BY i.customer_id, c.customer_name, c.segment, c.channel, c.payment_terms;
GO

SELECT
    SUM(net_revenue)  AS total_revenue,
    SUM(gross_profit) AS total_gross_profit,
    CAST(SUM(gross_profit) / NULLIF(SUM(net_revenue), 0) * 100 AS DECIMAL(5,2)) AS overall_margin_pct
FROM vw_sales_enriched;

