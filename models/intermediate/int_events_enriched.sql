{{ config(
    tags=['events', 'intermediate']
) }}

-- Enriches events with campaign metadata (channel, campaign_name, budget, dates).
-- Join is conditioned on both campaign_id AND client_id to prevent cross-tenant
-- data leakage in case of any campaign_id collisions across clients.

with events as (

    select * from {{ ref('stg_events') }}

),

campaigns as (

    select * from {{ ref('stg_campaigns') }}

),

enriched as (

    select
        e.event_id,
        e.client_id,
        e.account_id,
        e.campaign_id,
        e.event_date,
        e.event_type,
        e.revenue_influenced,
        e.is_conversion_event,
        c.channel,
        c.campaign_name,
        c.budget,
        c.start_date      as campaign_start_date,
        c.end_date        as campaign_end_date

    from events e
    left join campaigns c
        on e.campaign_id = c.campaign_id
       and e.client_id   = c.client_id

)

select * from enriched
