with source as (

    select * from {{ source('raw', 'raw_events') }}

),

renamed as (

    select
        event_id,
        campaign_id,
        client_id,
        account_id,
        cast(event_date as date)                               as event_date,
        lower(trim(event_type))                                as event_type,
        -- revenue_influenced is only populated on conversion events. Coalescing
        -- to 0 means downstream sums never return NULL and non-revenue events
        -- contribute a true zero rather than an unknown.
        coalesce(cast(revenue_influenced as decimal(18, 2)), 0) as revenue_influenced

    from source
    -- Drop rows with no event_id: the grain is one row per event and a missing
    -- key cannot be de-duplicated, tested, or traced back to the source.
    where event_id is not null

),

deduplicated as (

    -- The raw feed is not guaranteed unique on event_id (it currently contains
    -- one duplicate). Keep a single, deterministically chosen row per event.
    select *
    from renamed
    qualify row_number() over (
        partition by event_id
        order by event_date, campaign_id, account_id
    ) = 1

)

select * from deduplicated
