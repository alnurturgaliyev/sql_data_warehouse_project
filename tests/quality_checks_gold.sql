/*
===============================================================================
Quality Checks: Gold Layer
===============================================================================
Script Purpose:
    This script checks the Gold layer views for common data quality issues.

    It validates:
    - Uniqueness of surrogate keys in dimension views.
    - Missing dimension links in the sales fact view.
    - Basic relationship consistency for the star schema.

Usage Notes:
    - Run this script after creating the Gold layer views.
    - Each check should return no rows if the data model is valid.
===============================================================================
*/

-- ====================================================================
-- Check: gold.dim_customers
-- ====================================================================
-- Customer surrogate key should be unique
-- Expectation: No rows

SELECT
    customer_key,
    COUNT(*) AS duplicate_count
FROM gold.dim_customers
GROUP BY customer_key
HAVING COUNT(*) > 1;


-- ====================================================================
-- Check: gold.dim_products
-- ====================================================================
-- Product surrogate key should be unique
-- Expectation: No rows

SELECT
    product_key,
    COUNT(*) AS duplicate_count
FROM gold.dim_products
GROUP BY product_key
HAVING COUNT(*) > 1;


-- ====================================================================
-- Check: gold.fact_sales
-- ====================================================================
-- Every sales record should connect to existing customer and product dimensions
-- Expectation: No rows

SELECT
    f.*
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
    ON f.customer_key = c.customer_key
LEFT JOIN gold.dim_products p
    ON f.product_key = p.product_key
WHERE c.customer_key IS NULL
   OR p.product_key IS NULL;
