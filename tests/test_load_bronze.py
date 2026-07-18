"""Bronze layer tests.

Bronze's only contract (see CLAUDE.md) is "load the raw file exactly as it
is" — no casting, filtering, deduping, or other judgment calls. These tests
check that contract against a small synthetic fixture workbook, not the real
541,909-row dataset — the logic under test should hold for any workbook
shaped like the source, not just today's data.
"""

import importlib.util
import sys
from pathlib import Path

import duckdb
import openpyxl

REPO_ROOT = Path(__file__).resolve().parent.parent

# scripts/load_bronze.py is a standalone script, not an installed package —
# load it by path so its `load_bronze()` function is directly callable/testable.
_spec = importlib.util.spec_from_file_location(
    "load_bronze", REPO_ROOT / "scripts" / "load_bronze.py"
)
load_bronze_module = importlib.util.module_from_spec(_spec)
sys.modules["load_bronze"] = load_bronze_module
_spec.loader.exec_module(load_bronze_module)
load_bronze = load_bronze_module.load_bronze

COLUMNS = [
    "InvoiceNo",
    "StockCode",
    "Description",
    "Quantity",
    "InvoiceDate",
    "UnitPrice",
    "CustomerID",
    "Country",
]


def _write_fixture_workbook(path: Path, rows: list) -> None:
    workbook = openpyxl.Workbook()
    sheet = workbook.active
    sheet.title = "Online Retail"
    sheet.append(COLUMNS)
    for row in rows:
        sheet.append(row)
    workbook.save(path)


def test_loads_every_row_from_the_source_workbook(tmp_path):
    # Arrange: a fixture workbook with a known number of data rows.
    xlsx_path = tmp_path / "fixture.xlsx"
    fixture_rows = [
        ["536365", "85123A", "WHITE HANGING HEART T-LIGHT HOLDER", "6", "2010/12/01 08:26:00", "2.55", "17850", "United Kingdom"],
        ["536366", "22633", "HAND WARMER UNION JACK", "6", "2010/12/01 08:28:00", "1.85", "17850", "United Kingdom"],
        ["536367", "84879", "ASSORTED COLOUR BIRD ORNAMENT", "32", "2010/12/01 08:34:00", "1.69", "13047", "United Kingdom"],
    ]
    _write_fixture_workbook(xlsx_path, fixture_rows)
    db_path = tmp_path / "warehouse.duckdb"

    # Act
    row_count = load_bronze(xlsx_path, db_path)

    # Assert: every row in the source workbook made it into bronze — no filtering.
    assert row_count == len(fixture_rows)


def test_every_column_is_loaded_as_varchar(tmp_path):
    # Arrange
    xlsx_path = tmp_path / "fixture.xlsx"
    _write_fixture_workbook(
        xlsx_path,
        [["536365", "85123A", "WHITE HANGING HEART T-LIGHT HOLDER", "6", "2010/12/01 08:26:00", "2.55", "17850", "United Kingdom"]],
    )
    db_path = tmp_path / "warehouse.duckdb"
    load_bronze(xlsx_path, db_path)

    # Act
    con = duckdb.connect(str(db_path), read_only=True)
    try:
        schema = con.execute("DESCRIBE bronze.online_retail").fetchall()
    finally:
        con.close()
    actual_columns = [row[0] for row in schema]
    actual_types = {row[0]: row[1] for row in schema}

    # Assert
    assert actual_columns == COLUMNS
    assert all(dtype == "VARCHAR" for dtype in actual_types.values())


def test_does_not_coerce_or_reformat_values(tmp_path):
    # Arrange: values that a type-inferring loader would silently mangle —
    # a leading-zero code (int cast drops the zero) and a float artifact
    # (numeric round-trip loses precision).
    xlsx_path = tmp_path / "fixture.xlsx"
    _write_fixture_workbook(
        xlsx_path,
        [["536365", "007", "TEST PRODUCT", "6", "2010/12/01 08:26:00", "9.9499999999999993", "17850", "United Kingdom"]],
    )
    db_path = tmp_path / "warehouse.duckdb"
    load_bronze(xlsx_path, db_path)

    # Act
    con = duckdb.connect(str(db_path), read_only=True)
    try:
        stock_code, unit_price = con.execute(
            "SELECT StockCode, UnitPrice FROM bronze.online_retail"
        ).fetchone()
    finally:
        con.close()

    # Assert: preserved as literal text, not cast to int/float and back.
    assert stock_code == "007"
    assert unit_price == "9.9499999999999993"


def test_does_not_drop_rows_with_missing_values(tmp_path):
    # Arrange: a guest-checkout-shaped row with no CustomerID.
    xlsx_path = tmp_path / "fixture.xlsx"
    _write_fixture_workbook(
        xlsx_path,
        [["536365", "85123A", "WHITE HANGING HEART T-LIGHT HOLDER", "6", "2010/12/01 08:26:00", "2.55", None, "United Kingdom"]],
    )
    db_path = tmp_path / "warehouse.duckdb"
    load_bronze(xlsx_path, db_path)

    # Act
    con = duckdb.connect(str(db_path), read_only=True)
    try:
        row_count, null_count = con.execute(
            "SELECT count(*), count(*) FILTER (WHERE CustomerID IS NULL) FROM bronze.online_retail"
        ).fetchone()
    finally:
        con.close()

    # Assert: the row is kept, with the missing value preserved as NULL.
    assert row_count == 1
    assert null_count == 1


def test_does_not_dedupe_identical_rows(tmp_path):
    # Arrange: the same row twice, as a re-scan/re-export would produce.
    xlsx_path = tmp_path / "fixture.xlsx"
    duplicate_row = ["536365", "85123A", "WHITE HANGING HEART T-LIGHT HOLDER", "6", "2010/12/01 08:26:00", "2.55", "17850", "United Kingdom"]
    _write_fixture_workbook(xlsx_path, [duplicate_row, list(duplicate_row)])
    db_path = tmp_path / "warehouse.duckdb"

    # Act
    row_count = load_bronze(xlsx_path, db_path)

    # Assert: both copies are kept — dedup is Silver's decision, not Bronze's.
    assert row_count == 2
