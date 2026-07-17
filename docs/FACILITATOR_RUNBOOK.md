# Facilitator Runbook — "Your Data Pipeline in Two Hours, Built with AI"

This is the step-by-step build guide for the live session. It's written against the
actual dataset (`Online_Retail.xlsx`, profiled below), with verified commands so
nothing has to be discovered live. Appendix C has known-good fallback SQL — if the
AI drifts mid-session or time runs short, paste it in and keep moving.

---

## 1. Run of show (120 min)

| # | Segment | Min | Cumulative |
|---|---|---|---|
| 1 | Welcome | 5 | 5 |
| 2 | The dataset | 10 | 15 |
| 3 | Bronze | 15 | 30 |
| 4 | Silver | 20 | 50 |
| 5 | Gold (mart + CI break + fix) | 30 | 80 |
| 6 | Tests & guardrails | 15 | 95 |
| 7 | How it all fits | 5 | 100 |
| 8 | Q&A + next steps | 10 | 110 |
| — | Buffer | 10 | 120 |

Gold is the anchor — it's where prompt engineering, DuckDB MCP, GitHub MCP, and
human-in-the-loop all show up in one continuous story. Bronze is now built live
too (§4), but keep its prompt short and its review quick — protect Gold's time
budget.

---

## 2. Pre-session setup (do this the night before, not live)

Run `./setup.sh` from the repo root first — it creates the folder scaffold, the
`.venv` with pinned dependencies, the CI workflow, and the Evidence project, and
copies `Online_Retail.xlsx` in from `~/Downloads` if it finds it there. It never
touches the files you build live (§4, §5, §6, §8). The steps below are what it
doesn't automate.

### 2.1 Software

- VS Code + Claude Code extension, signed in
- Python 3.11+, with dependencies from the repo's `requirements.txt` installed (`pip install -r requirements.txt` — pins `dbt-core==1.11.12`, `dbt-duckdb==1.10.1`, `duckdb==1.5.4`)
- Node.js 18+ (for Evidence.dev)
- GitHub CLI (`gh`), authenticated
- A GitHub personal access token (fine-grained, scoped to just this repo: Contents read/write, Actions read, Pull requests read/write) for the GitHub MCP server

### 2.2 Repo scaffold

```
WIBD_Workshop/
├── data/raw/Online_Retail.xlsx
├── warehouse/                      # gitignored — retail.duckdb lives here
├── scripts/         (load_bronze.sql + load_bronze.py — built live, §4)
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── models/
│   │   ├── staging/  (stg_online_retail.sql + _staging.yml + _sources.yml)
│   │   └── marts/    (fct_revenue.sql + _marts.yml)
│   └── tests/assert_fct_revenue_non_negative.sql
├── evidence/                       # Evidence.dev project
├── .github/workflows/dbt_ci.yml
├── requirements.txt
├── setup.sh                        # run once: scaffolds + installs everything above
└── docs/ (this file + ai_review_checklist.md)
```

Run `./setup.sh` to generate everything above except the files you build live
(§4 bronze load, §5 staging model, §6 mart + test, §8 dashboard page) — it's
idempotent and safe to re-run.

Create the GitHub repo and push this scaffold (empty `scripts/` and models are
fine — they get filled in live) before the session starts. Enable Actions on the
repo.

`warehouse/*.duckdb` should be in `.gitignore` — CI rebuilds bronze from
`data/raw/Online_Retail.xlsx` on every run (see §6.3), so the binary DuckDB file
never needs to be committed.

### 2.3 MCP servers

**DuckDB MCP** (queries the live warehouse file so the agent can inspect real data
mid-conversation):

```bash
claude mcp add duckdb uvx mcp-server-duckdb -- --db-path warehouse/retail.duckdb
```

**GitHub MCP** (reads workflow logs, PR state; official server, HTTP transport —
no Docker needed):

```bash
claude mcp add -s user --transport http github https://api.githubcopilot.com/mcp \
  -H "Authorization: Bearer <YOUR_FINE_GRAINED_PAT>"
```

