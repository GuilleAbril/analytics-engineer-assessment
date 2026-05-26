-- Model: account_engagement_trend_months_filled
-- Grain: one row per client + account + calendar month
-- Purpose: Full-refresh version of account_engagement_trend. Produces identical output
--          without the incremental complexity, useful for backfills, local development,
--          or environments where incremental state cannot be trusted.
--          Takes into account gaps between months.

with stg_events_month as (

    select
        event_id,
        client_id,
        account_id,
        {{ dbt.date_trunc('month', 'event_date') }} as event_month
    from {{ ref('stg_raw__events') }}

),

events_per_month as (

    -- Aggregate total events at the client + account + month grain
    select
        client_id,
        account_id,
        event_month,
        count(event_id) as total_events
    from stg_events_month
    group by client_id, account_id, event_month

),

bounds_months as (
    select
        client_id,
        account_id,
        min(event_month) as min_month,
        max(event_month) as max_month
    from events_per_month
    group by client_id, account_id
),


months_spine as (
    {{ dbt_utils.date_spine(
        datepart="month",
        start_date="cast('2015-01-01' as date)",
        end_date="cast(" ~ dbt.dateadd('month', 1, 'current_date') ~ " as date)"
    ) }}
),

all_months as (
    select
        bounds_months.client_id,
        bounds_months.account_id,
        months_spine.date_month as event_month
    from bounds_months
    inner join months_spine
        on months_spine.date_month between bounds_months.min_month and bounds_months.max_month
),

events_per_months_filled as (
    select
        all_months.client_id,
        all_months.account_id,
        all_months.event_month,
        coalesce(events_per_month.total_events, 0) as total_events
    from all_months
    left join events_per_month
        on  events_per_month.client_id  = all_months.client_id
        and events_per_month.account_id = all_months.account_id
        and events_per_month.event_month = all_months.event_month
),

{% set lag_total_events %}
    lag(total_events) over (
        partition by client_id, account_id
        order by event_month
    )
{% endset %}

account_engagement_trend_months_filled_no_incremental as (

    select
        client_id,
        account_id,
        cast(event_month as date) as event_month,
        total_events,
        {{ lag_total_events }} as prev_month_events,
        total_events - {{ lag_total_events }} as mom_change
    from events_per_months_filled

)

select * from account_engagement_trend_months_filled_no_incremental
