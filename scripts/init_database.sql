/*
=============================================================
Create Schemas for Data Warehouse
=============================================================
Script Purpose:
    This script creates three schemas for the data warehouse project.

    The project follows the Bronze, Silver, and Gold architecture:
    - bronze: stores raw ingested data
    - silver: stores cleaned and transformed data
    - gold: stores final analytics-ready tables

Database:
    datawarehouse
=============================================================
*/

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE SCHEMA IF NOT EXISTS silver;

CREATE SCHEMA IF NOT EXISTS gold;
