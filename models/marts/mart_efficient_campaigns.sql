-- prod (BigQuery): cluster_by=['channel', 'client_id'] — typical access: filter by channel, then tenant.
{{ config(
    tags=['campaigns', 'efficiency'],
    cluster_by=['channel', 'client_id']
) }}

-- Q3: Campaigns that outperform their channel peers on cost efficiency.
-- Efficiency = budget / meetings_booked (lower is better).
-- "Outperforming" = cost_per_meeting < avg_cost_per_meeting_for_channel.
-- avg_cost_per_meeting_for_channel is the unweighted mean across all campaigns in the same channel
-- that had at least one meeting booked (excludes zero-meeting campaigns from the peer benchmark).
-- Campaigns with zero meetings booked are excluded — cost_per_meeting would be undefined.

with cp as (

    select
        client_id,
        campaign_id,
        campaign_name,
        channel,
        budget,
        total_meetings_booked                                           as meetings_booked,
        budget / nullif(total_meetings_booked, 0)                       as cost_per_meeting
    from {{ ref('int_campaign_performance') }}
    where total_meetings_booked > 0

),

with_channel_avg as (

    select
        client_id,
        campaign_id,
        campaign_name,
        channel,
        budget,
        meetings_booked,
        cost_per_meeting,
        avg(cost_per_meeting) over (
            partition by channel
        )                                                               as avg_cost_per_meeting_for_channel
    from cp

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
from with_channel_avg
where cost_per_meeting < avg_cost_per_meeting_for_channel
order by channel, cost_per_meeting
