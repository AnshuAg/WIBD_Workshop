INSTALL excel;
LOAD excel;

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE OR REPLACE TABLE bronze.online_retail AS
SELECT *
FROM read_xlsx(
    '{xlsx_path}',
    sheet = 'Online Retail',
    all_varchar = true
);
