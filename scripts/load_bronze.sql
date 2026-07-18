-- Bronze layer: land the raw Online Retail workbook into DuckDB exactly as-is.
--
-- The `spatial` extension's st_read() uses GDAL to read the .xlsx sheet. The
-- FIELD_TYPES=STRING open option tells GDAL not to infer INTEGER/DOUBLE/DATE
-- types for any column, so every value comes through as the literal text
-- from the workbook (including float artifacts like 2.5499999999999998 that
-- are genuinely stored in the source file) instead of being silently
-- rounded, reformatted, or coerced by type inference. HEADERS=FORCE makes
-- GDAL always treat row 1 as column names, rather than its own (occasionally
-- wrong) auto-detection heuristic — verified byte-identical output on the
-- real workbook.
--
-- {xlsx_path} is substituted by load_bronze.py — the loading logic itself
-- doesn't know or care which workbook it's pointed at, so tests can exercise
-- it against a small fixture file instead of the real dataset.

INSTALL spatial;
LOAD spatial;

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE OR REPLACE TABLE bronze.online_retail AS
SELECT
    CAST(InvoiceNo   AS VARCHAR) AS InvoiceNo,
    CAST(StockCode   AS VARCHAR) AS StockCode,
    CAST(Description AS VARCHAR) AS Description,
    CAST(Quantity    AS VARCHAR) AS Quantity,
    CAST(InvoiceDate AS VARCHAR) AS InvoiceDate,
    CAST(UnitPrice   AS VARCHAR) AS UnitPrice,
    CAST(CustomerID  AS VARCHAR) AS CustomerID,
    CAST(Country     AS VARCHAR) AS Country
FROM st_read(
    '{xlsx_path}',
    layer = 'Online Retail',
    open_options = ['FIELD_TYPES=STRING', 'HEADERS=FORCE']
);
