{{ config(
    tags=['accounts']
) }}

with source as (

    select * from {{ source('raw', 'raw_accounts') }}

),

renamed as (

    select
        account_id,
        client_id,
        account_name,
        industry,
        cast(employee_count as integer)                                     as employee_count,
        case
            when cast(employee_count as integer) < 50    then 'small'
            when cast(employee_count as integer) <= 500  then 'mid'
            else 'enterprise'
        end                                                                 as employee_size_band

    from source
    where account_id is not null
      and client_id is not null

)

select * from renamed
