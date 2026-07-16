# WIBD Workshop — Your Data Pipeline in Two Hours, Built with AI

A hands-on session where we build a real data pipeline live, end to end, with an
AI coding assistant (Claude Code) doing the typing and a human reviewing every
step. By the end you'll have a working dbt + DuckDB pipeline, a CI check that
catches a real data bug, and a dashboard on top of it — and a feel for what
reviewing AI-generated data models actually looks like in practice.

## The dataset

The real **UCI Online Retail** dataset: one UK-based online gift retailer,
541,909 transaction line items, Dec 2010 – Dec 2011. It's genuinely messy —
guest checkouts, cancelled orders, refunds, duplicate rows, non-product line
items (postage, fees) — which is exactly why it's useful for a workshop about
reviewing AI output, not a scripted stand-in for messiness.

## What we build, live

Medallion architecture, one layer per segment:

| Layer | What it does |
|---|---|
| **Bronze** | Load the raw file into DuckDB exactly as-is — no judgment calls, nothing fixed |
| **Silver** | One clean, typed, deduplicated staging model, with business rules (like "what counts as cancelled") made explicit |
| **Gold** | A purpose-built revenue mart that answers a specific question: "what did we actually sell?" |

Plus: a dbt test that catches a real seeded bug via CI, a couple of guardrail
tests, and an Evidence.dev dashboard on top of the mart.

Nothing here is pre-solved — `scripts/`, `dbt/models/`, `dbt/tests/`, and the
dashboard page all start empty. Every prompt, every review, and every fix
happens live in the session.

## Getting set up

```bash
./setup.sh
```

This creates the folder scaffold, a `.venv` with pinned dependencies
(`dbt-core`, `dbt-duckdb`, `duckdb` — see `requirements.txt`), the CI workflow,
and an Evidence.dev project. It's idempotent and safe to re-run. It never
touches anything you build live in the session.

You'll need: Python 3.11+, Node.js 18+ (for the dashboard), and VS Code with
the Claude Code extension.

## Repo layout

```
WIBD_Workshop/
├── data/raw/           # the source Excel file
├── warehouse/          # gitignored — the DuckDB file lives here
├── scripts/            # Bronze load scripts — built live
├── dbt/
│   ├── models/staging/ # Silver — built live
│   ├── models/marts/   # Gold — built live
│   └── tests/          # guardrail tests — built live
├── evidence/           # dashboard — built live
├── .github/workflows/  # CI: rebuilds Bronze + runs dbt build on every push
└── docs/               # facilitator runbook + AI-review checklist
```


