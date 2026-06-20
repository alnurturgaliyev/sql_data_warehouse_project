/*
===============================================================================
DDL Script: Create Silver Layer Tables
===============================================================================
Purpose:
    This script creates tables in the silver schema.

    The silver layer stores cleaned and transformed data loaded from the bronze
    layer. These tables are used as the source for the gold layer.

Actions Performed:
    - Drops existing silver tables if they already exist.
    - Creates CRM and ERP silver tables.
    - Adds dwh_create_date column to track record load timestamp.
===============================================================================
*/

-- =============================================================================
-- 1. CRM Customer Information
-- =============================================================================
DROP TABLE IF EXISTS silver.crm_cust_info;

CREATE TABLE silver.crm_cust_info (
    cst_id             INT,
    cst_key            VARCHAR(50),
    cst_firstname      VARCHAR(50),
    cst_lastname       VARCHAR(50),
    cst_marital_status VARCHAR(50),
    cst_gndr           VARCHAR(50),
    cst_create_date    DATE,
    dwh_create_date    TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 2. CRM Product Information
-- =============================================================================
DROP TABLE IF EXISTS silver.crm_prd_info;

CREATE TABLE silver.crm_prd_info (
    prd_id          INT,
    cat_id          VARCHAR(50),
    prd_key         VARCHAR(50),
    prd_nm          VARCHAR(50),
    prd_cost        NUMERIC(18,2),
    prd_line        VARCHAR(50),
    prd_start_dt    DATE,
    prd_end_dt      DATE,
    dwh_create_date TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 3. CRM Sales Details
-- =============================================================================
DROP TABLE IF EXISTS silver.crm_sales_details;

CREATE TABLE silver.crm_sales_details (
    sls_ord_num     VARCHAR(50),
    sls_prd_key     VARCHAR(50),
    sls_cust_id     INT,
    sls_order_dt    DATE,
    sls_ship_dt     DATE,
    sls_due_dt      DATE,
    sls_sales       NUMERIC(18,2),
    sls_quantity    INT,
    sls_price       NUMERIC(18,2),
    dwh_create_date TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 4. ERP Customer Information
-- =============================================================================
DROP TABLE IF EXISTS silver.erp_cust_az12;

CREATE TABLE silver.erp_cust_az12 (
    cid             VARCHAR(50),
    bdate           DATE,
    gen             VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 5. ERP Location Information
-- =============================================================================
DROP TABLE IF EXISTS silver.erp_loc_a101;

CREATE TABLE silver.erp_loc_a101 (
    cid             VARCHAR(50),
    cntry           VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- 6. ERP Product Category Information
-- =============================================================================
DROP TABLE IF EXISTS silver.erp_px_cat_g1v2;

CREATE TABLE silver.erp_px_cat_g1v2 (
    id              VARCHAR(50),
    cat             VARCHAR(50),
    subcat          VARCHAR(50),
    maintenance     VARCHAR(50),
    dwh_create_date TIMESTAMP DEFAULT NOW()
);
