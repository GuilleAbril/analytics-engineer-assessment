-- ============================================================
-- ISSUES FOUND:
-- (list your findings here)
-- ============================================================

select
    e.account_id,
    a.account_name,
    a.industry,
    sum(e.revenue_influenced) as total_revenue,
    count(*) as total_events,
    sum(e.revenue_influenced) / count(*) as revenue_per_event

from {{ source('raw', 'raw_events') }} e
left join {{ source('raw', 'raw_accounts') }} a on e.account_id = a.account_id

where e.event_date >= '2024-01-01'

group by 1, 2, 3

order by total_revenue desc
limit 10

-- ============================================================
-- YOUR IMPROVED VERSION:
-- ============================================================
