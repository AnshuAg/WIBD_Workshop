-- Silver should only drop bronze's exact-duplicate rows — nothing else.
-- If this returns a row, stg_online_retail's row count diverged from
-- "all bronze rows, deduplicated" for a reason nobody explicitly decided on.
with bronze_distinct as (

    select count(*) as row_count
    from (select distinct * from {{ source('bronze', 'online_retail') }})

),

staging as (

    select count(*) as row_count
    from {{ ref('stg_online_retail') }}

)

select *
from bronze_distinct
cross join staging
where bronze_distinct.row_count != staging.row_count
