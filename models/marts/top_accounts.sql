-- ============================================================
-- ISSUES FOUND:
-- (list your findings here)
-- 
-- 1. Use raw tables instead of staging/intermediate views or tables.
-- 2. In case that an account can be a target for two different clients (¿?) client_id sould be considered for the aggrupation
--    In other case it would be considering revenue coming from an account for two different clients as one.
-- 3. It would be sufficient group by account_id and client_id, if only account_id is required. But give more information to the user at a glance.
-- 4. If only total_revenue is required, total_events and revenue_per_event can be deleted. But also can give more usefull information to the user.
-- 5. count(*) consider null or invalid events but sum(e.revenue_influenced) not.
-- 6. order by + limit doesnt guaranteer the order depending the warehouse engine (example: BigQuery or Spark doesnt)
--    Use window function row_number instead.
-- 7. Add hardcoded date from parameter
-- 8. delete mart_ prefix from model name
-- ============================================================

--select
--    e.account_id,
--    a.account_name,
--    a.industry,
--    sum(e.revenue_influenced) as total_revenue,
--    count(*) as total_events,
--    sum(e.revenue_influenced) / count(*) as revenue_per_event
--
--from {{ source('raw', 'raw_events') }} e
--left join {{ source('raw', 'raw_accounts') }} a on e.account_id = a.account_id
--
--where e.event_date >= '2024-01-01'
--
--group by 1, 2, 3
--
--order by total_revenue desc
--limit 10

-- ============================================================
-- YOUR IMPROVED VERSION:
-- ============================================================

{% set top_accounts_start_event_date = var("top_accounts_start_event_date", "2024-01-01") %}

with events as (

    select *
    from {{ ref('stg_raw__events') }}
    where event_date >= cast('{{ top_accounts_start_event_date }}' as date)

),

accounts as (

    select *
    from {{ ref('stg_raw__accounts') }}

),

events_accounts as (

    select
        accounts.client_id,
        events.account_id,
        accounts.account_name,
        accounts.industry,
        events.event_id,
        events.revenue_influenced
    from events
    inner join accounts
        on events.account_id = accounts.account_id

),

accounts_total_revenue as (

    select
        client_id,
        account_id,
        account_name,
        industry,
        sum(revenue_influenced) as total_revenue_influenced,
        count(event_id) as total_events,
        sum(revenue_influenced)
            / nullif(count(event_id), 0) as revenue_per_event
    from events_accounts
    group by client_id, account_id, account_name, industry

),

ranked_accounts_by_revenue as (

    select
        *,
        row_number() over (
            partition by client_id
            order by total_revenue_influenced desc
        ) as account_rank
    from accounts_total_revenue

),

top_accounts as (

    select *
    from ranked_accounts_by_revenue
    where account_rank <= 10

)

select * from top_accounts