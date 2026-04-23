# Project Setup Guide

A local data platform running four ingestion domains (crime, census, water quality, education in India), a shared geo bridge, and a Kimball-style gold-layer Hive warehouse. Superset connects directly to the Hive warehouse for dashboarding.

## Architecture

```
Kaggle / data.gov.in APIs
        │
        ▼
  Airflow DAG (domain_ingestion_schedule)
        │  runs 5 ingestion scripts
        ▼
      HDFS  ──────────── date-partitioned CSVs
        │
        ▼
  Spark (spark-submit)
        │  hive_warehouse_transform.py
        ▼
  Hive warehouse_gold  ◄──── Superset dashboards
```

**Alternative (local bypass):**
```
Python host  ──►  scripts/local_hive_load.py  ──►  Hive warehouse_silver
```

---

## Service URLs

| Service | URL / Port | Notes |
|---|---|---|
| Airflow | http://localhost:8080 | admin / admin |
| Superset | http://localhost:8088 | admin / admin |
| NameNode UI | http://localhost:9870 | HDFS file browser |
| Spark Master | http://localhost:8081 | job monitoring |
| DataNode | http://localhost:9864 | |
| HiveServer2 | localhost:10000 | Thrift binary — not HTTP |
| Hive Metastore | localhost:9083 | Thrift binary — not HTTP |

---

## Prerequisites

- Docker Desktop ≥ 4.x with Compose v2
- At least 8 GB RAM allocated to Docker
- Kaggle credentials if downloading Kaggle datasets (`~/.kaggle/kaggle.json`)
- Python ≥ 3.10 on the host (only needed for the local bypass script)

---

## Repository Layout

```
.
├── dags/
│   ├── crime_ingestion.py
│   ├── census_ingestion.py
│   ├── water_quality_ingestion.py
│   ├── education_ingestion.py
│   ├── geo_bridge_ingestion.py
│   ├── geo_bridge.py               # shared state-name canonicalisation
│   ├── hive_warehouse_transform.py # Spark gold-layer job
│   └── domain_ingestion_dag.py     # Airflow DAG definition
├── config/spark/                   # core-site.xml, hive-site.xml, spark-defaults
├── hql/
│   └── warehouse_gold_ddl.hql      # optional pre-create DDL for warehouse_gold
├── scripts/
│   └── local_hive_load.py          # bypass script (no HDFS/Airflow/Spark)
├── superset/
│   └── superset_config.py          # Superset settings (Redis cache, secret key)
├── Dockerfile                      # custom Airflow image (pyspark + requirements)
├── Dockerfile.superset             # custom Superset image (pyhive + thrift)
├── docker-compose.yaml
├── init-hive-db.sql                # postgres init — creates hive + superset DBs
└── requirements.txt
```

---

## First-Time Setup

### Step 1 — Clone and enter the project

```powershell
cd airflow-hdfs
```

### Step 2 — Create postgres databases for Hive and Superset

> **Skip this step** only if you are starting with a completely fresh Docker environment
> (no existing `postgres-db-volume`). In that case `init-hive-db.sql` runs automatically.

If postgres is already running (existing volume):

```powershell
# Hive metastore database
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "CREATE USER hive WITH PASSWORD 'hive';"
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "CREATE DATABASE hive_metastore OWNER hive;"
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "GRANT ALL PRIVILEGES ON DATABASE hive_metastore TO hive;"

# Superset metadata database
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "CREATE USER superset WITH PASSWORD 'superset';"
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "CREATE DATABASE superset OWNER superset;"
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "GRANT ALL PRIVILEGES ON DATABASE superset TO superset;"
```

### Step 3 — Build images

```powershell
docker compose build
```

This builds two custom images:
- **Airflow image** — adds Java, pyspark, hdfs, kagglehub, pyhive
- **Superset image** — adds pyhive, thrift (for Hive connectivity)

### Step 4 — Start HDFS and postgres first

```powershell
docker compose up -d namenode datanode postgres redis
```

Wait until namenode is healthy (usually ~30 seconds):

```powershell
docker compose ps
```

### Step 5 — Initialize the Hive metastore schema

This is a one-time step. It populates the Hive schema tables in postgres.

```powershell
docker compose up -d hive-metastore hive-server
```

Wait ~30 seconds for hive-metastore to start, then run:

```powershell
docker exec hive-server /opt/hive/bin/schematool -dbType postgres -initSchema
```

Expected output: `schemaTool completed`

> On subsequent restarts you do **not** need to run schematool again. The schema
> persists in the `hive_metastore` postgres database.

### Step 6 — Start the full stack

```powershell
docker compose up -d
```

This starts Airflow (webserver, scheduler, worker, triggerer), Spark (master, worker), and Superset.

Wait for Airflow init to complete (~2 minutes):

```powershell
docker compose logs -f airflow-init
# When you see "Admin user airflow created", press Ctrl+C
```

Wait for Superset init to complete (~1 minute):

```powershell
docker compose logs -f superset-init
# When you see "superset-init-done", press Ctrl+C
```

### Step 7 — Verify everything is healthy

