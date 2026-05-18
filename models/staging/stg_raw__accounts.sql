
{{ config(
    tags=['accounts']
) }}

with source as (

    select * from {{ source('raw', 'raw_accounts') }}

),

stg_accounts as (

    select
        account_id,
        account_name,
        industry,
        cast( employee_count as {{ dbt.type_int() }} ) as employee_count,
        client_id

    from source
    where account_id is not null and client_id is not null

)

select * from stg_accounts
