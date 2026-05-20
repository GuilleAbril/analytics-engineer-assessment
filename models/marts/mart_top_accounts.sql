-- ============================================================
-- ISSUES FOUND in the original mart_top_accounts.sql
-- ============================================================
--
-- 1. "Top 10 by client" was never implemented. The model used a single global
--    `LIMIT 10`, returning 10 accounts overall instead of the top 10 per
--    client. `client_id` was not even selected -- unusable on a multi-tenant
--    platform and a cross-client data-leak risk in any BI tool.
--
-- 2. `LIMIT` is the wrong tool for "top N per group". Per-client ranking needs
--    a window function (ROW_NUMBER() partitioned by client_id).
--
-- 3. Reads straight from `source()`. This skips the staging layer entirely,
--    breaking the staging -> marts contract: casting, key cleaning, the
--    NULL-account-id drop and the duplicate-event de-duplication all live in
--    staging and are bypassed here.
--
-- 4. `total_revenue` can come back NULL. `revenue_influenced` is NULL for
--    impressions/clicks, so an account with no conversions yields SUM(NULL) =
--    NULL, which then sorts unpredictably. Needs COALESCE(..., 0).
--
-- 5. `revenue_per_event` divides revenue by COUNT(*) of *all* events, including
--    impressions and clicks that can never carry revenue. The metric is
--    mechanically diluted and misleading -- it has been dropped in favour of
--    total_conversions (revenue is meaningful only against conversions).
--
-- 6. Division-by-zero exposure in `revenue_per_event`, guarded only by the
--    accident that COUNT(*) > 0 after grouping. The intent is unsafe.
--
-- 7. `WHERE event_date >= '2024-01-01'` is a magic-string filter with no
--    rationale. The dataset starts in 2025, so the filter silently does
--    nothing -- dead code that misleads the next reader.
--
-- 8. `LEFT JOIN` to accounts lets events with an unknown account survive with
--    NULL account_name/industry. For a "top accounts" model the relationship
--    should be enforced (and tested), not silently tolerated.
--
-- 9. `GROUP BY 1, 2, 3` uses positional grouping -- it breaks silently if the
--    SELECT list is reordered. Group by explicit column names.
--
-- 10. `ORDER BY` inside a table-materialized model is wasted work: result
--     ordering is not guaranteed to survive materialization and belongs in the
--     BI layer.
--
-- 11. Naming/grain: `total_revenue` should be `total_revenue_influenced` (the
--     domain term -- revenue is *influenced*, not booked). The model also had
--     no tests and no documentation despite being end-user facing.
--
-- ============================================================
-- IMPROVED VERSION -- top 10 accounts per client by influenced revenue.
-- Built on int_events_enriched so the campaign/account joins, key cleaning and
-- funnel flags are defined once and reused.
-- ============================================================

with events as (

    select * from {{ ref('int_events_enriched') }}

),

account_revenue as (

    select
        client_id,
        account_id,
        account_name,
        industry,
        sum(revenue_influenced)               as total_revenue_influenced,
        count(*)                              as total_events,
        count(*) filter (where is_conversion) as total_conversions

    from events
    group by client_id, account_id, account_name, industry

),

ranked as (

    select
        client_id,
        account_id,
        account_name,
        industry,
        total_revenue_influenced,
        total_events,
        total_conversions,
        row_number() over (
            partition by client_id
            order by total_revenue_influenced desc, account_id
        ) as account_rank

    from account_revenue

)

select
    client_id,
    account_id,
    account_name,
    industry,
    total_revenue_influenced,
    total_events,
    total_conversions,
    account_rank

from ranked
where account_rank <= 10
