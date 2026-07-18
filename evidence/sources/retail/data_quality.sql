select 'bronze: raw rows loaded' as check_name, count(*) as row_count
from bronze.online_retail
union all
select 'silver: typed + deduped rows', count(*)
from stg_online_retail
union all
select 'silver: excluded — cancelled orders', count(*)
from stg_online_retail
where is_cancelled
union all
select 'silver: excluded — non-positive quantity', count(*)
from stg_online_retail
where quantity is null or quantity <= 0
union all
select 'silver: excluded — non-positive unit price', count(*)
from stg_online_retail
where unit_price is null or unit_price <= 0
union all
select 'silver: rows missing customer_id', count(*)
from stg_online_retail
where customer_id is null
union all
select 'gold: revenue rows (fct_revenue)', count(*)
from fct_revenue