Verify both with `claude mcp list` before the room fills up.

### 2.4 Dry run + recovery checkpoints

Run the entire pipeline solo, start to finish, at least once. While doing so, tag
a git commit at the end of each stage:

```bash
git tag ckpt-bronze
git tag ckpt-silver
git tag ckpt-gold-broken   # the commit that deliberately fails CI
git tag ckpt-gold-fixed
git tag ckpt-tests
```

If live AI output goes sideways and you're burning time, `git checkout <tag> --
<path>` gets you back on schedule without breaking the narrative — you can say
"here's one I made earlier" and keep going.

---

## 3. The dataset — talking points (Segment 2)

This is the real **UCI Online Retail** dataset: one UK-based online gift retailer,
**541,909 rows, 8 columns, Dec 2010 – Dec 2011**. Don't just describe messiness in
the abstract — show these specific numbers live (`SELECT` them via DuckDB MCP once
Bronze is loaded, or show this table now):

| Issue | Scale | Why it matters |
|---|---|---|
| Missing `CustomerID` | 135,080 rows (~25%) | Guest/unlinked checkouts — not an error, a real business case |
| Missing `Description` | 1,454 rows | Correlated with `UnitPrice = 0` — junk/adjustment rows |
| Cancelled orders (`InvoiceNo` starts `C`) | 9,288 rows | Returns — must be excluded from revenue, but that's *not* the only cancellation pattern (see Gold) |
| Negative/zero `Quantity` | 10,624 rows | Returns and stock adjustments |
| Negative/zero `UnitPrice` | 2,517 rows | Includes two `-£11,062.06` "Adjust bad debt" entries — the seeded CI break lives here |
| Exact duplicate rows | 5,268 rows | Straight re-scans/re-exports, not real repeat purchases |
| Non-merchandise `StockCode`s | 37 codes (`POST`, `D`, `M`, `BANK CHARGES`, `DOT`, `S`, `AMAZONFEE`, `gift_0001_*`, `DCGS*`, `PADS`…) | Postage, fees, discounts, manual adjustments mixed into transaction data — not products |
| Case-inconsistent `StockCode` | e.g. `15056BL` vs `15056bl` | Same product, two identities — a join/dedup trap |
| Inconsistent `Description` per code | 650 stock codes have >1 description | Some are genuinely different variants; some are warehouse notes like `"wrongly coded-23343"`, `"found"` typed straight into a product-name field |
| Non-standard country names | `EIRE`, `RSA`, `Unspecified`, `European Community` | Breaks any join to a standard ISO country dimension |
| `CustomerID` stored as float | e.g. `17850.0` | Classic Excel type-coercion artifact |

**Medallion architecture, in one breath:** Bronze = load it exactly as it is, no
judgment calls. Silver = one clean, typed, deduplicated, well-named table per
source, with business rules like "what counts as cancelled" made explicit. Gold =
purpose-built, aggregated tables that answer a specific question (here: "what did
we actually sell?"). Each layer only trusts the layer below it — that's what makes
the pipeline debuggable when something breaks downstream (which it will, in
Segment 5, on purpose).

---

## 4. Bronze (Segment 3) — built live

**Principle to state out loud:** load everything as text (`all_varchar=true`).
Don't let the loader silently coerce `CustomerID` to a float or reformat dates —
that coercion is itself a data-quality decision, and it belongs in Silver where
it's visible and intentional, not buried in an ingestion step nobody reviews.

`scripts/` starts empty (just a `.gitkeep`) — this is a live-build segment now,
not a canned script. Type this to the agent, live, roughly verbatim:

> "Write a DuckDB script that loads `data/raw/Online_Retail.xlsx` (sheet 'Online
> Retail') into a `bronze.online_retail` table, with every column loaded as text
> so nothing gets silently coerced. Save it as `scripts/load_bronze.sql`. Also
> write `scripts/load_bronze.py` that runs that SQL file against
> `warehouse/retail.duckdb` — CI needs to call this without a `duckdb` CLI
> binary, since `pip install duckdb` only ships the Python library."

Keep this one short and mechanical-feeling on purpose (§1) — it's a warm-up
prompt, not where the room's attention should linger. Known-good fallback if the
AI drifts (verbatim in Appendix C too):

```sql
INSTALL excel; LOAD excel;

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE OR REPLACE TABLE bronze.online_retail AS
SELECT *
FROM read_xlsx(
    'data/raw/Online_Retail.xlsx',
    sheet = 'Online Retail',
    all_varchar = true
);
```

```python
import duckdb

