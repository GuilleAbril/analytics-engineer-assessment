
{{ config(
    tags=['events']
) }}

with source_events as (

    select * from {{ source('raw', 'raw_events') }}

),

stg_events as (

    select
        event_id,
        campaign_id,
        client_id,
        cast(event_date as date) as event_date,
        event_type,
        account_id,
        cast(revenue_influenced as {{ dbt.type_numeric() }} ) as revenue_influenced

    from source_events
    where event_id is not null and 
        campaign_id is not null and 
        client_id is not null and
        account_id is not null

)

select * from stg_events
