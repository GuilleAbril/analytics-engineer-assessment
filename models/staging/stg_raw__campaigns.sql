
{{ config(
    tags=['campaigns']
) }}

with source_campaigns as (

    select * from {{ source('raw', 'raw_campaigns') }}

),

stg_campaigns as (

    select
        campaign_id,
        client_id,
        channel,
        campaign_name,
        cast( start_date as date ) as start_date,
        cast( end_date as date ) as end_date,
        cast(budget as {{ dbt.type_numeric() }} ) as budget

    from source_campaigns
    where campaign_id is not null and client_id is not null

)

select * from stg_campaigns
