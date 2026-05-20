# Octane11 — Sr. Analytics Engineer Technical Assessment

Welcome, and thanks for taking the time to complete this assessment. This exercise is designed to reflect the kind of work you'd actually be doing at Octane11 — no algorithmic puzzles, no trick questions.

**Estimated time: 2–3 hours.** We don't expect perfection. We're more interested in how you think, structure your work, and explain your decisions than in a complete solution.

Approach this exercise the same way you would any task in your day-to-day work — use whatever tools, references, and resources you normally rely on. What matters is the quality of your thinking and the decisions you make, not how you got there.

Feel free to go beyond what's asked. If you spot something worth improving, add a test that would catch a real bug, or see an opportunity to make the project more production-ready — go for it. Treat it as if it were your own codebase.

---

## Context

You are joining the data team at a B2B marketing analytics platform. The platform ingests marketing activity data from multiple channels (paid media, email, CRM) across multiple clients and helps them understand what's driving pipeline and revenue.

You have been given a dbt project with raw seed data already loaded. Your job is to build a small but production-quality analytics layer on top of it.

---

## Setup

### Requirements
- Python 3.11–3.13 (3.14 is not yet supported by dbt)
- dbt-duckdb (`pip install dbt-duckdb`)
- No cloud account or credentials needed — everything runs locally

### Getting started

1. Create your repository from this template (click **"Use this template"** on GitHub) and clone it locally
2. Copy `profiles.yml` to `~/.dbt/profiles.yml`, or add the profile within it to your existing `~/.dbt/profiles.yml` if you already have one
3. Run `dbt deps` to install packages
4. Run `dbt seed` to load the sample data
5. Run `dbt run` to execute models
6. You're ready to go

A local DuckDB database file (`octane11_analytics.duckdb`) will be created automatically in the project root. You can query it directly using the DuckDB CLI or any SQL client that supports DuckDB (e.g. DBeaver, TablePlus).

---

## The Data

Octane11 is a **multi-tenant platform** — multiple clients use it to run and measure their marketing activity. Each client targets their own set of accounts (B2B companies) through campaigns across different channels.

Three seed tables are provided:

| Table | Rows | Description |
|-------|------|-------------|
| `raw_campaigns` | ~50 | Marketing campaigns with `campaign_id`, `client_id`, `channel`, `campaign_name`, `start_date`, `end_date`, `budget` |
| `raw_accounts` | ~100 | B2B companies with `account_id`, `account_name`, `industry`, `employee_count`, `client_id` |
| `raw_events` | ~2,000 | Engagement events with `event_id`, `campaign_id`, `client_id`, `event_date`, `event_type` (`impression`, `click`, `form_fill`, `meeting_booked`), `account_id`, `revenue_influenced` |

**How the tables relate:**
- Each **campaign** belongs to a client and runs on a single channel over a fixed period with a set budget. A **channel** is the marketing medium used to reach accounts — in this dataset: `linkedin`, `google`, `email`, `display`, and `content`.
- Each **account** is a B2B company in a client's target market, segmented by industry and employee count.
- Each **event** records a moment an account engaged with a campaign. Events are linked to both a campaign (`campaign_id`) and an account (`account_id`).

**The engagement funnel:**

In B2B marketing, the goal is not to reach individuals but to engage entire companies — called **accounts** — and move them through a buying journey. This is often referred to as Account-Based Marketing (ABM). Campaigns run across multiple channels to create touchpoints with target accounts, and each interaction is recorded as an event.

Events follow a funnel from awareness to high-intent action:

| Event type | What it means |
|---|---|
| `impression` | The account was exposed to an ad or piece of content — they saw it, but did not interact |
| `click` | The account clicked through, showing active interest |
| `form_fill` | The account submitted a lead form — a meaningful conversion and a strong buying signal |
| `meeting_booked` | The account booked a sales meeting — the highest-intent action before a deal is opened |

`revenue_influenced` is only populated on conversion events (`form_fill`, `meeting_booked`) — it represents the pipeline value attributed to that touchpoint, based on what the account eventually contributed to in terms of closed or forecasted revenue. Impressions and clicks do not carry revenue.

