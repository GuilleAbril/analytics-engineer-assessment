-- prod (BigQuery): cluster_by=['client_id'] — all access patterns filter or partition by tenant.
{{ config(
    tags=['channels'],
    cluster_by=['client_id']
) }}

-- Q1: Top 3 channels per client by revenue influenced over the last 90 days.
-- Only conversion events carry revenue_influenced (form_fill, meeting_booked).
-- row_number() is used instead of rank() to guarantee at most 3 rows per client;
-- ties are broken by insertion order (non-deterministic for exact ties — documented decision).

with base as (

    select
        client_id,
        channel,
        revenue_influenced
    from {{ ref('int_events_enriched') }}
    where is_conversion_event
      and event_date >= cast({{ var('reference_date', 'current_date') }} as date) - interval '90' day

),

agg as (

    select
        client_id,
        channel,
        sum(revenue_influenced) as total_revenue_influenced
    from base
    group by 1, 2

),

ranked as (

    select
        client_id,
        channel,
        total_revenue_influenced,
        row_number() over (
            partition by client_id
            order by total_revenue_influenced desc
        ) as channel_rank
    from agg

)

select
    client_id,
    channel,
    total_revenue_influenced,
    channel_rank
from ranked
where channel_rank <= 3
order by client_id, channel_rank
