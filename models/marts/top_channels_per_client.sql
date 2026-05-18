

with stg_events_revenued_last_90_days as (

    select campaign_id, client_id, revenue_influenced 
    from {{ ref('stg_raw__events') }}
    where 
        event_date >= {{ dbt.dateadd('day', -90, 'current_date') }} and 
        event_type in ('form_fill', 'meeting_booked')

),

stg_campaigns as (

    select campaign_id, channel from {{ ref('stg_raw__campaigns') }}

),

events_revenued_campaign as (

        select
        e.client_id, 
        c.channel,
        e.revenue_influenced
    from stg_events_revenued_last_90_days as e
    left join stg_campaigns as c
    on e.campaign_id = c.campaign_id

),

total_revenue_client_channel as (

    select
        client_id, 
        channel,
        sum(revenue_influenced) as total_revenue_influenced
    from events_revenued_campaign
    group by client_id, channel

),

ranked_channels_per_client as (

    select 
        client_id,
        channel,
        total_revenue_influenced,
        rank() over (
            partition by client_id 
            order by total_revenue_influenced desc
        ) as channel_rank
    from total_revenue_client_channel

),

top_channels_per_client as (

    select * from ranked_channels_per_client where channel_rank <= 3
    
)

select * from top_channels_per_client