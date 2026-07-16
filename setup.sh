#!/usr/bin/env bash
# One-shot environment setup for "Your Data Pipeline in Two Hours — Built with AI".
# Safe to re-run: only writes infra files, never touches the models you build live
# in the session (see docs/FACILITATOR_RUNBOOK.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "==> Checking prerequisites"
command -v python3 >/dev/null || { echo "!! python3 not found — required"; exit 1; }
command -v node    >/dev/null || echo "!! node not found — needed for the Evidence dashboard (§8)"
command -v npm     >/dev/null || echo "!! npm not found — needed for the Evidence dashboard (§8)"
command -v gh      >/dev/null || echo "!! GitHub CLI (gh) not found — needed for repo/Actions setup (§2.2)"
command -v claude  >/dev/null || echo "!! claude CLI not found — needed for MCP servers (§2.3)"

echo "==> Creating folder scaffold"
mkdir -p data/raw
mkdir -p warehouse
mkdir -p scripts
mkdir -p dbt/models/staging
mkdir -p dbt/models/marts
mkdir -p dbt/tests
mkdir -p .github/workflows
touch warehouse/.gitkeep scripts/.gitkeep dbt/models/staging/.gitkeep dbt/models/marts/.gitkeep dbt/tests/.gitkeep

echo "==> Writing .gitignore"
cat > .gitignore <<'EOF'
.venv/
__pycache__/
warehouse/*.duckdb
dbt/target/
dbt/logs/
dbt/dbt_packages/
node_modules/
evidence/.evidence/
.DS_Store
EOF

echo "==> Writing dbt project files"
cat > dbt/dbt_project.yml <<'EOF'
name: 'retail'
version: '1.0.0'
config-version: 2

profile: 'retail'

model-paths: ["models"]
test-paths: ["tests"]

target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

models:
  retail:
    staging:
      +materialized: view
    marts:
      +materialized: table
EOF

cat > dbt/profiles.yml <<'EOF'
retail:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: '../warehouse/retail.duckdb'
      schema: main
      threads: 4
EOF

# NOTE: source YAML must live under model-paths (models/) or dbt won't see it —
# not at the dbt/ project root.
cat > dbt/models/staging/_sources.yml <<'EOF'
version: 2
sources:
  - name: bronze
    schema: bronze
    tables:
      - name: online_retail
EOF

echo "==> Writing .github/workflows/dbt_ci.yml (Gold, §6.3)"
cat > .github/workflows/dbt_ci.yml <<'EOF'
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
EOF

echo "==> Locating the raw dataset"
if [ -f data/raw/Online_Retail.xlsx ]; then
  echo "    already present at data/raw/Online_Retail.xlsx"
elif [ -f "$HOME/Downloads/Online_Retail.xlsx" ]; then
  cp "$HOME/Downloads/Online_Retail.xlsx" data/raw/Online_Retail.xlsx
  echo "    copied from ~/Downloads/Online_Retail.xlsx"
else
  echo "    !! not found — place Online_Retail.xlsx at data/raw/ before Bronze (§4)"
fi

echo "==> Python virtual environment (.venv)"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt -q
echo "    installed: $(pip show dbt-core | grep Version), duckdb $(pip show duckdb | grep Version)"

echo "==> Evidence.dev scaffold (§8)"
if [ -d evidence ]; then
  echo "    evidence/ already exists — skipping scaffold, leaving your dashboard alone"
elif command -v npx >/dev/null; then
  npx --yes degit evidence-dev/template evidence
  (cd evidence && npm install --silent && npm install --silent @evidence-dev/duckdb)
  mkdir -p evidence/sources/retail
  cat > evidence/sources/retail/connection.yaml <<'EOF'
name: retail
type: duckdb
options:
  filename: ../../warehouse/retail.duckdb
EOF
else
  echo "    npx not found — install Node.js, then: npx degit evidence-dev/template evidence"
fi

cat <<'EOF'

==> Scaffold ready. Activate the venv in new shells with: source .venv/bin/activate

Still manual (see docs/FACILITATOR_RUNBOOK.md §2.2-2.3):
  1. Create the GitHub repo, push this scaffold, enable Actions
  2. claude mcp add duckdb uvx mcp-server-duckdb -- --db-path warehouse/retail.duckdb
  3. claude mcp add -s user --transport http github https://api.githubcopilot.com/mcp \
       -H "Authorization: Bearer <YOUR_FINE_GRAINED_PAT>"

Left empty on purpose — build these live in the session:
  scripts/load_bronze.sql, load_bronze.py        (§4 Bronze)
  dbt/models/staging/stg_online_retail.sql       (§5 Silver)
  dbt/models/marts/fct_revenue.sql               (§6 Gold)
  dbt/tests/assert_fct_revenue_non_negative.sql  (§6.2)
  evidence/pages/index.md                        (§8 dashboard)
EOF
