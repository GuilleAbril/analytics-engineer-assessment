-- prod (BigQuery): partition_by event_month (month granularity), cluster_by client_id, account_id.
-- Queries for dashboards always filter by client and a date range — partition + cluster covers both.
{{ config(
    tags=['accounts', 'engagement'],
    partition_by={'field': 'event_month', 'data_type': 'date', 'granularity': 'month'},
    cluster_by=['client_id', 'account_id']
) }}

-- Q2: Monthly event counts per (client, account) with month-over-month delta.
-- Decision: months with zero events produce no row (no calendar spine).
-- Consequence: lag() skips over gap months to the previous month with data.
-- If the stakeholder needs explicit zero rows, a date spine would be required.
-- prev_month_events and mom_change are NULL for each account's first observed month — expected.

with monthly as (

    select
        client_id,
        account_id,
        cast(date_trunc('month', event_date) as date) as event_month,
        count(*)                        as total_events
    from {{ ref('stg_events') }}
    group by 1, 2, 3

)

select
    client_id,
    account_id,
    event_month,
    total_events,
    lag(total_events) over (
        partition by client_id, account_id
        order by event_month
    )                                                                       as prev_month_events,
    total_events - lag(total_events) over (
        partition by client_id, account_id
        order by event_month
    )                                                                       as mom_change
from monthly
order by client_id, account_id, event_month
