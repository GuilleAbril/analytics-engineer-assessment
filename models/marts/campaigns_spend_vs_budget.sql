
with stg_campaigns as (

    select
        client_id,
        campaign_id,
        campaign_name,
        channel,
        budget
    from {{ ref('stg_raw__campaigns') }}

),

stg_ad_spend as (
    select
        campaign_id,
        client_id,
        actual_spend
    from {{ ref('stg_external__ad_spend') }}
),

campaigns_total_spend as (
    select
        campaign_id,
        client_id,
        sum(actual_spend) as total_actual_spend
    from stg_ad_spend
    group by campaign_id, client_id
),

campaigns_spend_vs_budget as (
    select
        campaigns.client_id,
        campaigns.campaign_id,
        campaigns.campaign_name,
        campaigns.channel,
        campaigns.budget,
        total_spend.total_actual_spend,
        ( campaigns.budget - total_spend.total_actual_spend ) as variance,
        round( ( variance / campaigns.budget ) * 100, 2) as variance_pct,
        CASE 
            WHEN variance > 0 THEN 'under budget'
            WHEN variance < 0 THEN 'over budget'
            ELSE 'equal budget'
        END
            as status

    from stg_campaigns as campaigns
    left join campaigns_total_spend as total_spend
    on campaigns.client_id = total_spend.client_id and campaigns.campaign_id = total_spend.campaign_id
)

select * from campaigns_spend_vs_budget