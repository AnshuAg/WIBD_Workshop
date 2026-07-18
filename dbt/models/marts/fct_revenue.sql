-- Gold: one row per non-cancelled transaction line item — "what did we
-- actually sell?" Feeds the dashboard's revenue KPIs and charts directly.
select
    invoice_no,
    stock_code,
    description,
    invoice_date,
    date_trunc('month', invoice_date) as invoice_month,
    country,
    customer_id,
    quantity,
    unit_price,
    quantity * unit_price as line_amount
from {{ ref('stg_online_retail') }}
where not is_cancelled
  and quantity > 0
