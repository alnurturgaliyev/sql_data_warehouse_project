/*
===============================================================================
Customer Analytics Report
===============================================================================
Purpose:
    Creates gold.report_customers, a customer-level analytical view built from
    the Gold star schema.

Grain:
    One row per customer.

Highlights:
    - Customer profile attributes from gold.dim_customers.
    - Customer purchasing behavior and lifecycle metrics.
    - Recency, frequency, monetary, and product diversity metrics.
    - Customer segmentation for reporting and prioritization.
    - Sales contribution and ranking metrics across all customers.

Usage:
    Run this script after the Gold layer views have been created.
===============================================================================
*/

DROP VIEW IF EXISTS gold.report_customers;

CREATE VIEW gold.report_customers AS
WITH analysis_context AS (
    SELECT
        MAX(order_date)::DATE AS report_as_of_date,
        COALESCE(SUM(sales_amount), 0)::NUMERIC(18,2) AS warehouse_total_sales
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
),

customer_sales AS (
    SELECT
        customer_key,
        MIN(order_date)::DATE AS first_order_date,
        MAX(order_date)::DATE AS last_order_date,
        COUNT(DISTINCT order_number) AS total_orders,
        COUNT(DISTINCT product_key) AS unique_products_purchased,
        SUM(quantity)::INT AS total_quantity,
        SUM(sales_amount)::NUMERIC(18,2) AS total_sales,
        AVG(sales_amount)::NUMERIC(18,2) AS avg_line_sales_amount,
        MAX(sales_amount)::NUMERIC(18,2) AS highest_line_sales_amount
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY customer_key
),

customer_metrics AS (
    SELECT
        c.customer_key,
        c.customer_id,
        c.customer_number,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        c.country,
        c.marital_status,
        c.gender,
        c.birthdate,
        CASE
            WHEN c.birthdate IS NULL OR ac.report_as_of_date IS NULL THEN NULL
            ELSE DATE_PART('year', AGE(ac.report_as_of_date, c.birthdate))::INT
        END AS age,
        c.create_date,
        ac.report_as_of_date,
        cs.first_order_date,
        cs.last_order_date,
        COALESCE(cs.total_orders, 0) AS total_orders,
        COALESCE(cs.unique_products_purchased, 0) AS unique_products_purchased,
        COALESCE(cs.total_quantity, 0) AS total_quantity,
        COALESCE(cs.total_sales, 0)::NUMERIC(18,2) AS total_sales,
        COALESCE(cs.avg_line_sales_amount, 0)::NUMERIC(18,2) AS avg_line_sales_amount,
        COALESCE(cs.highest_line_sales_amount, 0)::NUMERIC(18,2) AS highest_line_sales_amount,
        ac.warehouse_total_sales,
        CASE
            WHEN cs.first_order_date IS NULL OR cs.last_order_date IS NULL THEN 0
            ELSE (
                DATE_PART('year', AGE(cs.last_order_date, cs.first_order_date))::INT * 12
                + DATE_PART('month', AGE(cs.last_order_date, cs.first_order_date))::INT
                + 1
            )
        END AS customer_lifespan_months,
        CASE
            WHEN cs.last_order_date IS NULL OR ac.report_as_of_date IS NULL THEN NULL
            ELSE (ac.report_as_of_date - cs.last_order_date)::INT
        END AS recency_days,
        CASE
            WHEN cs.last_order_date IS NULL OR ac.report_as_of_date IS NULL THEN NULL
            ELSE (
                DATE_PART('year', AGE(ac.report_as_of_date, cs.last_order_date))::INT * 12
                + DATE_PART('month', AGE(ac.report_as_of_date, cs.last_order_date))::INT
            )
        END AS recency_months
    FROM gold.dim_customers c
    CROSS JOIN analysis_context ac
    LEFT JOIN customer_sales cs
        ON c.customer_key = cs.customer_key
)

SELECT
    customer_key,
    customer_id,
    customer_number,
    customer_name,
    country,
    marital_status,
    gender,
    birthdate,
    age,
    CASE
        WHEN age IS NULL THEN 'Unknown'
        WHEN age < 20 THEN 'Under 20'
        WHEN age BETWEEN 20 AND 29 THEN '20-29'
        WHEN age BETWEEN 30 AND 39 THEN '30-39'
        WHEN age BETWEEN 40 AND 49 THEN '40-49'
        WHEN age BETWEEN 50 AND 59 THEN '50-59'
        ELSE '60+'
    END AS age_group,
    create_date,
    report_as_of_date,
    first_order_date,
    last_order_date,
    recency_days,
    recency_months,
    customer_lifespan_months,
    CASE
        WHEN total_orders = 0 THEN 'No Sales'
        WHEN total_sales >= 5000 AND total_orders >= 5 THEN 'VIP'
        WHEN total_orders >= 5 THEN 'Loyal'
        WHEN total_orders = 1 THEN 'One-Time Buyer'
        WHEN recency_days <= 90 THEN 'Active'
        WHEN recency_days > 365 THEN 'Dormant'
        ELSE 'Regular'
    END AS customer_segment,
    CASE
        WHEN total_orders = 0 THEN 'No Purchase'
        WHEN recency_days <= 90 THEN 'Recent'
        WHEN recency_days <= 365 THEN 'Warm'
        ELSE 'Inactive'
    END AS recency_status,
    total_orders,
    unique_products_purchased,
    total_quantity,
    total_sales,
    ROUND(total_sales / NULLIF(total_orders, 0), 2) AS avg_order_value,
    ROUND(total_quantity::NUMERIC / NULLIF(total_orders, 0), 2) AS avg_units_per_order,
    avg_line_sales_amount,
    highest_line_sales_amount,
    ROUND(total_sales / NULLIF(customer_lifespan_months, 0), 2) AS avg_monthly_spend,
    ROUND((total_sales / NULLIF(warehouse_total_sales, 0)) * 100, 2) AS sales_contribution_pct,
    DENSE_RANK() OVER (ORDER BY total_sales DESC) AS sales_rank,
    DENSE_RANK() OVER (ORDER BY total_orders DESC) AS order_frequency_rank,
    DENSE_RANK() OVER (ORDER BY total_quantity DESC) AS quantity_rank
FROM customer_metrics;
