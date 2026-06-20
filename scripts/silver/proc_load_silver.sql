/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Purpose:
    This stored procedure performs the ETL process to populate the silver schema
    tables from the bronze schema.

Actions Performed:
    - Truncates Silver layer tables.
    - Cleans and transforms Bronze layer data.
    - Inserts cleaned data into Silver layer tables.
    - Prints load duration for each table and the whole batch.

Usage:
    CALL silver.load_silver();
===============================================================================
*/

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    start_time       TIMESTAMP;
    end_time         TIMESTAMP;
    batch_start_time TIMESTAMP;
    batch_end_time   TIMESTAMP;

    error_message    TEXT;
    error_code       TEXT;
BEGIN
    batch_start_time := clock_timestamp();

    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Silver Layer';
    RAISE NOTICE '================================================';

    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading CRM Tables';
    RAISE NOTICE '------------------------------------------------';

    ---------------------------------------------------------------------------
    -- 1. Load silver.crm_cust_info
    --    - Removes duplicate customers by keeping the latest record.
    --    - Trims first and last names.
    --    - Normalizes marital status values.
    --    - Normalizes gender values.
    ---------------------------------------------------------------------------
    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.crm_cust_info';
    TRUNCATE TABLE silver.crm_cust_info;

    RAISE NOTICE '>> Inserting Data Into: silver.crm_cust_info';

    INSERT INTO silver.crm_cust_info (
        cst_id,
        cst_key,
        cst_firstname,
        cst_lastname,
        cst_marital_status,
        cst_gndr,
        cst_create_date
    )
    SELECT
        cst_id,
        cst_key,
        TRIM(cst_firstname) AS cst_firstname, -- Remove unwanted spaces from first name
        TRIM(cst_lastname)  AS cst_lastname,  -- Remove unwanted spaces from last name

        CASE
            WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
            WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
            ELSE 'n/a'
        END AS cst_marital_status, -- Convert marital status codes to readable values

        CASE
            WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
            WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
            ELSE 'n/a'
        END AS cst_gndr, -- Convert gender codes to readable values

        cst_create_date
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY cst_id
                ORDER BY cst_create_date DESC
            ) AS flag_last
        FROM bronze.crm_cust_info
        WHERE cst_id IS NOT NULL -- Exclude records without customer ID
    ) AS t
    WHERE flag_last = 1; -- Keep only the latest record for each customer

    end_time := clock_timestamp();

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    RAISE NOTICE '>> ------------------';

    ---------------------------------------------------------------------------
    -- 2. Load silver.crm_prd_info
    --    - Extracts category ID from product key.
    --    - Extracts cleaned product key.
    --    - Replaces NULL product costs with 0.
    --    - Normalizes product line values.
    --    - Calculates product end date using the next start date.
    ---------------------------------------------------------------------------
    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.crm_prd_info';
    TRUNCATE TABLE silver.crm_prd_info;

    RAISE NOTICE '>> Inserting Data Into: silver.crm_prd_info';

    INSERT INTO silver.crm_prd_info (
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        prd_end_dt
    )
    SELECT
        prd_id,

        REPLACE(SUBSTRING(prd_key FROM 1 FOR 5), '-', '_') AS cat_id,
        -- Extract category ID and replace '-' with '_'

        SUBSTRING(prd_key FROM 7) AS prd_key,
        -- Extract product key without category prefix

        prd_nm,

        COALESCE(prd_cost, 0) AS prd_cost,
        -- Replace NULL cost values with 0

        CASE UPPER(TRIM(prd_line))
            WHEN 'M' THEN 'Mountain'
            WHEN 'R' THEN 'Road'
            WHEN 'S' THEN 'Other Sales'
            WHEN 'T' THEN 'Touring'
            ELSE 'n/a'
        END AS prd_line,
        -- Convert product line codes to descriptive values

        prd_start_dt::DATE AS prd_start_dt,

        (
            LEAD(prd_start_dt) OVER (
                PARTITION BY SUBSTRING(prd_key FROM 7)
                ORDER BY prd_start_dt
            ) - INTERVAL '1 day'
        )::DATE AS prd_end_dt
        -- End date is one day before the next product start date

    FROM bronze.crm_prd_info;

    end_time := clock_timestamp();

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    RAISE NOTICE '>> ------------------';

    ---------------------------------------------------------------------------
    -- 3. Load silver.crm_sales_details
    --    - Converts integer date values into DATE format.
    --    - Replaces invalid dates with NULL.
    --    - Recalculates sales if sales value is missing, zero, negative, or wrong.
    --    - Recalculates price using the cleaned sales value.
    ---------------------------------------------------------------------------
    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.crm_sales_details';
    TRUNCATE TABLE silver.crm_sales_details;

    RAISE NOTICE '>> Inserting Data Into: silver.crm_sales_details';

    WITH cleaned_dates AS (
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,

            CASE
                WHEN sls_order_dt = 0 OR LENGTH(sls_order_dt::TEXT) != 8 THEN NULL
                ELSE TO_DATE(sls_order_dt::TEXT, 'YYYYMMDD')
            END AS sls_order_dt,
            -- Convert valid order date values from YYYYMMDD to DATE

            CASE
                WHEN sls_ship_dt = 0 OR LENGTH(sls_ship_dt::TEXT) != 8 THEN NULL
                ELSE TO_DATE(sls_ship_dt::TEXT, 'YYYYMMDD')
            END AS sls_ship_dt,
            -- Convert valid shipping date values from YYYYMMDD to DATE

            CASE
                WHEN sls_due_dt = 0 OR LENGTH(sls_due_dt::TEXT) != 8 THEN NULL
                ELSE TO_DATE(sls_due_dt::TEXT, 'YYYYMMDD')
            END AS sls_due_dt,
            -- Convert valid due date values from YYYYMMDD to DATE

            sls_sales,
            sls_quantity,
            sls_price
        FROM bronze.crm_sales_details
    ),

    cleaned_sales AS (
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_quantity,
            sls_price,

            CASE
                WHEN sls_sales IS NULL
                  OR sls_sales <= 0
                  OR (
                        sls_price IS NOT NULL
                        AND sls_sales != sls_quantity * ABS(sls_price)
                     )
                    THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS sls_sales
            -- Recalculate sales if the original value is invalid or inconsistent

        FROM cleaned_dates
    )

    INSERT INTO silver.crm_sales_details (
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        sls_sales,
        sls_quantity,
        sls_price
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        sls_sales,
        sls_quantity,

        CASE
            WHEN sls_price IS NULL OR sls_price <= 0
                THEN sls_sales::NUMERIC / NULLIF(sls_quantity, 0)
            ELSE sls_price
        END AS sls_price
        -- Recalculate price from the cleaned sales value

    FROM cleaned_sales;

    end_time := clock_timestamp();

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    RAISE NOTICE '>> ------------------';

    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading ERP Tables';
    RAISE NOTICE '------------------------------------------------';

    ---------------------------------------------------------------------------
    -- 4. Load silver.erp_cust_az12
    --    - Removes NAS prefix from customer ID.
    --    - Replaces future birthdates with NULL.
    --    - Normalizes gender values.
    ---------------------------------------------------------------------------
    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.erp_cust_az12';
    TRUNCATE TABLE silver.erp_cust_az12;

    RAISE NOTICE '>> Inserting Data Into: silver.erp_cust_az12';

    INSERT INTO silver.erp_cust_az12 (
        cid,
        bdate,
        gen
    )
    SELECT
        CASE
            WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid FROM 4)
            ELSE cid
        END AS cid,
        -- Remove NAS prefix if it exists

        CASE
            WHEN bdate > CURRENT_DATE THEN NULL
            ELSE bdate
        END AS bdate,
        -- Replace future birthdates with NULL

        CASE
            WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
            WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
            ELSE 'n/a'
        END AS gen
        -- Normalize gender values

    FROM bronze.erp_cust_az12;

    end_time := clock_timestamp();

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    RAISE NOTICE '>> ------------------';

    ---------------------------------------------------------------------------
    -- 5. Load silver.erp_loc_a101
    --    - Removes hyphens from customer ID.
    --    - Normalizes country codes.
    --    - Replaces missing country values with n/a.
    ---------------------------------------------------------------------------
    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.erp_loc_a101';
    TRUNCATE TABLE silver.erp_loc_a101;

    RAISE NOTICE '>> Inserting Data Into: silver.erp_loc_a101';

    INSERT INTO silver.erp_loc_a101 (
        cid,
        cntry
    )
    SELECT
        REPLACE(cid, '-', '') AS cid,
        -- Remove hyphens from customer ID

        CASE
            WHEN TRIM(cntry) = 'DE' THEN 'Germany'
            WHEN TRIM(cntry) IN ('USA', 'US') THEN 'United States'
            WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
            ELSE TRIM(cntry)
        END AS cntry
        -- Normalize country values

    FROM bronze.erp_loc_a101;

    end_time := clock_timestamp();

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    RAISE NOTICE '>> ------------------';

    ---------------------------------------------------------------------------
    -- 6. Load silver.erp_px_cat_g1v2
    --    - Loads product category data from Bronze to Silver.
    --    - No major transformation is applied.
    ---------------------------------------------------------------------------
    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.erp_px_cat_g1v2';
    TRUNCATE TABLE silver.erp_px_cat_g1v2;

    RAISE NOTICE '>> Inserting Data Into: silver.erp_px_cat_g1v2';

    INSERT INTO silver.erp_px_cat_g1v2 (
        id,
        cat,
        subcat,
        maintenance
    )
    SELECT
        id,
        cat,
        subcat,
        maintenance
    FROM bronze.erp_px_cat_g1v2;

    end_time := clock_timestamp();

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (end_time - start_time));

    RAISE NOTICE '>> ------------------';

    ---------------------------------------------------------------------------
    -- Batch completion message
    ---------------------------------------------------------------------------
    batch_end_time := clock_timestamp();

    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Loading Silver Layer is Completed';

    RAISE NOTICE '   - Total Load Duration: % seconds',
        EXTRACT(EPOCH FROM (batch_end_time - batch_start_time));

    RAISE NOTICE '==========================================';

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            error_message = MESSAGE_TEXT,
            error_code    = RETURNED_SQLSTATE;

        RAISE NOTICE '==========================================';
        RAISE NOTICE 'ERROR OCCURRED DURING LOADING SILVER LAYER';
        RAISE NOTICE 'Error Message: %', error_message;
        RAISE NOTICE 'SQL State: %', error_code;
        RAISE NOTICE '==========================================';

        RAISE;
END;
$$;