```powershell
docker compose ps
```

All services except `superset-init` and `airflow-init` should show `Up` or `Up (healthy)`.

Quick connectivity checks:

```powershell
# HiveServer2 responds
docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000' -n root -e 'SHOW DATABASES;'"

# Airflow UI reachable
Invoke-WebRequest http://localhost:8080/health -UseBasicParsing | Select-Object StatusCode

# Superset UI reachable
Invoke-WebRequest http://localhost:8088/health -UseBasicParsing | Select-Object StatusCode
```

---

## Option A — Run the Full Pipeline via Airflow DAG

### Trigger the DAG

From the Airflow UI at http://localhost:8080 (admin / admin):
1. Find `domain_ingestion_schedule`
2. Click **Trigger DAG**

Or from the terminal:

```powershell
docker compose exec airflow-webserver airflow dags trigger domain_ingestion_schedule
```

### Monitor progress

```powershell
# Watch task states
docker compose exec airflow-webserver airflow dags list-runs -d domain_ingestion_schedule

# Tail a specific task log (replace <run_id> and <task_id>)
docker compose exec airflow-webserver airflow tasks logs domain_ingestion_schedule <task_id> <run_id>
```

### What the DAG does

| Task | What it runs |
|---|---|
| `ingest_crime` | `crime_ingestion.py` — fetches NCRB data.gov.in + Kaggle crime CSV, writes to HDFS |
| `ingest_census` | `census_ingestion.py` — fetches Census 2011 primary abstract, writes to HDFS |
| `ingest_water` | `water_quality_ingestion.py` — downloads Kaggle water quality dataset, writes to HDFS |
| `ingest_education` | `education_ingestion.py` — downloads Kaggle education dataset, writes to HDFS |
| `build_geo_bridge` | `geo_bridge_ingestion.py` — cross-domain canonical state bridge, writes to HDFS |
| `transform_to_hive` | `hive_warehouse_transform.py` — Spark job that reads HDFS CSVs and writes Parquet star schema to `warehouse_gold` |

### Run ingestion scripts manually (without triggering the full DAG)

```powershell
docker compose exec airflow-webserver python /opt/airflow/dags/crime_ingestion.py
docker compose exec airflow-webserver python /opt/airflow/dags/census_ingestion.py
docker compose exec airflow-webserver python /opt/airflow/dags/water_quality_ingestion.py
docker compose exec airflow-webserver python /opt/airflow/dags/education_ingestion.py
docker compose exec airflow-webserver python /opt/airflow/dags/geo_bridge_ingestion.py
```

### Run the Spark warehouse transform manually

```powershell
docker compose exec airflow-webserver \
  /home/airflow/.local/bin/spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode client \
  --conf spark.sql.catalogImplementation=hive \
  --conf spark.sql.warehouse.dir=hdfs://namenode:8020/warehouse/gold \
  --conf spark.hadoop.fs.defaultFS=hdfs://namenode:8020 \
  --conf spark.hadoop.hive.metastore.uris=thrift://hive-metastore:9083 \
  /opt/airflow/dags/hive_warehouse_transform.py \
  --run-date 2026-04-23
```

### Verify Hive tables after the DAG

```powershell
# List databases
docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000' -n root -e 'SHOW DATABASES;'"

# List tables in warehouse_gold
docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000/warehouse_gold' -n root -e 'SHOW TABLES;'"

# Sample query
docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000/warehouse_gold' -n root -e 'SELECT state_name, is_union_territory FROM dim_state LIMIT 10;'"
```

---

## Option B — Local Bypass Script (no HDFS / Airflow / Spark)

This runs all ingestion pipelines and the star schema transforms on your host machine using pandas only, then loads results directly into Hive via PyHive. Useful for debugging without a full cluster.

### Install host dependencies

```powershell
pip install "pyhive[hive]" thrift pandas requests kagglehub hdfs
```

### Run the script

```powershell
# From the project root — runs all 5 ingestion pipelines then loads into Hive
python scripts/local_hive_load.py

# Skip re-downloading data (reuses today's CSVs in data/)
python scripts/local_hive_load.py --skip-ingestion

# Custom host/port if HiveServer2 is not on localhost:10000
python scripts/local_hive_load.py --host localhost --port 10000
```

### What it does

1. Sets `HDFS_UPLOAD_ENABLED=false` so ingestion scripts skip all HDFS writes
2. Calls `run_pipeline()` in each of the 5 ingestion modules
3. CSVs are saved locally under `data/crime/`, `data/water_quality/`, `data/census_2011/`, `data/education_in_india/`, `data/geo_bridge/`
4. Connects to HiveServer2 at `localhost:10000` via PyHive
5. Creates a `warehouse_silver` database and loads every CSV as a table

### Verify after the local script

```powershell
# List all loaded tables
docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000/warehouse_silver' -n root -e 'SHOW TABLES;'"

# Sample query
docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000/warehouse_silver' -n root -e 'SELECT * FROM dim_state LIMIT 5;'"
```

---

## Superset — Connect to Hive and Build Dashboards