> **Example:** Account A fills out a form after seeing a LinkedIn campaign. That account later closes a $50,000 deal. The `revenue_influenced` on that `form_fill` event would be $50,000 — reflecting that the campaign touchpoint played a role in generating that revenue.

---

## The Assessment

### Getting Started

Build a production-quality analytics layer on top of the seed data. We're leaving the specific models and their names up to you — deciding *what to build and why* is part of what we're evaluating.

A reference staging model (`stg_campaigns`) is provided as a reference.

**Requirements:**
- Follow a clear staging → marts separation using `ref()` and `source()`
- Add at least 2 dbt tests
- Document at least one model in a YAML file
- Where relevant, apply the BigQuery optimizations you'd use in a production environment (partitioning, clustering, incremental) — and be ready to explain your choices

**Optional bonus:** Where relevant, convert your models to incremental. Be ready to explain your strategy for handling late-arriving data.

---

### Part 1 — Business Questions (~90 min)

A stakeholder comes to you with three data requests. For each, build a dbt model that answers the question. You decide the model name, layer, and structure — including any intermediate models you think are needed to keep the logic clean and readable.

**Question 1 — Top channels per client**

For each client, which channels have driven the most revenue over the last 90 days? The stakeholder wants to see the top 3 channels per client, ranked by total revenue influenced.

Expected output fields: `client_id`, `channel`, `total_revenue_influenced`, `channel_rank`

---

**Question 2 — Account engagement trend**

The team wants to understand how engagement volume for individual accounts changes month over month. For each client and account, show the total number of events per month and how that compares to the previous month.

Expected output fields: `client_id`, `account_id`, `event_month`, `total_events`, `prev_month_events`, `mom_change`

---

**Question 3 — Efficient campaigns**

Find campaigns that are outperforming their channel peers on cost efficiency. Efficiency is defined as `budget / meetings_booked`. Exclude campaigns with no meetings booked.

Expected output fields: `client_id`, `campaign_id`, `campaign_name`, `channel`, `budget`, `meetings_booked`, `cost_per_meeting`, `avg_cost_per_meeting_for_channel`

---

### Part 2 — Code Review (~30 min)

Open `models/marts/mart_top_accounts.sql`.

You'll find a model written by a former team member. It is intended to show the top 10 accounts by total revenue influenced (by client). It has several issues.

1. List all the issues you find (as comments at the top of the file)
2. Rewrite the model with your improvements
3. Be ready to walk through your changes during the debrief

---

### Part 3 *(optional)* — External Data Source

This part is not required. It is here if you want to go further and demonstrate additional depth. Only attempt it once Parts 1 and 2 are complete.

The media agency that manages campaign spend on behalf of clients delivers a daily export of actual ad spend at the campaign level. You've been given that file at `data/ad_spend.parquet`.

Your task:

1. Make the Parquet file available as a source in the dbt project — you'll need to figure out the right approach for DuckDB
2. Create a staging model for it
3. Build a mart that compares each campaign's total actual spend against its planned budget
4. Document the steps needed to make the Parquet file available so we can reproduce your setup when reviewing your solution

Expected output fields: `client_id`, `campaign_id`, `campaign_name`, `channel`, `budget`, `total_actual_spend`, `variance`, `variance_pct`, `status`

> `variance` = `budget - total_actual_spend` (positive = under budget, negative = over budget)
> `status` = `'under_budget'` or `'over_budget'`

---

## Submission

1. Click **"Use this template"** on GitHub to create your own repository (private or public — your choice)
2. Do your work on your repository
3. Share the link with us when you're done — if private, let us know and we'll tell you who to grant access to
4. We'll schedule time to debrief where you'll walk us through your solution

---

## What We're Looking For

| Area | What matters |
|------|-------------|
| Modeling decisions | Did you choose the right layers, grains, and model names — and can you justify them? |
| SQL quality | Correct, performant, readable |
| dbt structure | Proper layering, use of ref/source, tests, docs |
| Performance & efficiency | Applies the right optimization techniques (partitioning, clustering, incremental) where appropriate and for the right reasons |
| Window functions | Used correctly with real business logic |
| Code review | Did you find the obvious issues? The subtle ones? |
| Reasoning | Can you explain *why* you made each decision? |

