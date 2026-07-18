-- A completed sale always has a positive line amount. A negative
-- line_amount means a non-sale row (e.g. a bad-debt adjustment) slipped
-- through the cancellation filter.
select *
from {{ ref('fct_revenue') }}
where line_amount < 0
