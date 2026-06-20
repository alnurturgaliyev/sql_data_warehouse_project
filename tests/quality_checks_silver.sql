/*
===============================================================================
Silver Layer Data Quality Checks
===============================================================================
Purpose:
    This script validates the data loaded into the silver layer after the
    Bronze -> Silver transformation process.

    The checks focus on confirming that the silver tables contain cleaned,
    standardized, and reliable data before they are used by the gold layer.

Validation Areas:
    - Duplicate or missing business keys
    - Extra spaces in text columns
    - Standardized categorical values
    - Invalid or illogical date values
    - Sales calculation consistency

===============================================================================
*/


-- =============================================================================
-- 1. Customer Data Checks: silver.crm_cust_info
-- =============================================================================

-- Validate customer ID uniqueness and completeness
-- Expected result: no rows
SELECT
    cst_id,
    COUNT(*) AS record_count
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1
    OR cst_id IS NULL;


-- Detect leading or trailing spaces in customer keys
-- Expected result: no rows
SELECT
    cst_key
FROM silver.crm_cust_info
WHERE cst_key <> TRIM(cst_key);


-- Detect leading or trailing spaces in customer first names
-- Expected result: no rows
SELECT
    cst_firstname
FROM silver.crm_cust_info
WHERE cst_firstname <> TRIM(cst_firstname);


-- Detect leading or trailing spaces in customer last names
-- Expected result: no rows
SELECT
    cst_lastname
FROM silver.crm_cust_info
WHERE cst_lastname <> TRIM(cst_lastname);


-- Review standardized marital status values
-- Expected values: Single, Married, n/a
SELECT DISTINCT
    cst_marital_status
FROM silver.crm_cust_info
ORDER BY cst_marital_status;


-- Review standardized gender values
-- Expected values: Female, Male, n/a
SELECT DISTINCT
    cst_gndr
FROM silver.crm_cust_info
ORDER BY cst_gndr;


-- =============================================================================
-- 2. Product Data Checks: silver.crm_prd_info
-- =============================================================================

-- Validate product ID uniqueness and completeness
-- Expected result: no rows
SELECT
    prd_id,
    COUNT(*) AS record_count
FROM silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1
    OR prd_id IS NULL;


-- Check product names for unwanted leading or trailing spaces
-- Expected result: no rows
SELECT
    prd_nm
FROM silver.crm_prd_info
WHERE prd_nm <> TRIM(prd_nm);


-- Ensure product costs are available and not negative
-- Expected result: no rows
SELECT
    prd_id,
    prd_cost
FROM silver.crm_prd_info
WHERE prd_cost < 0
    OR prd_cost IS NULL;


-- Review standardized product line values
-- Expected values: Mountain, Road, Other Sales, Touring, n/a
SELECT DISTINCT
    prd_line
FROM silver.crm_prd_info
ORDER BY prd_line;


-- Check product date validity
-- Product end date should not be earlier than product start date
-- Expected result: no rows
SELECT
    *
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;


-- =============================================================================
-- 3. Sales Data Checks: silver.crm_sales_details
-- =============================================================================

-- Review invalid order date values from the Bronze source
-- These records should be converted to NULL or corrected during Silver loading
SELECT
    sls_order_dt
FROM bronze.crm_sales_details
WHERE sls_order_dt <= 0
    OR LENGTH(sls_order_dt::TEXT) <> 8
    OR sls_order_dt > 20500101
    OR sls_order_dt < 19000101;


-- Review invalid shipping date values from the Bronze source
-- These records should be converted to NULL or corrected during Silver loading
SELECT
    sls_ship_dt
FROM bronze.crm_sales_details
WHERE sls_ship_dt <= 0
    OR LENGTH(sls_ship_dt::TEXT) <> 8
    OR sls_ship_dt > 20500101
    OR sls_ship_dt < 19000101;


-- Review invalid due date values from the Bronze source
-- These records should be converted to NULL or corrected during Silver loading
SELECT
    sls_due_dt
FROM bronze.crm_sales_details
WHERE sls_due_dt <= 0
    OR LENGTH(sls_due_dt::TEXT) <> 8
    OR sls_due_dt > 20500101
    OR sls_due_dt < 19000101;


-- Validate chronological order of sales dates
-- Order date should not be later than shipping date or due date
-- Expected result: no rows
SELECT
    *
FROM silver.crm_sales_details
WHERE sls_order_dt > sls_ship_dt
    OR sls_order_dt > sls_due_dt;


-- Validate sales amount calculation
-- Sales amount should equal quantity multiplied by price
-- Expected result: no rows
SELECT DISTINCT
    sls_sales,
    sls_quantity,
    sls_price
FROM silver.crm_sales_details
WHERE sls_sales <> sls_quantity * sls_price
    OR sls_sales IS NULL
    OR sls_quantity IS NULL
    OR sls_price IS NULL
    OR sls_sales <= 0
    OR sls_quantity <= 0
    OR sls_price <= 0
ORDER BY
    sls_sales,
    sls_quantity,
    sls_price;


-- =============================================================================
-- 4. ERP Customer Data Checks: silver.erp_cust_az12
-- =============================================================================

-- Identify birthdates outside the accepted business range
-- Expected range: from 1924-01-01 up to the current date
-- Expected result: no rows
SELECT DISTINCT
    bdate
FROM silver.erp_cust_az12
WHERE bdate < DATE '1924-01-01'
    OR bdate > CURRENT_DATE
ORDER BY bdate;


-- Review standardized ERP gender values
-- Expected values: Female, Male, n/a
SELECT DISTINCT
    gen
FROM silver.erp_cust_az12
ORDER BY gen;


-- =============================================================================
-- 5. ERP Location Data Checks: silver.erp_loc_a101
-- =============================================================================

-- Review standardized country values after transformation
-- Expected values should be readable country names or n/a
SELECT DISTINCT
    cntry
FROM silver.erp_loc_a101
ORDER BY cntry;


-- Check country values for unwanted leading or trailing spaces
-- Expected result: no rows
SELECT
    cntry
FROM silver.erp_loc_a101
WHERE cntry <> TRIM(cntry);


-- =============================================================================
-- 6. ERP Product Category Checks: silver.erp_px_cat_g1v2
-- =============================================================================

-- Check category-related text fields for unwanted spaces
-- Expected result: no rows
SELECT
    *
FROM silver.erp_px_cat_g1v2
WHERE cat <> TRIM(cat)
    OR subcat <> TRIM(subcat)
    OR maintenance <> TRIM(maintenance);


-- Review maintenance values for consistency
SELECT DISTINCT
    maintenance
FROM silver.erp_px_cat_g1v2
ORDER BY maintenance;
