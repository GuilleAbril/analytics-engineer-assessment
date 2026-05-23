{{ config(
    tags=['campaigns', 'intermediate']
) }}

-- Pre-aggregates campaign-level performance metrics used by Q3 and Part 3.
-- Kept as a view so it always reflects the latest stg_events state without
-- a separate materialization step.

with enriched as (

    select * from {{ ref('int_events_enriched') }}

),

aggregated as (

    select
        client_id,
        campaign_id,
        channel,
        campaign_name,
        budget,
        count(*)                                                        as total_events,
        count(*) filter (where event_type = 'impression')               as total_impressions,
        count(*) filter (where event_type = 'click')                    as total_clicks,
        count(*) filter (where event_type = 'form_fill')                as total_form_fills,
        count(*) filter (where event_type = 'meeting_booked')           as total_meetings_booked,
        sum(revenue_influenced)                                         as total_revenue_influenced

    from enriched
    group by 1, 2, 3, 4, 5

)

select * from aggregated
