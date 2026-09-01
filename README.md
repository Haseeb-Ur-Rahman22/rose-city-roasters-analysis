# Rose City Roasters — Sales & Profitability Analysis

An end-to-end analytics project on a specialty coffee roaster and retailer in Portland, Oregon. Four years of transaction-level data are profiled and cleaned in SQL Server, modeled into analytical views, and surfaced in a three-page Power BI dashboard that shows where the business is losing money.

**Tools:** SQL Server (T-SQL) · Power BI · Data modeling · DAX

---

## The question

The business looked healthy on the surface: steady sales and a solid gross margin. But was it actually making money, and if not, where was the profit leaking out?

## What the data shows

**1. The business is running at an operating loss.**
Gross margin held around 34.5%, but operating costs grew faster than profit every year. Operating profit fell from +$187K in 2022 to -$525K in 2025. Revenue grew over the same period, so the problem is cost, not sales.

**2. Two leaks are draining margin.**
About $210K was lost across ~18,200 order lines sold below cost (worst SKUs: Coaster Set, Bulk Brewer Pro, French Press). Separately, $1.77M in revenue was given away as discounts, and gross margin roughly halves with each discount tier (44% at no discount down to 14% at 21–30% off).

**3. Wholesale is the cash-flow risk.**
79% of wholesale invoices are paid late (about 19,000 of 24,000), tying up working capital. Retail shows the highest unpaid invoice *count* (~10,900), but only because of volume: its late *rate* is near 0%. The risk sits with wholesale terms, not retail.

## Recommendations

1. Re-price the loss-making SKUs to recover the ~$210K leaking below cost.
2. Cap the deepest discount tiers to protect the $1.77M currently discounted away.
3. Tighten wholesale payment terms and collections to free up trapped cash.
4. Address the cost base — the root cause behind the four-year slide into operating loss.

---

## How it was built

**1. Profile & clean (T-SQL).**
Profiled 1.05M sales line items. Removed 3,146 duplicate rows, quarantined 526 fat-finger quantity outliers to an audit table, filled missing discounts, flagged comped (free) lines, and standardized inconsistent customer and city text. Integrity checks confirmed every fact row links to a valid dimension and each order has exactly one invoice.

**2. Model (SQL views).**
Built analytical views on the cleaned tables: line-level profit, monthly P&L against operating expenses, product profitability, location performance, and customer payment behavior.

**3. Connect (Power BI).**
Imported the views, built a shared `Dim_Year` dimension, and related it to the sales and P&L tables so a single year slicer filters the whole report cleanly.

**4. Visualize.**
Three pages: an Executive Summary, a Profit Leak Deep Dive, and a Customers & Payments view.

## Repo contents

| File | What it is |
|---|---|
| `RoseCityRoasters_Cleaning.sql` | Full T-SQL profiling and cleaning script (check → fix → verify) |
| `RoseCityRoasters_CaseStudy.pptx` | Presentation deck of the findings |
| `README.md` | This file |

## Data note

The dataset is synthetic, generated to model realistic small-business patterns (cost creep, late wholesale payments, discounting, and data-quality issues) for analysis practice.

---

**Md Haseeb Ur Rahman** · Data Analyst · [github.com/Haseeb-Ur-Rahman22](https://github.com/Haseeb-Ur-Rahman22)
