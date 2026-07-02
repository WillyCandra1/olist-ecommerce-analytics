"""Rebuild the olist schema in LocalDB, load the cleaned parquet tables,
and fail loudly if SQL row counts do not match the parquet files."""

import sys
from pathlib import Path

import pandas as pd
import pyodbc
import sqlalchemy
from sqlalchemy import text

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROCESSED = PROJECT_ROOT / "data" / "processed"
SCHEMA_FILE = PROJECT_ROOT / "sql" / "01_schema.sql"

# FK targets must load before the tables that reference them
LOAD_ORDER = [
    "customers", "sellers", "products", "geolocation",
    "orders", "order_items", "payments", "reviews",
]


def make_engine():
    installed = [
        d for d in pyodbc.drivers()
        if d in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server")
    ]
    if not installed:
        raise SystemExit(f"No ODBC Driver 17/18 installed. Found: {pyodbc.drivers()}")
    driver = sorted(installed)[-1]
    url = (
        "mssql+pyodbc://@(localdb)\\MSSQLLocalDB/olist"
        f"?driver={driver.replace(' ', '+')}&trusted_connection=yes"
    )
    if driver.endswith("18 for SQL Server"):
        url += "&TrustServerCertificate=yes"
    return sqlalchemy.create_engine(url, fast_executemany=True)


def main():
    engine = make_engine()
    with engine.begin() as conn:
        conn.execute(text(SCHEMA_FILE.read_text()))

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


if __name__ == "__main__":
    main()
