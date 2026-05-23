{{ config(
    tags=['ad_spend']
) }}

-- Reads the Parquet export of daily actual ad spend delivered by the media agency.
-- Path is relative to the project root where dbt commands are run.
-- In dbt-core with dbt-duckdb adapter, source() + external_location meta would replace
-- the read_parquet() call below; dbt-fusion does not support that meta key on sources.

with source as (

    select * from read_parquet('data/ad_spend.parquet')

),

renamed as (

    select
        campaign_id,
        client_id,
        cast(spend_date as date)                as spend_date,
        cast(actual_spend as decimal(18, 2))    as actual_spend

    from source
    where campaign_id is not null
      and client_id is not null

)

select * from renamed
