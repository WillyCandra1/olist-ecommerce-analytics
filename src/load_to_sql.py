"""Rebuild the olist schema in LocalDB, load the cleaned parquet tables,
verify row parity against the parquet files, and create the Power BI views.
Creates the olist database first if it does not exist."""

import re
import sys
from pathlib import Path

import pandas as pd
import pyodbc
import sqlalchemy
from sqlalchemy import text

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROCESSED = PROJECT_ROOT / "data" / "processed"
SCHEMA_FILE = PROJECT_ROOT / "sql" / "01_schema.sql"
VIEWS_FILE = PROJECT_ROOT / "sql" / "03_powerbi_views.sql"

# FK targets must load before the tables that reference them
LOAD_ORDER = [
    "customers", "sellers", "products", "geolocation",
    "orders", "order_items", "payments", "reviews",
]


def connection_url(database):
    installed = [
        d for d in pyodbc.drivers()
        if d in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server")
    ]
    if not installed:
        raise SystemExit(f"No ODBC Driver 17/18 installed. Found: {pyodbc.drivers()}")
    driver = sorted(installed)[-1]
    url = (
        f"mssql+pyodbc://@(localdb)\\MSSQLLocalDB/{database}"
        f"?driver={driver.replace(' ', '+')}&trusted_connection=yes"
    )
    if driver.endswith("18 for SQL Server"):
        url += "&TrustServerCertificate=yes"
    return url


def ensure_database():
    # CREATE DATABASE cannot run inside a transaction, hence AUTOCOMMIT
    master = sqlalchemy.create_engine(connection_url("master"), isolation_level="AUTOCOMMIT")
    with master.connect() as conn:
        created = conn.execute(text(
            "IF DB_ID('olist') IS NULL BEGIN CREATE DATABASE olist; SELECT 1; END ELSE SELECT 0"
        )).scalar()
    print("database olist created" if created else "database olist exists")


def run_batched_script(engine, script_path):
    # sqlcmd-style scripts separate batches with GO, which pyodbc cannot execute
    batches = re.split(r"(?im)^\s*GO\s*$", script_path.read_text())
    with engine.begin() as conn:
        for batch in filter(str.strip, batches):
            conn.execute(text(batch))


def main():
    ensure_database()
    engine = sqlalchemy.create_engine(connection_url("olist"), fast_executemany=True)
    run_batched_script(engine, SCHEMA_FILE)

    frames = {name: pd.read_parquet(PROCESSED / f"{name}.parquet") for name in LOAD_ORDER}
    for name, df in frames.items():
        df.to_sql(name, engine, schema="dbo", if_exists="append", index=False, chunksize=20_000)
        print(f"loaded {name}: {len(df):,} rows")

    with engine.connect() as conn:
        sql_counts = {
            name: conn.execute(text(f"SELECT COUNT(*) FROM dbo.{name}")).scalar()
            for name in LOAD_ORDER
        }

    parity = pd.DataFrame({
        "parquet_rows": {name: len(df) for name, df in frames.items()},
        "sql_rows": sql_counts,
    })
    parity["match"] = parity["parquet_rows"] == parity["sql_rows"]
    print(parity.to_string())
    if not parity["match"].all():
        sys.exit("row count mismatch between parquet and SQL")
    print("parity check passed")

    run_batched_script(engine, VIEWS_FILE)
    with engine.connect() as conn:
        views = conn.execute(text("SELECT COUNT(*) FROM sys.views")).scalar()
    print(f"power bi views created: {views}")


if __name__ == "__main__":
    main()
