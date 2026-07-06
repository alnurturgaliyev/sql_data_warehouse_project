# Data Catalog for Gold Layer

## Overview

The Gold layer contains the business-ready objects exposed by the warehouse for reporting, dashboards, and ad-hoc SQL analysis. In this PostgreSQL project, the Gold layer is implemented as views over the cleaned Silver layer and follows a star schema with customer and product dimensions around sales facts.

## gold.dim_customers

**Purpose:** Provides one enriched customer record per customer, combining CRM customer attributes with ERP demographic and country information.

| Column Name | Data Type | Description |
|---|---:|---|
| customer_key | BIGINT | Surrogate key generated with `ROW_NUMBER()` for analytical joins. |
| customer_id | INT | Original CRM customer identifier. |
| customer_number | VARCHAR(50) | Business customer number from CRM, used to connect customer data across systems. |
| first_name | VARCHAR(50) | Customer first name after Silver-layer trimming and cleansing. |
| last_name | VARCHAR(50) | Customer last name after Silver-layer trimming and cleansing. |
| country | VARCHAR(50) | Customer country from ERP location data, standardized in the Silver layer. |
| marital_status | VARCHAR(50) | Customer marital status, standardized from CRM codes such as `M` and `S`. |
| gender | VARCHAR(50) | Customer gender. CRM is treated as the primary source; ERP gender is used when CRM gender is unavailable or `n/a`. |
| birthdate | DATE | Customer date of birth from ERP customer data, with future dates removed in the Silver layer. |
| create_date | DATE | Date when the customer record was created in the source CRM system. |

## gold.dim_products

**Purpose:** Provides the current product dimension enriched with category and maintenance attributes.

| Column Name | Data Type | Description |
|---|---:|---|
| product_key | BIGINT | Surrogate key generated with `ROW_NUMBER()` for analytical joins. |
| product_id | INT | Original CRM product identifier. |
| product_number | VARCHAR(50) | Product business key after removing the category prefix from the source product key. |
| product_name | VARCHAR(50) | Product name from CRM. |
| category_id | VARCHAR(50) | Product category key extracted from the source product key and standardized to match ERP category data. |
| category | VARCHAR(50) | High-level product category from ERP category data. |
| subcategory | VARCHAR(50) | Product subcategory from ERP category data. |
| maintenance | VARCHAR(50) | Indicates whether the product category requires maintenance. |
| cost | NUMERIC(18,2) | Product cost, with missing Silver-layer values defaulted to `0`. |
| product_line | VARCHAR(50) | Product line description standardized from CRM codes such as `M`, `R`, `S`, and `T`. |
| start_date | DATE | Product effective start date. The Gold view keeps only current products where `prd_end_dt IS NULL`. |

## gold.fact_sales

**Purpose:** Stores sales transactions at the order-line level and connects each sale to customer and product dimensions.

| Column Name | Data Type | Description |
|---|---:|---|
| order_number | VARCHAR(50) | Sales order number from CRM sales details. |
| product_key | BIGINT | Foreign key-style reference to `gold.dim_products.product_key`. |
| customer_key | BIGINT | Foreign key-style reference to `gold.dim_customers.customer_key`. |
| order_date | DATE | Date when the order was placed, converted from source `YYYYMMDD` integer format in the Silver layer. |
| shipping_date | DATE | Date when the order was shipped, converted from source `YYYYMMDD` integer format in the Silver layer. |
| due_date | DATE | Date when the order was due, converted from source `YYYYMMDD` integer format in the Silver layer. |
| sales_amount | NUMERIC(18,2) | Line-item sales amount. Invalid or inconsistent source values are recalculated in the Silver layer. |
| quantity | INT | Number of product units sold in the order line. |
| price | NUMERIC(18,2) | Unit price. Missing or invalid prices are recalculated from sales amount and quantity in the Silver layer. |

## Source-to-Gold Mapping

| Gold Object | Primary Silver Sources | Notes |
|---|---|---|
| `gold.dim_customers` | `silver.crm_cust_info`, `silver.erp_cust_az12`, `silver.erp_loc_a101` | Joins CRM customer data to ERP demographic and location data using standardized customer IDs. |
| `gold.dim_products` | `silver.crm_prd_info`, `silver.erp_px_cat_g1v2` | Joins product master data to ERP categories and keeps only current product records. |
| `gold.fact_sales` | `silver.crm_sales_details`, `gold.dim_products`, `gold.dim_customers` | Links sales transactions to product and customer surrogate keys for reporting. |
