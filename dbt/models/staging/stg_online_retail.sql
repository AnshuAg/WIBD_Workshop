-- Silver: one clean, typed staging model over bronze.online_retail.
--
-- Cancellation rule made explicit: this dataset's convention is that a
-- cancelled order's InvoiceNo is prefixed with 'C' (UCI Online Retail data
-- dictionary). We encode that rule directly rather than a broader "does this
-- look like a return" heuristic.
with source as (

    select * from {{ source('bronze', 'online_retail') }}

),

cleaned as (

    select
        trim(InvoiceNo)                                              as invoice_no,
        starts_with(trim(InvoiceNo), 'C')                            as is_cancelled,
        trim(StockCode)                                              as stock_code,
        nullif(trim(Description), '')                                as description,
        try_cast(Quantity as integer)                                as quantity,
        try_cast(InvoiceDate as timestamp)                           as invoice_date,
        try_cast(UnitPrice as decimal(10, 2))                        as unit_price,
        try_cast(try_cast(nullif(trim(CustomerID), '') as double) as integer) as customer_id,
        trim(Country)                                                as country
    from source

)

-- Bronze intentionally keeps exact-duplicate rows (re-scans/re-exports);
-- collapsing them to one row per unique line item is Silver's job.
select distinct * from cleaned
