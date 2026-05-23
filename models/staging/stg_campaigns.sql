-- Reference model — provided as an example of code style and conventions.
-- Use it as a guide; you are not required to follow this structure exactly.

{{ config(
    tags=['campaigns']
) }}

with source as (

    select * from {{ source('raw', 'raw_campaigns') }}

),

renamed as (

    select
        campaign_id,
        client_id,
        channel,
        campaign_name,
        cast(start_date as date)                                            as start_date,
        cast(end_date as date)                                              as end_date,
        cast(budget as decimal)                                             as budget,
        datediff('day', cast(start_date as date), cast(end_date as date))  as campaign_duration_days

    from source
    where campaign_id is not null
      and client_id is not null

)

select * from renamed
