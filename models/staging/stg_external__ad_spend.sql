
{{ config(
    tags=['ad_spend']
) }}

with source_ad_spend as (

    select * from {{ source('external', 'ad_spend') }}

),

stg_ad_spend as (

    select
        campaign_id,
        client_id,
        cast(spend_date as date) as spend_date,
        cast(actual_spend as {{ dbt.type_numeric() }} ) as actual_spend

    from source_ad_spend
    where campaign_id is not null and
        client_id is not null

)

select * from stg_ad_spend
