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
