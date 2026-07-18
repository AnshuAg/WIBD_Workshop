# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A live-built medallion architecture pipeline (Bronze → Silver → Gold) over the
UCI **Online Retail** dataset (541,909 transaction line items, one UK gift
retailer, Dec 2010–Dec 2011). This is a workshop repo: `scripts/`, `dbt/models/`,
`dbt/tests/`, and the Evidence dashboard start empty and are built during the
session, prompt by prompt, with a human reviewing every step. The dataset is
genuinely messy on purpose (guest checkouts, cancelled orders, refunds,
duplicate rows, non-product line items like postage/fees) — don't "fix" that
messiness in Bronze; it's the point.

## Commands

```bash
source .venv/bin/activate              # activate the pinned venv (dbt-core, dbt-duckdb, duckdb)
python scripts/load_bronze.py          # rebuild bronze.online_retail from data/raw/Online_Retail.xlsx
pytest tests/                          # run Python-level tests (e.g. the bronze layer contract)
cd dbt && dbt build --profiles-dir .   # run staging + mart models and tests
cd dbt && dbt test --profiles-dir . --select <model_name>   # run a single model's tests
cd dbt && dbt run --profiles-dir . --select <model_name>    # build a single model
```

`./setup.sh` (repo root) is the one-shot environment/scaffold script — idempotent,
safe to re-run, but it never touches anything built live in the session (Bronze
scripts, staging/mart models, tests, the dashboard page). Re-run it to restore
`dbt_project.yml`, `profiles.yml`, `.gitignore`, or the CI workflow if they get
clobbered; don't hand-edit those to "fix" a scaffold problem.

CI (`.github/workflows/ci.yml`) rebuilds Bronze from the raw xlsx and runs
`dbt build` on every push — it never reads a committed `.duckdb` file
(`warehouse/*.duckdb` is gitignored).

## Architecture

**Bronze** (`scripts/load_bronze.sql` + `scripts/load_bronze.py`) — loads
`data/raw/Online_Retail.xlsx` (sheet `Online Retail`) into `bronze.online_retail`
in `warehouse/retail.duckdb`, with every column as VARCHAR. This is a hard rule,
not a stylistic default:

- **Bronze never cleans, casts, filters, dedupes, or otherwise transforms data.**
  No judgment calls, nothing fixed — load exactly what's in the source file. If a
  value looks wrong (e.g. a float artifact like `2.5499999999999998` in
  `UnitPrice`), that's Silver's problem to interpret, not Bronze's to silently
  correct.
- `load_bronze.py` runs the `.sql` file through the `duckdb` Python API, not a
  `duckdb` CLI binary — `pip install duckdb` only ships the Python library, and
  CI has no CLI available. Any change to how Bronze loads must keep working
  through that API, not assume a CLI is present.
- The `spatial` extension's `st_read(..., open_options=['FIELD_TYPES=STRING'])`
  is what forces GDAL to skip type inference on the xlsx sheet; don't swap in a
  reader that infers INTEGER/DOUBLE/DATE types and casts back to text after the
  fact — that's a silent-coercion path even though the final column type is
  still VARCHAR.

**Silver** (`dbt/models/staging/`) — one clean, typed, deduplicated staging
model (`stg_online_retail`) reading from the `bronze` source. Business rules
that Bronze deliberately left alone (e.g. "what counts as a cancelled order")
get made explicit here, in SQL a reviewer can read and question — not implied by
a filter pattern that merely usually matches the rule.

**Gold** (`dbt/models/marts/`) — purpose-built marts answering a specific
business question (e.g. `fct_revenue`: "what did we actually sell?"), built on
Silver, materialized as tables.

**Naming conventions** (dbt models, `dbt/dbt_project.yml`):
- `stg_<source>` — Silver staging models, materialized as views.
- `fct_<subject>` — Gold fact tables (one row per business event/transaction),
  materialized as tables.
- `dim_<entity>` — Gold dimension tables (descriptive attributes of an entity),
  materialized as tables, if/when a dimension table is introduced.

Guardrail tests live in `dbt/tests/` (singular data tests, e.g.
`assert_fct_revenue_non_negative.sql`) alongside schema tests declared in each
layer's `.yml` files.

`dbt/models/staging/_sources.yml` declares the `bronze` source — it must live
under `model-paths` (`dbt/models/`), not at the `dbt/` project root, or dbt
won't see it.

**Dashboard** (`evidence/`) — Evidence.dev project reading `warehouse/retail.duckdb`
directly (`evidence/sources/retail/connection.yaml`), built on top of the Gold
mart(s).

## Working conventions

- **Show your reasoning before running a command.** State what you're about to
  do and why before executing it, especially for anything that writes to the
  warehouse, `dbt/`, or CI — this is a live-reviewed session, not a
  fire-and-forget pipeline.
- **Never modify files outside the current task's scope without asking first.**
  If a fix seems to require touching an unrelated model, script, or config,
  stop and ask rather than expanding scope silently.
- Read `docs/ai_review_checklist.md` before treating a filter, test, or fix as
  done — it's the standing review bar for this repo (rule vs. pattern, row
  counts across layers, whether a fix generalizes). `docs/FACILITATOR_RUNBOOK.md`
  has the full session runbook and known-good fallback SQL if needed.
- **Add a test by default whenever a new thing is added** — a new script,
  dbt model, mart, or dashboard query gets a test in the same change, not as a
  follow-up. dbt-layer tests (staging/marts) are schema tests or `dbt/tests/`
  singular tests, per the guardrail convention above. Anything outside dbt
  (e.g. `scripts/load_bronze.py`) gets a `pytest` test under `tests/`, run with
  `pytest tests/` (needs `pytest` from `requirements.txt`, in the venv).
- **Follow AAA (Arrange-Act-Assert) for unit tests**, with each section
  visible (a comment or blank-line break is enough) — Arrange sets up
  inputs/fixtures, Act performs the one thing under test, Assert checks the
  outcome. Don't fold Act into Assert (e.g. asserting directly on a query
  call) — keep the result captured in Act so Assert reads as a pure check.
  See `tests/test_load_bronze.py` for the pattern this repo follows.
- Before calling a test "done," actually run it and confirm it passes —
  don't take a plausible-looking test on faith.
