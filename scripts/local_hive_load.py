"""
scripts/local_hive_load.py
--------------------------
Runs all domain ingestion pipelines locally (no HDFS, no Airflow, no Spark)
and loads the generated CSVs into Hive via PyHive at localhost:10000.

This is a temporary bypass script for debugging. The full pipeline is:
  Airflow DAG -> ingestion scripts -> HDFS -> Spark -> Hive (star schema)

This script skips HDFS/Airflow/Spark and writes a flat silver layer directly
into a `warehouse_silver` Hive database — one table per ingestion output CSV.

Requirements (install on the host machine):
    pip install pyhive[hive] thrift pandas kagglehub requests hdfs

Hive must be reachable at localhost:10000 (docker-compose port 10000 is exposed).

Usage (run from project root):
    python scripts/local_hive_load.py
    python scripts/local_hive_load.py --skip-ingestion   # reuse existing CSVs
    python scripts/local_hive_load.py --host localhost --port 10000
"""

import os
import sys
import argparse
from datetime import datetime
from pathlib import Path

# Set env vars BEFORE importing any ingestion module — they read these at
# module level when imported.
os.environ["HDFS_UPLOAD_ENABLED"] = "false"
os.environ.setdefault("HDFS_URL", "http://localhost:9870")

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DAGS_DIR = PROJECT_ROOT / "dags"
sys.path.insert(0, str(DAGS_DIR))

import pandas as pd

HIVE_DB = "warehouse_silver"
DATE_PARTITION = datetime.now().strftime("%Y-%m-%d")

DATA_DIRS = [
    "data/crime",
    "data/water_quality",
    "data/census_2011",
    "data/education_in_india",
    "data/geo_bridge",
]


# ---------------------------------------------------------------------------
# Hive helpers
# ---------------------------------------------------------------------------

def get_hive_conn(host: str, port: int):
    from pyhive import hive
    return hive.connect(
        host=host,
        port=port,
        username="root",
        auth="NONE",
        database="default",
        configuration={"hive.exec.dynamic.partition.mode": "nonstrict"},
    )


def ensure_database(cursor) -> None:
    cursor.execute(f"CREATE DATABASE IF NOT EXISTS {HIVE_DB}")
    cursor.execute(f"USE {HIVE_DB}")
    print(f"Database ready: {HIVE_DB}")


def df_to_hive(cursor, table_name: str, df: pd.DataFrame, chunk_size: int = 200) -> None:
    if df is None or df.empty:
        print(f"  [skip] {table_name}: empty")
        return

    df = df.copy().where(pd.notnull(df), None)
    safe_cols = [str(c).replace("`", "").replace("\n", " ") for c in df.columns]
    df.columns = safe_cols

    col_defs = ",\n    ".join(f"`{c}` STRING" for c in safe_cols)
    cursor.execute(f"DROP TABLE IF EXISTS {HIVE_DB}.{table_name}")
    cursor.execute(
        f"CREATE TABLE {HIVE_DB}.{table_name} (\n    {col_defs}\n) "
        f"ROW FORMAT DELIMITED FIELDS TERMINATED BY '\\t' STORED AS TEXTFILE"
    )

    total = 0
    for start in range(0, len(df), chunk_size):
        chunk = df.iloc[start : start + chunk_size]
        rows = []
        for _, row in chunk.iterrows():
            vals = []
            for v in row:
                if v is None:
                    vals.append("NULL")
                else:
                    escaped = str(v).replace("\\", "\\\\").replace("'", "\\'")
                    vals.append(f"'{escaped}'")
            rows.append(f"({', '.join(vals)})")
        cursor.execute(f"INSERT INTO {HIVE_DB}.{table_name} VALUES {', '.join(rows)}")
        total += len(chunk)

    print(f"  [ok] {table_name}: {total} rows")


# ---------------------------------------------------------------------------
# Ingestion
# ---------------------------------------------------------------------------

def run_ingestion() -> None:
    print("\n=== Running ingestion pipelines (HDFS disabled) ===\n")

    print("[1/5] Water quality")
    from water_quality_ingestion import run_pipeline as _water
    _water()

    print("\n[2/5] Crime")
    from crime_ingestion import run_pipeline as _crime
    _crime()

    print("\n[3/5] Census 2011")
    from census_ingestion import run_pipeline as _census
    _census()

    print("\n[4/5] Education in India")
    from education_ingestion import run_pipeline as _edu
    _edu()

    print("\n[5/5] Geo bridge")
    from geo_bridge_ingestion import run_pipeline as _geo
    _geo()


def collect_csvs() -> dict[str, pd.DataFrame]:
    tables: dict[str, pd.DataFrame] = {}
    for rel_dir in DATA_DIRS:
        dir_path = PROJECT_ROOT / rel_dir
        if not dir_path.exists():
            continue
        for csv_file in sorted(dir_path.glob(f"*_{DATE_PARTITION}.csv")):
            # Strip the trailing _yyyy-mm-dd date suffix to get the table name
            stem = csv_file.stem
            table_name = stem[: stem.rfind(f"_{DATE_PARTITION}")]
            df = pd.read_csv(csv_file, low_memory=False, dtype=str)
            tables[table_name] = df
            print(f"  {csv_file.relative_to(PROJECT_ROOT)}  ->  {table_name}  ({len(df)} rows)")
    return tables


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="localhost", help="HiveServer2 host (default: localhost)")
    parser.add_argument("--port", type=int, default=10000, help="HiveServer2 port (default: 10000)")
    parser.add_argument(
        "--skip-ingestion",
        action="store_true",
        help="Skip running ingestion pipelines and reuse today's existing CSVs",
    )
    args = parser.parse_args()

    if not args.skip_ingestion:
        run_ingestion()
    else:
        print("Skipping ingestion — using existing CSVs.")

    print(f"\n=== Collecting CSVs for {DATE_PARTITION} ===\n")
    tables = collect_csvs()

    if not tables:
        print(f"No CSV files found for {DATE_PARTITION} in {DATA_DIRS}.")
        print("Run without --skip-ingestion first, or check that ingestion ran today.")
        sys.exit(1)

    print(f"\n=== Connecting to HiveServer2 at {args.host}:{args.port} ===\n")
    try:
        conn = get_hive_conn(args.host, args.port)
    except Exception as exc:
        print(f"Connection failed: {exc}")
        print("Make sure hive-server container is running and port 10000 is exposed.")
        sys.exit(1)

    cursor = conn.cursor()
    ensure_database(cursor)

    print(f"\n=== Loading {len(tables)} tables into {HIVE_DB} ===\n")
    failed = []
    for table_name, df in tables.items():
        try:
            df_to_hive(cursor, table_name, df)
        except Exception as exc:
            print(f"  [error] {table_name}: {exc}")
            failed.append(table_name)

    cursor.close()
    conn.close()

    print(f"\n=== Done ===")
    print(f"Loaded: {len(tables) - len(failed)}/{len(tables)} tables into {HIVE_DB}")
    if failed:
        print(f"Failed: {failed}")
    print(f"\nVerify in beeline:")
    print(f"  beeline -u 'jdbc:hive2://localhost:10000/{HIVE_DB}' -n root")
    print(f"  > SHOW TABLES;")


if __name__ == "__main__":
    main()
