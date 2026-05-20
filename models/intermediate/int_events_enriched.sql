{{
    config(
        materialized='incremental',
        unique_key='event_id',
        incremental_strategy='delete+insert',
        on_schema_change='append_new_columns',
        partition_by=(
            {'field': 'event_date', 'data_type': 'date', 'granularity': 'month'}
            if target.type == 'bigquery' else none
        ),
        cluster_by=(['client_id', 'channel'] if target.type == 'bigquery' else none)
    )
}}

-- The single, reusable event fact. Every mart selects from this model so the
-- campaign/account joins and funnel definitions are written exactly once.
--
-- Incremental: each run re-processes a trailing look-back window of events
-- (var: late_arriving_lookback_days) and replaces them by event_id, so events
-- ingested late are still picked up. partition_by / cluster_by are emitted only
-- on BigQuery -- see the README, "Performance & efficiency".

with events as (

    select * from {{ ref('stg_events') }}

    {% if is_incremental() %}
    -- Re-read a trailing window rather than only rows newer than the current
    -- max, so late-arriving events within the window are reprocessed. Combined
    -- with delete+insert on event_id, re-read events replace their old version.
    where event_date >= (
        select max(event_date) from {{ this }}
    ) - interval '{{ var("late_arriving_lookback_days", 7) }} days'
    {% endif %}

),

campaigns as (

    select * from {{ ref('stg_campaigns') }}

),

accounts as (

    select * from {{ ref('stg_accounts') }}

),

enriched as (

    select
        events.event_id,
        events.client_id,
        events.event_date,
        date_trunc('month', events.event_date) as event_month,
        events.event_type,
        events.revenue_influenced,

        -- Campaign attributes. LEFT JOIN: one event references a campaign that
        -- is absent from the source; the event (and its revenue) is kept with a
        -- NULL channel rather than being silently dropped.
        events.campaign_id,
        campaigns.campaign_name,
        campaigns.channel,
        campaigns.budget as campaign_budget,

        -- Account attributes.
        events.account_id,
        accounts.account_name,
        accounts.industry,
        accounts.employee_count,

        -- Funnel flags. Conversion events are the only revenue-bearing stages.
        events.event_type in ('form_fill', 'meeting_booked') as is_conversion,
        events.event_type = 'meeting_booked'                 as is_meeting_booked

    from events
    left join campaigns on events.campaign_id = campaigns.campaign_id
    left join accounts  on events.account_id  = accounts.account_id

)

select * from enriched
