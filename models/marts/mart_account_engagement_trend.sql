-- Question 2 -- Account engagement trend.
-- Monthly event volume per client/account and the month-over-month change.
--
-- prev_month_events is taken from the immediately preceding *calendar* month
-- via a self-join, not lag(). lag() over only the months an account was active
-- would compare (say) March to January when February was silent. The self-join
-- correctly yields 0 for a silent previous month.
-- Grain: one row per client + account + month in which the account had events.

with events as (

    select * from {{ ref('int_events_enriched') }}

),

monthly_events as (

    select
        client_id,
        account_id,
        event_month,
        count(*) as total_events

    from events
    group by client_id, account_id, event_month

),

with_previous_month as (

    select
        current_month.client_id,
        current_month.account_id,
        current_month.event_month,
        current_month.total_events,
        coalesce(previous_month.total_events, 0) as prev_month_events

    from monthly_events as current_month
    left join monthly_events as previous_month
        on  current_month.client_id  = previous_month.client_id
        and current_month.account_id = previous_month.account_id
        and previous_month.event_month
            = cast(current_month.event_month - interval '1 month' as date)

)

select
    client_id,
    account_id,
    event_month,
    total_events,
    prev_month_events,
    total_events - prev_month_events as mom_change

from with_previous_month
