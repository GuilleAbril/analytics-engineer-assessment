with source as (

    select * from {{ source('media_agency', 'ad_spend') }}

),

renamed as (

    select
        campaign_id,
        client_id,
        cast(spend_date as date)             as spend_date,
        cast(actual_spend as decimal(18, 2)) as actual_spend

    from source
    where campaign_id is not null

)

select * from renamed