We value clarity of thinking over completeness. An incomplete solution with clear reasoning beats a complete one with no explanation.

---

## Questions?

If anything is unclear, feel free to reach out. Good luck!

---

# Solution — Implementation Notes

This section documents the analytics layer built on top of the seed data: how to
run it locally, the project structure, and the reasoning behind the main
decisions.

## How to run locally

The one-time environment setup (Python, `dbt-duckdb`, `profiles.yml`) is covered
in **Setup** above. Once that is done, from the project root:

```bash
dbt deps      # install the dbt_utils package
dbt seed      # load raw_campaigns / raw_accounts / raw_events
dbt build     # run every model + every test, in dependency order
```

`dbt build` is the recommended entry point — it runs seeds, models and tests in
DAG order. To run things separately or selectively:

```bash
dbt run                                       # build all models
dbt test                                      # run all tests
dbt build --select staging                    # one layer
dbt build --select +mart_efficient_campaigns  # a mart and everything upstream
```

Inspect the results with any DuckDB client against the generated
`octane11_analytics_claude.duckdb` file, e.g.:

```bash
duckdb octane11_analytics_claude.duckdb
select * from main_marts.mart_top_channels_by_client;
```

Models are written to schemas `main_staging`, `main_intermediate` and
`main_marts` (the layer name is appended to DuckDB's default `main` schema).

> **Incremental model:** `int_events_enriched` is incremental. The first
> `dbt run` builds it in full; later runs only re-process a trailing window.
> Use `dbt run --full-refresh` to rebuild it from scratch.

## Part 3 — making the Parquet file available

`data/ad_spend.parquet` is exposed **as a dbt source**, not a seed. dbt-duckdb
can read external files directly, so the `media_agency` source declares an
`external_location` (under `config.meta`, the dbt 1.10+ location for `meta`):

```yaml
# models/staging/_sources.yml
- name: media_agency
  config:
    meta:
      external_location: "data/{name}.parquet"
  tables:
    - name: ad_spend
```

`{{ source('media_agency', 'ad_spend') }}` then resolves straight to the Parquet
file (`{name}` is replaced with the table name). **No extra step is needed** —
keep the file at `data/ad_spend.parquet` and run `dbt build`. `stg_ad_spend` is
the staging model on top of it.

## Project structure

```
models/
  staging/        cast + clean source data, one model per source table
  intermediate/   int_events_enriched — the single reusable event fact
  marts/          business-question outputs, one model per deliverable
```

| Layer | Model | Purpose |
|-------|-------|---------|
| staging | `stg_campaigns` | Reference model (provided). |
| staging | `stg_accounts` | Clean accounts; drops the NULL-key row. |
| staging | `stg_events` | Clean events; drops NULL key, de-duplicates `event_id`. |
| staging | `stg_ad_spend` | Staging over the external Parquet spend file. |
| intermediate | `int_events_enriched` | Events + campaign + account + funnel flags. Incremental. |
| marts | `mart_top_channels_by_client` | Q1 — top 3 channels per client by revenue. |
| marts | `mart_account_engagement_trend` | Q2 — monthly engagement per account + MoM change. |
| marts | `mart_efficient_campaigns` | Q3 — campaigns beating their channel on cost per meeting. |
| marts | `mart_top_accounts` | Part 2 — rewritten top-10-accounts model. |
| marts | `mart_campaign_spend_vs_budget` | Part 3 — actual spend vs. planned budget. |

`int_events_enriched` is the central design decision: the campaign/account joins
and the funnel definitions (`is_conversion`, `is_meeting_booked`) live there
once, and every mart selects from it (DRY). Q2 only needs the event grain;
Q1, Q3 and `mart_top_accounts` reuse the same enriched fact.

## Modeling decisions

**Q1 — Top channels per client.** "Last 90 days" is a rolling window. In
production it would be measured from `current_date`; because the seed data is
static, the window is anchored to the most recent `event_date` in the data so
the result stays reproducible for reviewers. The window length is a variable
(`revenue_window_days`, default 90). Ranking uses `ROW_NUMBER()` for a
deterministic top 3 (ties broken alphabetically by channel); channels with zero
influenced revenue in the window are not ranked.

**Q2 — Account engagement trend.** `prev_month_events` is taken from the
*previous calendar month* via a self-join, **not** `lag()`. `lag()` over only
the months an account was active would compare March to January when February
was silent — wrong. The self-join returns 0 for a silent previous month. Output
grain: one row per account per month-with-activity.

**Q3 — Efficient campaigns.** `cost_per_meeting = budget / meetings_booked`;
campaigns with no meetings are excluded via an `INNER JOIN` (division by zero /
explicitly out of scope). `avg_cost_per_meeting_for_channel` is the mean of the
per-campaign `cost_per_meeting` within a channel — the peer benchmark — computed
with a window function. Only campaigns strictly beating that benchmark are
returned, since the question asks for the *outperforming* campaigns.

**Part 2 — `mart_top_accounts`.** The full list of issues found in the original
model is documented as comments at the top of `models/marts/mart_top_accounts.sql`.
The headline bug: it returned a single global `LIMIT 10` instead of the top 10
*per client*, and never selected `client_id` — unusable, and a cross-tenant data
leak, on a multi-tenant platform.

## Data quality findings

Profiling the seeds surfaced several issues, which drove the staging logic and
the tests:

| Finding | Handling |
|---------|----------|
| 1 campaign row with a NULL `campaign_id` | Dropped in `stg_campaigns` (provided filter). |
| 1 account row with a NULL `account_id` | Dropped in `stg_accounts`. |
| 1 duplicated `event_id` in `raw_events` | De-duplicated in `stg_events` via `qualify row_number()`. |
| 1 event references a campaign missing from the source | Kept (LEFT JOIN) with a NULL channel; surfaced by a `relationships` test (`warn`). |
| 1 `click` event carries non-zero `revenue_influenced` (the README says clicks never do) | Surfaced by a `dbt_utils.expression_is_true` test on `stg_events` (`warn`). |

Tests that catch *known* anomalies are set to `severity: warn`, not `error`, so
they flag the issue on every run without blocking the build — the bug belongs
with the source team, not in a hard pipeline failure.

## Performance & efficiency

**Incremental model + late-arriving data.** `int_events_enriched` is incremental
(`delete+insert` on `event_id`). Engagement events can be ingested days after
they occur, so a naïve "rows newer than the current max" filter would silently
miss them. Instead each run re-processes a **trailing look-back window**
(`late_arriving_lookback_days`, default 7 days): it re-reads the last N days of
events, and `delete+insert` on `event_id` replaces any already-loaded rows while
inserting genuinely new late events. The variable should be set to cover the
worst-case ingestion lag. The downstream marts are small aggregates and rebuild
fully on every run.

**BigQuery optimizations.** The warehouse here is DuckDB, but the configs are
written for a production BigQuery deployment and activate automatically when
`target.type == 'bigquery'` (they resolve to `none` on DuckDB). They are applied
only to `int_events_enriched` — the large, event-grain fact — because that is
where they pay off:

- `partition_by` on `event_date` (monthly granularity): the incremental
  look-back filter and most analytical queries are time-bounded, so partition
  pruning cuts the bytes scanned.
- `cluster_by` on `client_id, channel`: the most common filter / group-by
  columns on a multi-tenant platform.

The marts are deliberately **not** partitioned or clustered: they are small,
pre-aggregated tables (tens to a couple of thousand rows) where those features
would add metadata overhead for no real scan saving. The principle: optimize the
large upstream fact, not the small downstream aggregates.

## Testing

Tests are curated for signal over coverage (≈25 tests in total):

- **Structural integrity** — `unique` + `not_null` on every primary key
  (`event_id`, `account_id`, `campaign_id`), and `dbt_utils.unique_combination_of_columns`
  on every mart grain.
- **Referential integrity** — `relationships` tests on the event foreign keys.
- **Domain rules** — `accepted_values` on `event_type` / `channel` / `status`,
  `dbt_utils.accepted_range` on `account_rank`, and the
  revenue-only-on-conversions expression test that catches the dirty `click` row.

Every model is documented in a YAML file (`_models.yml` per layer), with
table- and column-level descriptions that explain *why*, not just *what*.
