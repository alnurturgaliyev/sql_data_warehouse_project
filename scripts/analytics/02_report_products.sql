/*
===============================================================================
Product Analytics Report
===============================================================================
Purpose:
    Creates gold.report_products, a product-level analytical view built from
    the Gold star schema.

Grain:
    One row per product.

Highlights:
    - Product attributes from gold.dim_products.
    - Sales, quantity, customer reach, and lifecycle metrics.
    - Estimated cost, profit, and margin metrics using product cost.
    - Product segmentation for performance and activity monitoring.
    - Sales contribution and ranking metrics across all products.

Usage:
    Run this script after the Gold layer views have been created.
===============================================================================
*/

DROP VIEW IF EXISTS gold.report_products;

CREATE VIEW gold.report_products AS
WITH analysis_context AS (
    SELECT
        MAX(order_date)::DATE AS report_as_of_date,
        COALESCE(SUM(sales_amount), 0)::NUMERIC(18,2) AS warehouse_total_sales
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
),

product_sales AS (
    SELECT
        product_key,
        MIN(order_date)::DATE AS first_sale_date,
        MAX(order_date)::DATE AS last_sale_date,
        COUNT(DISTINCT order_number) AS total_orders,
        COUNT(DISTINCT customer_key) AS unique_customers,
        SUM(quantity)::INT AS total_quantity_sold,
        SUM(sales_amount)::NUMERIC(18,2) AS total_sales,
        AVG(price)::NUMERIC(18,2) AS avg_selling_price,
        MAX(price)::NUMERIC(18,2) AS highest_selling_price,
        MIN(price)::NUMERIC(18,2) AS lowest_selling_price
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY product_key
),

product_metrics AS (
    SELECT
        p.product_key,
        p.product_id,
        p.product_number,
        p.product_name,
        p.category_id,
        p.category,
        p.subcategory,
        p.maintenance,
        p.cost,
        p.product_line,
        p.start_date,
        ac.report_as_of_date,
        ps.first_sale_date,
        ps.last_sale_date,
        COALESCE(ps.total_orders, 0) AS total_orders,
        COALESCE(ps.unique_customers, 0) AS unique_customers,
        COALESCE(ps.total_quantity_sold, 0) AS total_quantity_sold,
        COALESCE(ps.total_sales, 0)::NUMERIC(18,2) AS total_sales,
        COALESCE(ps.avg_selling_price, 0)::NUMERIC(18,2) AS avg_selling_price,
        COALESCE(ps.highest_selling_price, 0)::NUMERIC(18,2) AS highest_selling_price,
        COALESCE(ps.lowest_selling_price, 0)::NUMERIC(18,2) AS lowest_selling_price,
        COALESCE(p.cost * ps.total_quantity_sold, 0)::NUMERIC(18,2) AS estimated_total_cost,
        COALESCE(ps.total_sales - (p.cost * ps.total_quantity_sold), 0)::NUMERIC(18,2) AS estimated_profit,
        ac.warehouse_total_sales,
        CASE
            WHEN ps.first_sale_date IS NULL OR ps.last_sale_date IS NULL THEN 0
            ELSE (
                DATE_PART('year', AGE(ps.last_sale_date, ps.first_sale_date))::INT * 12
                + DATE_PART('month', AGE(ps.last_sale_date, ps.first_sale_date))::INT
                + 1
            )
        END AS product_lifespan_months,
        CASE
            WHEN ps.last_sale_date IS NULL OR ac.report_as_of_date IS NULL THEN NULL
            ELSE (ac.report_as_of_date - ps.last_sale_date)::INT
        END AS recency_days,
        CASE
            WHEN ps.last_sale_date IS NULL OR ac.report_as_of_date IS NULL THEN NULL
            ELSE (
                DATE_PART('year', AGE(ac.report_as_of_date, ps.last_sale_date))::INT * 12
                + DATE_PART('month', AGE(ac.report_as_of_date, ps.last_sale_date))::INT
            )
        END AS recency_months
    FROM gold.dim_products p
    CROSS JOIN analysis_context ac
    LEFT JOIN product_sales ps
        ON p.product_key = ps.product_key
),

product_benchmarks AS (
    SELECT
        *,
        AVG(NULLIF(avg_selling_price, 0)) OVER (PARTITION BY category) AS category_avg_selling_price,
        AVG(total_sales) OVER (PARTITION BY category) AS category_avg_sales
    FROM product_metrics
)

SELECT
    product_key,
    product_id,
    product_number,
    product_name,
    category_id,
    category,
    subcategory,
    maintenance,
    cost,
    product_line,
    start_date,
    report_as_of_date,
    first_sale_date,
    last_sale_date,
    recency_days,
    recency_months,
    product_lifespan_months,
    CASE
        WHEN total_orders = 0 THEN 'No Sales'
        WHEN total_sales >= 50000 THEN 'Top Performer'
        WHEN total_sales >= 20000 THEN 'Strong Performer'
        WHEN total_sales >= 10000 THEN 'Steady Seller'
        ELSE 'Low Performer'
    END AS product_performance_segment,
    CASE
        WHEN total_orders = 0 THEN 'No Sales'
        WHEN recency_days <= 90 THEN 'Active'
        WHEN recency_days <= 365 THEN 'Cooling'
        ELSE 'Dormant'
    END AS product_lifecycle_status,
    CASE
        WHEN total_orders = 0 THEN 'No Sales'
        WHEN category_avg_selling_price IS NULL THEN 'No Category Benchmark'
        WHEN avg_selling_price > category_avg_selling_price * 1.20 THEN 'Premium vs Category'
        WHEN avg_selling_price < category_avg_selling_price * 0.80 THEN 'Discount vs Category'
        ELSE 'Category Average'
    END AS price_position,
    total_orders,
    unique_customers,
    total_quantity_sold,
    total_sales,
    avg_selling_price,
    highest_selling_price,
    lowest_selling_price,
    ROUND(total_sales / NULLIF(total_orders, 0), 2) AS avg_order_revenue,
    ROUND(total_quantity_sold::NUMERIC / NULLIF(total_orders, 0), 2) AS avg_units_per_order,
    ROUND(total_sales / NULLIF(product_lifespan_months, 0), 2) AS avg_monthly_revenue,
    estimated_total_cost,
    estimated_profit,
    ROUND((estimated_profit / NULLIF(total_sales, 0)) * 100, 2) AS estimated_margin_pct,
    ROUND((total_sales / NULLIF(warehouse_total_sales, 0)) * 100, 2) AS sales_contribution_pct,
    ROUND((total_sales / NULLIF(category_avg_sales, 0)) * 100, 2) AS category_sales_index_pct,
    DENSE_RANK() OVER (ORDER BY total_sales DESC) AS sales_rank,
    DENSE_RANK() OVER (ORDER BY total_quantity_sold DESC) AS quantity_rank,
    DENSE_RANK() OVER (ORDER BY unique_customers DESC) AS customer_reach_rank,
    DENSE_RANK() OVER (ORDER BY estimated_profit DESC) AS estimated_profit_rank
FROM product_benchmarks;
