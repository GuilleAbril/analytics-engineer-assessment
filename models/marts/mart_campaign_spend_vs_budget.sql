-- Part 3 -- Campaign spend vs. budget.
-- Compares each campaign's planned budget with the actual spend reported in the
-- media agency's daily Parquet export.
--   variance     = budget - total_actual_spend   (positive = under budget)
--   variance_pct = variance / budget
--   status       = 'under_budget' | 'over_budget'

with campaigns as (

    select * from {{ ref('stg_campaigns') }}

),

ad_spend as (

    select * from {{ ref('stg_ad_spend') }}

),

spend_per_campaign as (

    select
        campaign_id,
        sum(actual_spend) as total_actual_spend

    from ad_spend
    group by campaign_id

),

joined as (

    select
        campaigns.client_id,
        campaigns.campaign_id,
        campaigns.campaign_name,
        campaigns.channel,
        campaigns.budget,
        -- LEFT JOIN + coalesce: a campaign absent from the spend export has
        -- spent 0, not an unknown amount.
        coalesce(spend_per_campaign.total_actual_spend, 0) as total_actual_spend

    from campaigns
    left join spend_per_campaign
        on campaigns.campaign_id = spend_per_campaign.campaign_id

)

select
    client_id,
    campaign_id,
    campaign_name,
    channel,
    budget,
    total_actual_spend,
    budget - total_actual_spend as variance,
    case
        when budget > 0
            then round((budget - total_actual_spend) / budget, 4)
    end as variance_pct,
    case
        when budget - total_actual_spend < 0 then 'over_budget'
        else 'under_budget'
    end as status

from joined
