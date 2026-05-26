-- Model: account_engagement_trend
-- Grain: one row per client + account + calendar month
-- Strategy: incremental merge with a lookback window to handle late-arriving
--           events, lag() continuity, and gap-filling across months.

{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['client_id', 'account_id', 'event_month'],
    on_schema_change='sync_all_columns'
) }}

{% set lookback_months = 3 %}

with stg_events_month as (

    select
        event_id,
        client_id,
        account_id,
        {{ dbt.date_trunc('month', 'event_date') }} as event_month
    from {{ ref('stg_raw__events') }}

    {% if is_incremental() %}
        -- Only pull events from the reprocess window onward.
        -- We compute the window from the existing table so we don't depend on wall-clock dates.
        where {{ dbt.date_trunc('month', 'event_date') }} >= (
            select {{ dbt.dateadd('month', -1 * lookback_months, 'max(event_month)') }}
            from {{ this }}
        )
    {% endif %}

),

-- Aggregate new/changed events at the client + account + month grain
new_events_per_month as (

    select
        client_id,
        account_id,
        event_month,
        count(event_id) as total_events
    from stg_events_month
    group by client_id, account_id, event_month

),

-- Identify which (client, account) pairs are affected this run.
-- We need to rebuild ALL months in the reprocess window for these pairs,
-- not just the months that have new events, because gap-filled rows
-- (with total_events = 0) also need to exist and the lag() must be continuous.
affected_pairs as (

    select distinct client_id, account_id
    from new_events_per_month

),

{% if is_incremental() %}

-- For affected pairs, get the historical bounds from both the existing table
-- and the new events, so we know the full month range to materialize.
existing_bounds as (

    select
        t.client_id,
        t.account_id,
        min(t.event_month) as min_month,
        max(t.event_month) as max_month
    from {{ this }} t
    inner join affected_pairs ap
        on  ap.client_id  = t.client_id
        and ap.account_id = t.account_id
    group by t.client_id, t.account_id

),

new_bounds as (

    select
        client_id,
        account_id,
        min(event_month) as min_month,
        max(event_month) as max_month
    from new_events_per_month
    group by client_id, account_id

),

bounds_months as (

    select
        coalesce(e.client_id,  n.client_id)  as client_id,
        coalesce(e.account_id, n.account_id) as account_id,
        least(
            coalesce(e.min_month, n.min_month),
            coalesce(n.min_month, e.min_month)
        ) as min_month,
        greatest(
            coalesce(e.max_month, n.max_month),
            coalesce(n.max_month, e.max_month)
        ) as max_month
    from existing_bounds e
    full outer join new_bounds n
        on  e.client_id  = n.client_id
        and e.account_id = n.account_id

),

{% else %}

-- Full refresh path: bounds come straight from the source
bounds_months as (

    select
        client_id,
        account_id,
        min(event_month) as min_month,
        max(event_month) as max_month
    from new_events_per_month
    group by client_id, account_id

),

{% endif %}

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

-- For incremental runs, we need full historical totals for the affected pairs
-- (so lag() works correctly across the boundary). We take new totals where
-- available, else fall back to the previously stored totals.
{% if is_incremental() %}

existing_totals as (

    select
        t.client_id,
        t.account_id,
        t.event_month,
        t.total_events
    from {{ this }} t
    inner join affected_pairs ap
        on  ap.client_id  = t.client_id
        and ap.account_id = t.account_id

),

merged_totals as (

    select
        am.client_id,
        am.account_id,
        am.event_month,
        coalesce(n.total_events, e.total_events, 0) as total_events
    from all_months am
    left join new_events_per_month n
        on  n.client_id  = am.client_id
        and n.account_id = am.account_id
        and n.event_month = am.event_month
    left join existing_totals e
        on  e.client_id  = am.client_id
        and e.account_id = am.account_id
        and e.event_month = am.event_month

),

{% else %}

merged_totals as (

    select
        am.client_id,
        am.account_id,
        am.event_month,
        coalesce(n.total_events, 0) as total_events
    from all_months am
    left join new_events_per_month n
        on  n.client_id  = am.client_id
        and n.account_id = am.account_id
        and n.event_month = am.event_month

),

{% endif %}

{% set lag_total_events %}
    lag(total_events) over (
        partition by client_id, account_id
        order by event_month
    )
{% endset %}

with_lag as (

    select
        client_id,
        account_id,
        cast(event_month as date) as event_month,
        total_events,
        {{ lag_total_events }} as prev_month_events,
        total_events - {{ lag_total_events }} as mom_change
    from merged_totals

)

select * from with_lag

{% if is_incremental() %}
    -- Only emit rows inside the reprocess window. Older months for the
    -- affected pairs were only re-read so lag() would be correct at the
    -- window boundary; they don't need to be re-merged into {{ this }}.
    where event_month >= (
        select {{ dbt.dateadd('month', -1 * lookback_months, 'max(event_month)') }}
        from {{ this }}
    )
{% endif %}