### Step 1 — Open Superset

Go to http://localhost:8088 and log in:

- **Username:** `admin`
- **Password:** `admin`

### Step 2 — Add the Hive database connection

1. In the top nav go to **Settings → Database Connections → + Database**
2. Select **Apache Hive** from the database list
3. Enter the **SQLAlchemy URI**:

**After running the Airflow DAG (warehouse_gold):**
```
hive://hive-server:10000/warehouse_gold
```

**After running the local bypass script (warehouse_silver):**
```
hive://hive-server:10000/warehouse_silver
```

4. Click **Test Connection** — you should see "Connection looks good!"
5. Click **Connect**

### Step 3 — Create datasets

1. Go to **Data → Datasets → + Dataset**
2. Select the Hive database, choose the schema, and pick a table (e.g. `dim_state`, `fact_crime_incident`)
3. Click **Add** to register it as a Superset dataset

### Step 4 — Build charts and dashboards

- Go to **Charts → + Chart**, pick a dataset and chart type
- Go to **Dashboards → + Dashboard** to arrange charts

### Useful Hive tables in warehouse_gold

| Table | Description |
|---|---|
| `dim_state` | All states/UTs with canonical names and surrogate keys |
| `dim_district` | Districts keyed to states (SCD-2) |
| `dim_date` | Calendar dimension with India fiscal + academic year |
| `fact_crime_incident` | One row per crime incident (Kaggle source) |
| `fact_inmate_population` | Prison population across all NCRB sub-tables |
| `fact_literacy_rate` | State-year literacy rates |
| `fact_population` | Census 2011 demographics in long form |
| `fact_water_measurement` | Water quality station-year-parameter measurements |
| `fact_education_indicator` | Education metrics by state/district and academic year |

---

## Day-to-Day Commands

```powershell
# Start everything (after initial setup)
docker compose up -d

# Stop everything (keeps volumes)
docker compose down

# Tear down and delete all data
docker compose down -v

# Rebuild after changing Dockerfile or requirements
docker compose build
docker compose up -d

# View logs for a specific service
docker compose logs -f superset
docker compose logs -f hive-metastore
docker compose logs -f airflow-scheduler

# Restart a single service
docker compose restart hive-server
docker compose restart superset
```

---

## Troubleshooting

### `ModuleNotFoundError: No module named 'hdfs'` in Airflow tasks

The Airflow image wasn't rebuilt after `requirements.txt` was updated.

```powershell
docker compose build
docker compose up -d --force-recreate airflow-worker airflow-scheduler
```

### `hive-metastore` exits immediately

Either the postgres `hive` user/database doesn't exist, or schematool hasn't been run.

```powershell
# 1. Create postgres objects (if missing)
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "CREATE USER hive WITH PASSWORD 'hive';"
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "CREATE DATABASE hive_metastore OWNER hive;"
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "GRANT ALL PRIVILEGES ON DATABASE hive_metastore TO hive;"

# 2. Start metastore (so hive-server has a running image to run schematool from)
docker compose up -d hive-server

# 3. Init schema
docker exec hive-server /opt/hive/bin/schematool -dbType postgres -initSchema

# 4. Start metastore
docker compose up -d hive-metastore

# 5. Restart hive-server so it reconnects
docker compose restart hive-server
```

### `Version information not found in metastore`

schematool hasn't initialised the schema yet. Run step 3 above.

### `User: root is not allowed to impersonate root`

`hive.server2.enable.doAs` is set to `true` without Hadoop proxyuser config. The compose already sets `HIVE_SITE_CONF_hive_server2_enable_doAs=false`. If you see this after a restart, force-recreate hive-server:

```powershell
docker compose up -d --force-recreate hive-server
```

### `superset-init` fails with database connection error

The postgres `superset` user or database doesn't exist.

```powershell
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "CREATE USER superset WITH PASSWORD 'superset';"
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "CREATE DATABASE superset OWNER superset;"
docker exec -i airflow-hdfs-postgres-1 psql -U airflow -c "GRANT ALL PRIVILEGES ON DATABASE superset TO superset;"
docker compose up -d superset-init
docker compose up -d superset
```

### Superset login says "Invalid login" (admin / admin not working)

The admin user was not created by `superset-init`. Create it manually on the running container:

```powershell
docker exec superset superset fab create-admin `
    --username admin `
    --firstname Admin `
    --lastname User `
    --email admin@admin.com `
    --password admin
```

### Beeline `Connection refused` on port 10000

HiveServer2 inside hive-server hasn't started yet (it waits for hive-metastore). Check:

```powershell
docker compose ps
docker compose logs hive-server | Select-String -Pattern "Starting HiveServer2|ERROR"
```

### Namenode is in safe mode

After a crash HDFS enters safe mode. Exit it:

```powershell
docker exec namenode hdfs dfsadmin -safemode leave
```

### Check HDFS contents after ingestion

```powershell
docker exec namenode hdfs dfs -ls /crime/state_data/
docker exec namenode hdfs dfs -ls /water_quality/state_data/
docker exec namenode hdfs dfs -ls /warehouse/gold/
```
