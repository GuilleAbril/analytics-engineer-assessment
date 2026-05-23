-- ============================================================
-- ISSUES FOUND:
-- 1. Missing client_id everywhere (SELECT, JOIN, GROUP BY) — multi-tenant data leak; "top by client" intent not met.
-- 2. `limit 10` is global, not per-client. Needs row_number() partitioned by client_id.
-- 3. JOIN condition omits client_id — can mix accounts across tenants if account_id is not globally unique.
-- 4. `revenue_per_event` divides by count(*) of all events including impressions/clicks (zero revenue) — KPI is meaningless.
-- 5. Reads source() directly from a mart — violates staging→marts layering required by the project.
-- 6. Hardcoded date '2024-01-01' — not parameterizable, ages badly, breaks reproducibility.
-- 7. LEFT JOIN on accounts causes NULL group rows for orphan events; INNER JOIN is correct (bad event data should be caught by tests).
-- 8. No tests, no YAML documentation entry.
-- ============================================================

-- prod (BigQuery): cluster_by=['client_id'] — multi-tenant access pattern; all queries filter by tenant first.
{{ config(
    tags=['accounts'],
    cluster_by=['client_id']
) }}

-- YOUR IMPROVED VERSION:
-- Top 10 accounts per client by total revenue influenced (all-time).
-- Filters the last 365 days; remove or widen the filter if all-time is preferred.
-- INNER JOIN ensures orphan events (account_id not in stg_accounts) are excluded rather
-- than surfaced as NULL rows — data quality issues are caught upstream by relationship tests.

with events as (

    select
        client_id,
        account_id,
        revenue_influenced,
        is_conversion_event
    from {{ ref('stg_events') }}
    where event_date >= cast({{ var('reference_date', 'current_date') }} as date) - interval '365' day

),

accounts as (

    select
        client_id,
        account_id,
        account_name,
        industry
    from {{ ref('stg_accounts') }}

),

agg as (

    select
        e.client_id,
        e.account_id,
        a.account_name,
        a.industry,
        sum(e.revenue_influenced)                           as total_revenue_influenced,
        count(*) filter (where e.is_conversion_event)       as total_conversion_events
    from events e
    inner join accounts a
        on  e.account_id = a.account_id
        and e.client_id  = a.client_id
    group by 1, 2, 3, 4

),

ranked as (

    select
        client_id,
        account_id,
        account_name,
        industry,
        total_revenue_influenced,
        total_conversion_events,
        row_number() over (
            partition by client_id
            order by total_revenue_influenced desc nulls last
        ) as account_rank
    from agg

)

select
    client_id,
    account_id,
    account_name,
    industry,
    total_revenue_influenced,
    total_conversion_events,
    account_rank
from ranked
where account_rank <= 10
order by client_id, account_rank
