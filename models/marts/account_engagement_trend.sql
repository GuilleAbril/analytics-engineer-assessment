
with stg_events_month as (

    select 
        event_id, 
        client_id, 
        account_id, 
        {{ dbt.date_trunc('month', 'event_date') }} as event_month
    from {{ ref('stg_raw__events') }}

),

events_per_month as (

    select 
        client_id, 
        account_id, 
        event_month, 
        count(1) as total_events
    from stg_events_month
    group by client_id, account_id, event_month

),

account_engagement_trend as (

    select 
        client_id, 
        account_id,
        cast ( event_month as date ) as event_month,
        total_events,
        lag(total_events) over (order by event_month) as prev_month_events,
        total_events - lag(total_events) over (order by event_month) as mom_change
    from events_per_month

)

select * from account_engagement_trend
