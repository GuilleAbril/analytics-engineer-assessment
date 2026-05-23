-- prod (BigQuery): cluster_by=['client_id', 'status'] — dashboards filter by tenant and over/under budget status.
{{ config(
    tags=['campaigns', 'budget'],
    cluster_by=['client_id', 'status']
) }}

-- Part 3: Compares each campaign's planned budget against total actual spend from the parquet export.
-- variance > 0 means under budget; variance < 0 means over budget.
-- variance_pct is NULL if budget is 0 (guard against division by zero).

with campaigns as (

    select
        client_id,
        campaign_id,
        campaign_name,
        channel,
        budget
    from {{ ref('stg_campaigns') }}

),

spend_agg as (

    select
        client_id,
        campaign_id,
        sum(actual_spend) as total_actual_spend
    from {{ ref('stg_ad_spend') }}
    group by 1, 2

),

joined as (

    select
        c.client_id,
        c.campaign_id,
        c.campaign_name,
        c.channel,
        c.budget,
        coalesce(s.total_actual_spend, 0)                       as total_actual_spend,
        c.budget - coalesce(s.total_actual_spend, 0)            as variance,
        (c.budget - coalesce(s.total_actual_spend, 0))
            / nullif(c.budget, 0)                               as variance_pct,
        case
            when c.budget - coalesce(s.total_actual_spend, 0) < 0
                then 'over_budget'
            else 'under_budget'
        end                                                     as status
    from campaigns c
    left join spend_agg s
        on  c.campaign_id = s.campaign_id
        and c.client_id   = s.client_id

)

select
    client_id,
    campaign_id,
    campaign_name,
    channel,
    budget,
    total_actual_spend,
    variance,
    variance_pct,
    status
from joined
order by client_id, status, variance
