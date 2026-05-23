-- prod (BigQuery): partition by event_date (day), cluster by client_id, campaign_id.
-- Incremental strategy: delete+insert with a 7-day lookback window to handle late-arriving data.
-- This covers the vast majority of event delays while keeping partition scans bounded.
{{ config(
    tags=['events'],
    materialized='incremental',
    unique_key='event_id',
    incremental_strategy='delete+insert',
    partition_by={'field': 'event_date', 'data_type': 'date', 'granularity': 'day'},
    cluster_by=['client_id', 'campaign_id']
) }}

with source as (

    select * from {{ source('raw', 'raw_events') }}

    {% if is_incremental() %}
        where cast(event_date as date) >= (
            select max(event_date) - interval '7' day from {{ this }}
        )
    {% endif %}

),

renamed as (

    select
        event_id,
        campaign_id,
        client_id,
        account_id,
        cast(event_date as date)                                            as event_date,
        event_type,
        cast(revenue_influenced as decimal(18, 2))                          as revenue_influenced,
        event_type in ('form_fill', 'meeting_booked')                       as is_conversion_event

    from source
    where event_id is not null
      and campaign_id is not null
      and account_id is not null

)

select * from renamed
