-- Model: efficient_campaigns
-- Grain: one row per campaign that has at least one meeting booked
-- Purpose: Identifies cost efficiency for each campaign by computing cost per meeting
--          (budget / meetings_booked) and comparing it against the average for its channel.
--          Campaigns with no meetings booked are excluded because they have no efficiency signal
--          and would cause a division-by-zero error.

with stg_events_meeting_booked as (

    select
        campaign_id,
        client_id,
        event_type
    from {{ ref('stg_raw__events') }}
    where event_type = 'meeting_booked'

),

stg_campaigns as (

    select
        client_id,
        campaign_id,
        campaign_name,
        channel,
        budget
    from {{ ref('stg_raw__campaigns') }}

),

meeting_booked as (

    select
        campaign_id,
        client_id,
        count(*) as meetings_booked
    from stg_events_meeting_booked
    group by client_id, campaign_id

),

efficient_campaigns as (

    select
        campaigns.client_id,
        campaigns.campaign_id,
        campaigns.campaign_name,
        campaigns.channel,
        campaigns.budget,
        meeting_booked.meetings_booked,
        (campaigns.budget / meeting_booked.meetings_booked) as cost_per_meeting,
        avg(campaigns.budget / meeting_booked.meetings_booked) over (
            partition by campaigns.client_id, campaigns.channel
        ) as avg_cost_per_meeting_for_channel
    from meeting_booked
    left join stg_campaigns as campaigns
    on meeting_booked.campaign_id = campaigns.campaign_id

)

select * from efficient_campaigns
