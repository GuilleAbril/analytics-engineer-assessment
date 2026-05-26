{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['client_id', 'account_id', 'event_month'],
        on_schema_change='sync_all_columns'
    )
}}

-- Model: account_engagement_trend
-- Grain: one row per client + account + calendar month
-- Purpose: Tracks how engagement volume evolves month over month for each account,
--          enabling detection of accounts that are accelerating or dropping off.
--
-- Incremental strategy: delete+insert on a 2-month lookback window.
--   A 2-month buffer is used instead of 1 to handle late-arriving events whose
--   event_date falls in the previous month but are ingested in the current run.
--   The MoM change (mom_change) for the most recent month also depends on the
--   prior month's total, so reprocessing both months keeps the LAG values consistent.

with stg_events_month as (

    select
        event_id,
        client_id,
        account_id,
        {{ dbt.date_trunc('month', 'event_date') }} as event_month
    from {{ ref('stg_raw__events') }}

    {% if is_incremental() %}
        -- On incremental runs, reprocess the last 2 months to capture late arrivals
        -- and recalculate the prev_month_events LAG for the current month correctly
        where {{ dbt.date_trunc('month', 'event_date') }} >= (
            select coalesce(
                {{ dbt.dateadd('month', -2, 'max(event_month)') }},
                date '1900-01-01'  -- fallback for an empty target table
            )
            from {{ this }}
        )
    {% endif %}

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

{% set lag_total_events %}
    lag(total_events) over (
        partition by client_id, account_id
        order by event_month
    )
{% endset %}

account_engagement_trend as (

    select
        client_id,
        account_id,
        cast(event_month as date) as event_month,
        total_events,
        {{ lag_total_events }} as prev_month_events,
        total_events - {{ lag_total_events }} as mom_change
    from events_per_month

)

select * from account_engagement_trend
