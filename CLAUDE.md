# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this is

A medallion architecture pipeline (Bronze → Silver → Gold) over the UCI
**Online Retail** dataset (541,909 transaction line items, one UK gift
retailer, Dec 2010–Dec 2011). `scripts/`, `dbt/models/`, `dbt/tests/`, and the
Evidence dashboard are built incrementally, prompt by prompt, with a human
reviewing every step. The dataset is genuinely messy on purpose (guest
checkouts, cancelled orders, refunds, duplicate rows, non-product line items
like postage/fees) — don't "fix" that messiness in Bronze; it's the point.

## Commands

```bash
source .venv/bin/activate              # activate the pinned venv
python scripts/load_bronze.py          # rebuild bronze.online_retail from data/raw/Online_Retail.xlsx
pytest tests/                          # run Python-level tests
cd dbt && dbt build --profiles-dir .   # run staging + mart models and tests
cd dbt && dbt test --profiles-dir . --select <model_name>   # run a single model's tests
cd dbt && dbt run --profiles-dir . --select <model_name>    # build a single model
```

`./setup.sh` (repo root) is the one-shot environment/scaffold script —
idempotent, safe to re-run, but it never touches anything built live (Bronze
scripts, staging/mart models, tests, the dashboard page). Re-run it to restore
`dbt_project.yml`, `profiles.yml`, `.gitignore`, or the CI workflow if they get
clobbered; don't hand-edit those to "fix" a scaffold problem.

`warehouse/*.duckdb` is gitignored — CI (and any fresh clone) rebuilds Bronze
from the raw xlsx rather than reading a committed binary.

## Architecture

**Bronze** (`scripts/load_bronze.sql` + `scripts/load_bronze.py`) — loads
`data/raw/Online_Retail.xlsx` (sheet `Online Retail`) into `bronze.online_retail`
in `warehouse/retail.duckdb` via DuckDB's `excel` extension (`read_xlsx`,
`all_varchar = true`), with every column loaded as VARCHAR. This is a hard
rule, not a stylistic default:

- **Bronze never cleans, casts, filters, dedupes, or otherwise transforms
  data.** No judgment calls — load exactly what's in the source file. If a
  value looks wrong (e.g. a float artifact like `2.5499999999999998` in
  `UnitPrice`, or dates coming through as raw Excel serial numbers), that's
  Silver's problem to interpret, not Bronze's to silently correct.
- `load_bronze.py` exposes a `load_bronze(xlsx_path, db_path)` function
  parameterized on both paths specifically so tests can point it at a small
  fixture workbook instead of the real dataset.

**Silver** (`dbt/models/staging/`) — one clean, typed, deduplicated staging
model (`stg_online_retail`) reading from the `bronze` source. Business rules
that Bronze deliberately left alone (e.g. "what counts as a cancelled order")
get made explicit here, in SQL a reviewer can read and question — not implied
by a filter pattern that merely usually matches the rule.

**Gold** (`dbt/models/marts/`) — purpose-built marts answering a specific
business question (e.g. `fct_revenue`: "what did we actually sell?"), built on
Silver, materialized as tables.

**Naming conventions** (dbt models, `dbt/dbt_project.yml`):
- `stg_<source>` — Silver staging models, materialized as views.
- `fct_<subject>` — Gold fact tables (one row per business event/transaction),
  materialized as tables.
- `dim_<entity>` — Gold dimension tables, materialized as tables, if/when one
  is introduced.

Guardrail tests live in `dbt/tests/` (singular data tests, e.g.
`assert_fct_revenue_non_negative.sql`) alongside schema tests declared in each
layer's `.yml` files.

## Testing policy

**Every time you add or change a script or model, add or update its tests in
the same change — don't treat tests as a follow-up.**

- Python scripts (`scripts/*.py`): a `tests/test_<name>.py` pytest module.
  Prefer testing against a small synthetic fixture (e.g. a fixture `.xlsx`
  built with `openpyxl`) over the real dataset, so tests stay fast and exercise
  the *contract* (e.g. "Bronze never drops or coerces rows") rather than
  today's specific numbers. Design scripts to be testable — parameterize
  file/db paths rather than hardcoding them — instead of skipping tests
  because the script "just runs end to end."
- dbt models (`dbt/models/**`): schema tests in the model's `.yml` (`not_null`,
  `unique`, `accepted_values`, relationships) plus a singular test in
  `dbt/tests/` for any business rule that a generic schema test can't express
  (e.g. a revenue mart never going negative).
- Before calling any change done: run `pytest tests/` and, for dbt changes,
  `dbt build --profiles-dir .` from `dbt/`. A model or script without a
  passing test alongside it is not finished.
- See `docs/ai_review_checklist.md` before merging any AI-generated model or
  test — it's written from real issues found in this pipeline (proxy filters
  that don't match the actual business rule, `not_null` tests that are
  stricter than reality, fixes that only patch the specific failing row).
