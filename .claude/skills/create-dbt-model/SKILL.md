---
name: create-dbt-model
description: >-
  Create a new dbt model (Silver staging or Gold mart) following the
  conventions in stg_online_retail. Use when asked to add a staging model,
  mart, fact table, or dimension table under dbt/models/.
---

# Creating a dbt model

Look at `dbt/models/staging/stg_online_retail.sql` and
`dbt/models/staging/_staging.yml` first — that's the style to match.

## 1. Which layer?

| | Silver (`dbt/models/staging/`) | Gold (`dbt/models/marts/`) |
|---|---|---|
| Does what | Cleans/types/dedupes one raw source | Answers a business question |
| Reads from | `source('bronze', ...)` | `ref('stg_online_retail')` |
| Name | `stg_<source>` | `fct_<event>` or `dim_<entity>` |
| Materialized | view | table |

(Both defaults already set in `dbt_project.yml` — no config override needed.)

If it's not obvious which one the user wants, ask.

## 2. Write the SQL

- CTE style: `with source as (...), cleaned as (...) select ... from cleaned`
- State the grain in one sentence (e.g. "one row per customer").
- Every business rule gets a one-line comment explaining *why*, e.g. why a
  row counts as cancelled, or how returns net against revenue. If you can't
  write that comment, check the data before writing the SQL.
- Don't silently drop or filter rows to make a number look cleaner — only
  filter when it's an intended, explained rule.

## 3. Add a test

Every new model gets a test in the same change:
- Schema test in `_staging.yml` or `dbt/models/marts/_marts.yml` (copy
  `_staging.yml`'s format) — only add `not_null`/`unique` where the data
  actually supports it.
- For anything a schema test can't check (e.g. a row-count relationship
  between layers), add a singular test in `dbt/tests/`, modeled on
  `assert_stg_online_retail_row_count.sql`.

## 4. Run it

```bash
cd dbt
dbt run --profiles-dir . --select <model_name>
dbt test --profiles-dir . --select <model_name>
```

Don't call it done until both pass.

## 5. Before you say "done"

Skim `docs/ai_review_checklist.md`. The two questions that matter most:
- Does each filter match the real business rule, or just a pattern that
  usually matches it?
- Can you explain any row-count change from the layer below in one
  sentence?

## Scope

Stay inside the model's own folder, its schema file, and `dbt/tests/`. If
it seems to require changing another model or `dbt_project.yml`, stop and
ask first.
