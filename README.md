# E-Commerce Sales Analytics with MySQL

This is a reproducible SQL analytics demo by **Murthy Sai Dhanush**. It uses a five-table e-commerce database (**customers, products, orders, order_items, payments**) with fictional sample data, plus queries for revenue trends, top products, repeat customers, and payment methods. Every query is written so that joins never double-count order totals.

> This is a fresh portfolio demo that builds on my resume project "E-Commerce Sales Analytics Using SQL". All names and transactions are fictional, generated with a fixed random seed. The repository contains no real customer data and no credentials.

## Data model

```
customers 1──* orders 1──* order_items *──1 products
                  │
                  └──* payments        (an order can have 2 payments: Wallet + card/UPI)
```

| Table | Rows | Notes |
|---|---|---|
| customers | 40 | fictional names, city, signup date |
| products | 20 | 7 categories, list price in INR |
| orders | 220 | 2025-01-01 to 2025-12-31, status: delivered / shipped / cancelled / returned |
| order_items | 336 | quantity and `unit_price` at the time of sale (some discounted) |
| payments | 251 | UPI, cards, Net Banking, COD, Wallet; 26 orders are split payments |

## How revenue is calculated

- **Line revenue** = `order_items.quantity × order_items.unit_price`. This uses the price actually charged, not the product's current list price.
- **Order revenue** = the sum of the order's line revenues. `orders` has no stored total, so there is one source of truth.
- **Net revenue** counts only orders with status `delivered` or `shipped`. Cancelled and returned orders are excluded, and their payments are marked `refunded`.

## Avoiding double counting

`order_items` and `payments` both have **many rows per order**. If you join both to `orders` in one query, every item row repeats once per payment row. The queries avoid this in two ways:

1. Item-level metrics (products, categories) query `order_items` at its own grain and never join `payments`.
2. When items and payments are needed together, each table is first **aggregated to one row per order in its own CTE**, and only then joined.

`q8_double_counting_pitfall` shows the difference on this data:

| method | reported revenue (INR) |
|---|---|
| naive join of items + payments (WRONG) | 618,785.70 |
| items only (CORRECT) | 515,395.00 |

`q7_reconciliation_items_vs_payments` confirms the correct figure. Net revenue from items is **515,395.00**, completed payments are **515,395.00**, and **0** orders are mismatched.

## Key results (from `outputs/sample_outputs.md`)

- **Net revenue for 2025:** INR 515,395.00 across 194 delivered or shipped orders. Another 26 orders were cancelled or returned, worth INR 66,179.70.
- **Revenue trend:** July was the strongest month at INR 75,736.90 (19 orders, average order value INR 3,986). June and December were the weakest.
- **Top products:** Smart Watch (INR 79,777), Running Shoes (INR 60,458), and Wireless Earbuds (INR 49,175). Electronics brings in 36.4% of revenue.
- **Repeat customers:** 29 of 36 purchasing customers (80.6%) placed 2 or more net orders.
- **Payment methods:** UPI collects 42.3% of the amount paid, followed by Credit Card (25.0%) and Cash on Delivery (16.7%). The Wallet appears only in split payments.

## Files

```
sql/01_schema.sql              DDL for the 5 tables, keys, checks, indexes (MySQL 8.0+)
sql/02_sample_data.sql         INSERTs for the fictional sample data
sql/03_analysis_queries.sql    9 documented queries (q1-q9)
scripts/generate_data.py       regenerates 02_sample_data.sql (seed=2025)
scripts/run_queries_sqlite.py  no-install runner: loads everything into SQLite, writes outputs/
outputs/sample_outputs.md      results of every query on the sample data
```

## Run it with MySQL

You need MySQL Server 8.0 or later (for CTEs, window functions, and CHECK constraints) and the `mysql` client. Use your own local user; you will be prompted for its password, and no credentials are stored in this repo.

```bash
git clone <this-repo-url>
cd ecommerce-sales-analytics-mysql

mysql -u <your_user> -p -e "CREATE DATABASE IF NOT EXISTS ecommerce_demo;"
mysql -u <your_user> -p ecommerce_demo < sql/01_schema.sql
mysql -u <your_user> -p ecommerce_demo < sql/02_sample_data.sql
mysql -u <your_user> -p --table ecommerce_demo < sql/03_analysis_queries.sql
```

In MySQL Workbench, open and run the three files in order against a new `ecommerce_demo` schema.

## Run it without MySQL (quick check)

```bash
python scripts/run_queries_sqlite.py     # Python 3.9+, standard library only
```

This loads the same three SQL files into an in-memory SQLite database and rewrites `outputs/sample_outputs.md`. The SQL avoids engine-specific functions so the files behave the same on both engines; for example, months use `SUBSTR(order_date, 1, 7)` instead of `DATE_FORMAT`.

**How the sample outputs were produced:** `outputs/sample_outputs.md` was generated with this SQLite runner (SQLite 3.53). The SQL is written for MySQL 8. Because the queries use only integer and two-decimal arithmetic with explicit `ROUND`, the MySQL results should match. If you run it on MySQL, compare against q7 (expect 0 mismatched orders) as a sanity check.

## License

MIT
