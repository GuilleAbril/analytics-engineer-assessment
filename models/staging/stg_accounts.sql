with source as (

    select * from {{ source('raw', 'raw_accounts') }}

),

renamed as (

    select
        account_id,
        client_id,
        account_name,
        industry,
        cast(employee_count as integer) as employee_count

    from source
    -- One source row has a NULL account_id ("Account Null ID Corp"). An account
    -- with no key cannot be joined to events or tested, so it is dropped here.
    where account_id is not null

)

select * from renamed