with open("scripts/load_bronze.sql") as f:
    sql = f.read()

con = duckdb.connect("warehouse/retail.duckdb")
con.execute(sql)
con.close()
```

This SQL is reused verbatim in CI (§6.3). Then have the agent (via DuckDB MCP)
sanity-check the load live:

```sql
SELECT count(*) FROM bronze.online_retail;                 -- 541909
SELECT * FROM bronze.online_retail LIMIT 5;                 -- everything is VARCHAR
SELECT count(*) FROM bronze.online_retail WHERE CustomerID IS NULL;  -- 135080
```

This is the "why you resist the urge to clean it here" beat: point out that
`Quantity` and `UnitPrice` are now strings, `InvoiceDate` is a string — nothing
has been fixed, and that's correct. Bronze's only job is "did we lose any rows or
columns getting the file into the warehouse." Nothing else.

Once the count checks out, commit `scripts/load_bronze.sql` and
`scripts/load_bronze.py` and treat them as locked — this is the checkpoint §7
refers to when it says the agent can edit `dbt/models/**` but not Bronze once
verified.

---

## 5. Silver (Segment 4) — the one-sentence prompt

This is the first big "prompt engineering" beat. Type this to the agent, live,
roughly verbatim:

> "Write a dbt staging model `stg_online_retail` from the `bronze.online_retail`
> source. Cast each column to its proper type, trim whitespace, and add an
> `is_cancelled` flag for cancelled orders. This feeds a revenue mart, so make
> the grain and column names clean enough to build on."

Let it run. Then **narrate the review**, not just the output — this is the
educational payload of the segment.

**What a good draft typically gets right:**
- Casts `CustomerID` from `'17850.0'`-shaped strings to an integer
- Parses `InvoiceDate` to a real timestamp
- Trims `Description`/`StockCode` whitespace
- Flags `is_cancelled` via `starts_with(invoice_no, 'C')`

**What it typically misses — and why that's worth stopping on:**
- The `'C'`-prefix cancellation flag doesn't catch the two `A`-prefixed
  `"Adjust bad debt"` rows (`A563186`, `A563187`) — a plausible-looking rule that's
  quietly incomplete. **Leave this uncaught here on purpose** — it's what breaks
  the build in Gold, and finding it live via CI + GitHub MCP is a better lesson
  than fixing it now.
- It rarely knows to treat `POST`, `DOT`, `M`, `BANK CHARGES`, `gift_0001_*`,
  `DCGS*` as non-merchandise line items unless told — ask "is every `StockCode`
  here an actual product?" and let it look via DuckDB MCP.
- It won't normalize `StockCode` casing (`15056BL` vs `15056bl`) unless asked —
  a good "what would you check next" audience question.
- Watch whether it drops the 1,454 null-`Description` rows outright — some of
  those are legitimate transactions with real quantities/prices; blanket-dropping
  them silently loses revenue.

This maps directly to the checklist in §10 — a confident, well-formatted model
that passes review at a glance is exactly what the checklist exists to catch.

---

## 6. Gold (Segment 5) — the revenue mart, the break, the fix

This segment carries the session. Budget it accordingly: ~10 min build the mart,
~5 min push and watch it fail, ~10 min diagnose and fix via GitHub MCP + DuckDB
MCP, ~5 min green build + dashboard data ready.

### 6.1 Build `fct_revenue`

Prompt:

> "Build a dbt mart `fct_revenue` from `stg_online_retail`: one row per
> transaction line, excluding cancelled orders, with a `line_amount` column
> (`quantity * unit_price`) and a `invoice_month` for later aggregation."

A reasonable model the agent will likely produce:

```sql
select
    invoice_no,
    stock_code,
    description,
    invoice_date,
    date_trunc('month', invoice_date) as invoice_month,
    country,
    customer_id,
    quantity,
    unit_price,
    quantity * unit_price as line_amount
from {{ ref('stg_online_retail') }}
where not is_cancelled
  and quantity > 0
```

This is **the seeded bug**: `is_cancelled` only catches `InvoiceNo LIKE 'C%'`.
The two `"Adjust bad debt"` rows (`unit_price = -11062.06`, `quantity = 1`,
`invoice_no` starting with `A`) sail through, and `line_amount` for those two rows
is `-11062.06` — a revenue mart with negative "sales."

### 6.2 Add the test that catches it

```sql
-- dbt/tests/assert_fct_revenue_non_negative.sql
select *
from {{ ref('fct_revenue') }}
where line_amount < 0
```

A singular test, not a package-dependent generic one — keeps the CI setup free of
extra dependencies and the failure message dead simple to read in the Actions log.

### 6.3 Push it, watch it break

```yaml
# .github/workflows/dbt_ci.yml
name: dbt CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install -r requirements.txt
      - name: Build bronze
        run: python scripts/load_bronze.py
      - name: dbt build
        working-directory: dbt
        run: dbt build --profiles-dir .
```

`dbt build` runs models and tests in one DAG pass — `assert_fct_revenue_non_negative`
fails with **2 rows returned**, and the Action goes red. This is fully
deterministic — it fails the same way every run, on real data, not a fabricated
error.

### 6.4 Diagnose via GitHub MCP, fix via DuckDB MCP

Prompt, live:

> "The Actions run on the last push failed. Check the workflow logs, tell me what
> broke, and look at the actual data to figure out why before proposing a fix."

Expected flow: the agent reads the failed run log via GitHub MCP, sees the failing
test and "2 rows", then queries DuckDB directly (`select * from fct_revenue where
line_amount < 0`) to find the two bad-debt rows, and notices they don't start with
`C`. The fix that actually generalizes — call this out if the agent proposes
special-casing `stock_code = 'B'` instead:

```sql
where not is_cancelled
  and quantity > 0
  and unit_price > 0   -- the real rule: a completed sale has a positive price
```

**Talking point:** the narrow fix (exclude that one `StockCode`) would pass CI
today and silently break the next time a similar adjustment lands with a
different code. The general fix encodes the actual business rule. This is the
difference the human-in-the-loop is there to catch — a fix that makes the test
green isn't automatically the right fix.

Push the fix, watch Actions go green, move on.

---

## 7. Tests & guardrails (Segment 6)

Frame this as "what boundaries did we already put around the agent, and what else
should we add before this ships." Boundaries already in place by this point:
- The agent can edit `dbt/models/**` but Bronze (§4) was locked once verified —
  state this explicitly to the room as a guardrail, not just a workflow detail.
- CI must pass before anything is considered done — the test in §6.2 is the
  guardrail that caught a real bug, not a hypothetical one.

Add 2–3 more, live, with a prompt like:

> "Add dbt schema tests to `stg_online_retail` and `fct_revenue`: not-null checks
> on the columns that should never be missing, and a check that we haven't
> silently dropped an unexpected fraction of rows between staging and the mart."

Good tests to land here:
- `not_null` on `invoice_no`, `stock_code`, `invoice_date` in staging (never null
  in the raw data — a real not-null, not an assumption)
- `not_null` is *wrong* on `customer_id` — call this out explicitly if the agent
  suggests it: 25% of rows are legitimate guest checkouts, and a not-null test
  here would immediately break CI on correct data. This is a good live
  contrast to §6's real bug: a test that "looks safe" but encodes a false
  assumption is exactly as dangerous as a filter that's too narrow.
- A row-count guardrail between `stg_online_retail` and `fct_revenue` (e.g. mart
  row count shouldn't drop by more than some threshold vs. staging) — catches
  silent over-filtering the same class of bug as §6, one layer up.

If time allows: an `is_product` flag distinguishing real `StockCode`s from the 37
non-merchandise codes (`POST`, `DOT`, `BANK CHARGES`, gift cards, …) is a good
"stretch" prompt to leave the room with, since it directly affects "top products"
on the dashboard.

---

## 8. Evidence dashboard (part of Segment 6 / start of 7)

```
evidence/
├── package.json         # npm install @evidence-dev/duckdb
├── sources/retail/connection.yaml
└── pages/index.md
```

`sources/retail/connection.yaml`:

```yaml
name: retail
type: duckdb
options:
  filename: ../../warehouse/retail.duckdb
```

`pages/index.md`:

````markdown
# Retail Revenue

```sql revenue_by_month
select invoice_month, sum(line_amount) as revenue
from fct_revenue
group by 1 order by 1
```

<LineChart data={revenue_by_month} x=invoice_month y=revenue title="Revenue by month" />

```sql top_products
select description, sum(line_amount) as revenue
from fct_revenue
group by 1 order by 2 desc limit 10
```

<BarChart data={top_products} x=description y=revenue swapXY=true title="Top 10 products" />

```sql revenue_by_country
select country, sum(line_amount) as revenue
from fct_revenue
group by 1 order by 2 desc limit 10
```

<BarChart data={revenue_by_country} x=country y=revenue swapXY=true title="Top 10 countries" />
````

`npm run dev` inside `evidence/` and this is on screen in under a minute — the
payoff moment after the CI fix.

---

## 9. How it all fits (Segment 7)

Recap as a system, not a sequence of tricks: scope (agent could edit models and
tests, not touch Bronze once verified), tools (DuckDB MCP for live data, GitHub
MCP for CI state), and the two moments judgment mattered — rejecting the
`customer_id not_null` test, and rejecting the narrow `stock_code = 'B'` fix in
favor of the general one. Both were plausible, well-formatted, and wrong (or
incomplete) — that's the checklist in §10, applied twice already without calling
it that.

---

## 10. Q&A + handout

Hand out `docs/ai_review_checklist.md` (one page, see companion file) and the
repo link. Close on: the two "gotchas" in this session (§5's incomplete
cancellation flag, §7's tempting-but-wrong not-null test) were both real,
naturally occurring in this dataset — not scripted traps. That's worth saying
directly: the point isn't "AI makes mistakes," it's "here's what reviewing its
output actually looks like in practice."

---

## Appendix A: Prompt library (exact prompts to type live)

1. **Bronze:** "Write a DuckDB script that loads `data/raw/Online_Retail.xlsx`
   (sheet 'Online Retail') into a `bronze.online_retail` table, with every
   column loaded as text so nothing gets silently coerced. Save it as
   `scripts/load_bronze.sql`. Also write `scripts/load_bronze.py` that runs
   that SQL file against `warehouse/retail.duckdb` — CI needs to call this
   without a `duckdb` CLI binary, since `pip install duckdb` only ships the
   Python library."
2. **Silver:** "Write a dbt staging model `stg_online_retail` from the
   `bronze.online_retail` source. Cast each column to its proper type, trim
   whitespace, and add an `is_cancelled` flag for cancelled orders. This feeds a
   revenue mart, so make the grain and column names clean enough to build on."
3. **Gold — build:** "Build a dbt mart `fct_revenue` from `stg_online_retail`:
   one row per transaction line, excluding cancelled orders, with a
   `line_amount` column (`quantity * unit_price`) and an `invoice_month` for
   later aggregation."
4. **Gold — diagnose:** "The Actions run on the last push failed. Check the
   workflow logs, tell me what broke, and look at the actual data to figure out
   why before proposing a fix."
5. **Guardrails:** "Add dbt schema tests to `stg_online_retail` and
   `fct_revenue`: not-null checks on the columns that should never be missing,
   and a check that we haven't silently dropped an unexpected fraction of rows
   between staging and the mart."
6. **Rescue, if #3 special-cases instead of generalizing:** "That fix passes CI
   today — would it still catch the same class of problem if the next bad
   adjustment used a different stock code or invoice prefix?"

## Appendix B: Live-demo risk register

| Risk | Mitigation |
|---|---|
| AI output is wrong/slow live | Paste from Appendix C, keep narrating as if reviewing a PR |
| Wi-Fi/GitHub Actions is slow or down | Have a second browser tab already showing a prior green/red run from the dry run; narrate over screenshots if needed |
| MCP server disconnects mid-session | `claude mcp list` to check status; worst case, run the equivalent SQL/`gh` CLI commands directly and narrate what MCP would have shown |
| Running long | Cut the "stretch" `is_product` guardrail (§7) first, then trim Q&A — never cut the Gold break/fix, it's the spine of the session |
| Someone asks about dimensional modeling depth | Acknowledge it's out of scope per the agenda, point to a follow-up resource, move on |

## Appendix C: Known-good fallback SQL

`scripts/load_bronze.sql`:

```sql
INSTALL excel; LOAD excel;

CREATE SCHEMA IF NOT EXISTS bronze;

CREATE OR REPLACE TABLE bronze.online_retail AS
SELECT *
FROM read_xlsx(
    'data/raw/Online_Retail.xlsx',
    sheet = 'Online Retail',
    all_varchar = true
);
```

`scripts/load_bronze.py`:

```python
import duckdb

with open("scripts/load_bronze.sql") as f:
    sql = f.read()

con = duckdb.connect("warehouse/retail.duckdb")
con.execute(sql)
con.close()
```

`dbt/models/staging/stg_online_retail.sql`:

```sql
with source as (
    select * from {{ source('bronze', 'online_retail') }}
),

cleaned as (
    select
        trim(InvoiceNo)                                     as invoice_no,
        starts_with(trim(InvoiceNo), 'C')                   as is_cancelled,
        upper(trim(StockCode))                              as stock_code,
        nullif(trim(Description), '')                       as description,
        try_cast(Quantity as integer)                       as quantity,
        try_cast(InvoiceDate as timestamp)                  as invoice_date,
        try_cast(UnitPrice as decimal(10,2))                as unit_price,
        try_cast(try_cast(nullif(CustomerID, '') as double) as integer) as customer_id,
        trim(Country)                                       as country
    from source
)

select * from cleaned
```

`dbt/models/marts/fct_revenue.sql` (buggy version, for the deliberate CI break):

```sql
select
    invoice_no,
    stock_code,
    description,
    invoice_date,
    date_trunc('month', invoice_date) as invoice_month,
    country,
    customer_id,
    quantity,
    unit_price,
    quantity * unit_price as line_amount
from {{ ref('stg_online_retail') }}
where not is_cancelled
  and quantity > 0
```

`dbt/models/marts/fct_revenue.sql` (fixed version, after §6.4):

```sql
select
    invoice_no,
    stock_code,
    description,
    invoice_date,
    date_trunc('month', invoice_date) as invoice_month,
    country,
    customer_id,
    quantity,
    unit_price,
    quantity * unit_price as line_amount
from {{ ref('stg_online_retail') }}
where not is_cancelled
  and quantity > 0
  and unit_price > 0
```

`dbt/profiles.yml`:

```yaml
retail:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: '../warehouse/retail.duckdb'
      schema: main
      threads: 4
```

`dbt/models/staging/_sources.yml` (source YAML must live under `model-paths` —
`dbt/sources.yml` at the project root would be silently ignored):

```yaml
version: 2
sources:
  - name: bronze
    schema: bronze
    tables:
      - name: online_retail
```
