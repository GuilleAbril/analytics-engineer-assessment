-- Question 1 -- Top channels per client.
-- For each client, the 3 channels that drove the most influenced revenue over
-- the last N days (var: revenue_window_days, default 90).
--
-- "Last 90 days" is a rolling window. In production it would be measured from
-- current_date; the seed data is static, so the window is anchored to the most
-- recent event_date in the data to keep the result reproducible for reviewers.

with events as (

    select * from {{ ref('int_events_enriched') }}

),

window_bounds as (

    select
        cast(
            max(event_date) - interval '{{ var("revenue_window_days", 90) }} days'
            as date
        ) as window_start_date
    from events

),

channel_revenue as (

    select
        events.client_id,
        events.channel,
        sum(events.revenue_influenced) as total_revenue_influenced

    from events
    cross join window_bounds
    where events.event_date >= window_bounds.window_start_date
      -- The orphan event has no campaign and therefore no channel; an
      -- unattributed channel cannot be ranked.
      and events.channel is not null
    group by events.client_id, events.channel

),

ranked as (

    select
        client_id,
        channel,
        total_revenue_influenced,
        row_number() over (
            partition by client_id
            order by total_revenue_influenced desc, channel
        ) as channel_rank

    from channel_revenue
    -- A channel that influenced no revenue in the window has not "driven
    -- revenue" and should not occupy a top-3 slot.
    where total_revenue_influenced > 0

)

select
    client_id,
    channel,
    total_revenue_influenced,
    channel_rank

from ranked
where channel_rank <= 3
