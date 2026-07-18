#!/usr/bin/env python3
"""Run load_bronze.sql against a DuckDB database.

Uses the duckdb Python library directly rather than shelling out to a
`duckdb` CLI binary, since `pip install duckdb` only ships the Python
library and CI has no CLI available.
"""

import argparse
from pathlib import Path

import duckdb

REPO_ROOT = Path(__file__).resolve().parent.parent
SQL_PATH = REPO_ROOT / "scripts" / "load_bronze.sql"
DEFAULT_XLSX_PATH = REPO_ROOT / "data" / "raw" / "Online_Retail.xlsx"
DEFAULT_DB_PATH = REPO_ROOT / "warehouse" / "retail.duckdb"


def load_bronze(xlsx_path: Path, db_path: Path) -> int:
    """Load `xlsx_path` into bronze.online_retail in `db_path`, exactly as-is.

    Parameterized (rather than hardcoded to the real dataset) so tests can
    point this same loading logic at a small fixture workbook.
    """
    db_path.parent.mkdir(parents=True, exist_ok=True)

    sql = SQL_PATH.read_text().format(xlsx_path=Path(xlsx_path).resolve().as_posix())
    con = duckdb.connect(str(db_path))
    try:
        con.execute(sql)
        return con.execute("SELECT count(*) FROM bronze.online_retail").fetchone()[0]
    finally:
        con.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xlsx-path", type=Path, default=DEFAULT_XLSX_PATH)
    parser.add_argument("--db-path", type=Path, default=DEFAULT_DB_PATH)
    args = parser.parse_args()

    row_count = load_bronze(args.xlsx_path, args.db_path)
    print(f"Loaded {row_count} rows into bronze.online_retail ({args.db_path})")


if __name__ == "__main__":
    main()
