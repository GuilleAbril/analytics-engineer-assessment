-- Question 3 -- Efficient campaigns.
-- Campaigns that beat their channel peers on cost efficiency, where
-- efficiency = budget / meetings_booked (lower is better).
--
-- Campaigns with zero meetings booked are excluded: cost_per_meeting would be
-- undefined (division by zero) and the question explicitly scopes them out.
-- avg_cost_per_meeting_for_channel is the mean of the per-campaign
-- cost_per_meeting across the channel -- the peer benchmark each campaign is
-- compared against.

with events as (

    select * from {{ ref('int_events_enriched') }}

),

campaigns as (

    select * from {{ ref('stg_campaigns') }}

),

meetings_per_campaign as (

    select
        campaign_id,
        count(*) as meetings_booked

    from events
    where is_meeting_booked
    group by campaign_id

),

campaign_efficiency as (

    select
        campaigns.client_id,
        campaigns.campaign_id,
        campaigns.campaign_name,
        campaigns.channel,
        campaigns.budget,
        meetings_per_campaign.meetings_booked,
        campaigns.budget / meetings_per_campaign.meetings_booked as cost_per_meeting

    from campaigns
    -- INNER JOIN drops campaigns with no meetings booked (see header).
    inner join meetings_per_campaign
        on campaigns.campaign_id = meetings_per_campaign.campaign_id

),

with_channel_benchmark as (

    select
        client_id,
        campaign_id,
        campaign_name,
        channel,
        budget,
        meetings_booked,
        cost_per_meeting,
        avg(cost_per_meeting) over (partition by channel)
            as avg_cost_per_meeting_for_channel

    from campaign_efficiency

)

select
    client_id,
    campaign_id,
    campaign_name,
    channel,
    budget,
    meetings_booked,
    cost_per_meeting,
    avg_cost_per_meeting_for_channel

from with_channel_benchmark
-- "Outperforming" = strictly beating the channel peer benchmark.
where cost_per_meeting < avg_cost_per_meeting_for_channel
