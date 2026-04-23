# Education in India Ingestion (Airflow + HDFS)

This README documents the dedicated Kaggle ingestion pipeline for the Education in India dataset.

- Ingestion script: dags/education_ingestion.py
- Source dataset: rajanand/education-in-india

## Dataset Summary

This Kaggle archive contains district-wise, elementary state-wise, and secondary state-wise education data for academic year 2015-16. It also includes metadata files that describe the source fields.

The pipeline downloads the full Kaggle archive and ingests every CSV in it so the raw source layout is preserved.

## Source Files

Primary data files:

- 2015_16_Districtwise.csv
- 2015_16_Statewise_Elementary.csv
- 2015_16_Statewise_Secondary.csv

Metadata files:

- 2015_16_Districtwise_Metadata.csv
- 2015_16_Statewise_Elementary_Metadata.csv
- 2015_16_Statewise_Secondary_Metadata.csv

## What the Dataset Shows

The dataset is useful for studying:

- district-level population, literacy, and schooling context
- state-level elementary school supply and enrolment patterns
- state-level secondary school supply, teacher counts, and infrastructure
- differences between rural and urban education availability
- broad infrastructure indicators such as classrooms, libraries, toilets, drinking water, electricity, ICT labs, and teacher strength

## Normalization Strategy

The script uses a two-part approach:

1. Preserve the original Kaggle CSVs as cleaned wide tables.
2. Convert the primary education tables into long-form metric facts so overlapping indicators can be compared across files.

This makes the pipeline flexible without forcing a single hand-written schema over a very wide source.

## Cleaning Rules

The ingestion script applies consistent cleanup:

- Column names are normalized to snake_case.
- Null markers such as NA, N/A, empty strings, and dashes are converted to null.
- Known geography fields are renamed to stable names such as `state_code`, `state_name`, `district_code`, and `district_name`.
- Numeric-heavy columns are coerced to numeric types when the values are mostly numeric.
- Text-heavy fields are preserved as strings so labels and metadata stay readable.

## Normalized Outputs

The script writes both cleaned source files and normalized outputs.

### Manifest

- data/education_in_india/education_in_india_manifest_<date>.csv
  - one row per CSV file in the Kaggle archive
  - includes row and column counts plus the source path

### Cleaned Source Files

Each source CSV is written back out in cleaned form with a source-specific filename prefix, for example:

- data/education_in_india/education_in_india_clean_2015_16_districtwise_<date>.csv
- data/education_in_india/education_in_india_clean_2015_16_statewise_elementary_<date>.csv
- data/education_in_india/education_in_india_clean_2015_16_statewise_secondary_<date>.csv

### Dimension Tables

- dim_education_state_<date>.csv
  - unique state rows across the archive
- dim_education_district_<date>.csv
  - district lookups and core district summary fields from the district-wise file

### Fact Tables

- fact_education_district_metrics_<date>.csv
  - long-form district metrics with original field names preserved in `metric_name`
- fact_education_elementary_metrics_<date>.csv
  - long-form state-level elementary metrics
- fact_education_secondary_metrics_<date>.csv
  - long-form state-level secondary metrics

### Unified Mart

- mart_education_metrics_<date>.csv
  - the preferred consumption table for downstream analysis
  - unions districtwise, elementary, and secondary metrics into one schema
  - includes `domain`, `source_file`, `source_kind`, `geo_grain`, `canonical_state_name`, `metric_name`, and `metric_value`

Each fact table includes:

- source_file
- source_kind
- metric_name
- value

This structure makes it easy to union the three files into a single education mart later.
The pipeline now writes that mart directly so consumers do not need to stitch the source-specific facts together.

## Output Locations

### Local

- data/education_in_india/

### HDFS

Uploaded to:

- ${EDUCATION_HDFS_BASE_PATH}/<yyyy-mm-dd>/
- default EDUCATION_HDFS_BASE_PATH: /education_in_india/state_data

## Runtime Configuration

Environment variables supported by dags/education_ingestion.py:

- EDUCATION_DATASET_ENABLED
  - default: true
- EDUCATION_KAGGLE_DATASET_REF
  - default: rajanand/education-in-india
- EDUCATION_LOCAL_DATA_DIR
  - default: data/education_in_india
- EDUCATION_HDFS_BASE_PATH
  - default: /education_in_india/state_data
- HDFS_URL
  - default: http://namenode:9870
- HDFS_UPLOAD_ENABLED
  - default: true

## Run

From host:

```powershell
python dags/education_ingestion.py
```

From Airflow container:

```powershell
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/education_ingestion.py
```

## Convergence with Existing Crime, Census, and Water Data

The most reliable convergence path is state-level.

1. Education data to crime data
- Join key:
  - education.state_name -> crime state dimension / crime.state_ut
- Recommended path:
  - Use the same state bridge pattern described in README_crime.md.
  - Standardize state names before joining education metrics to crime facts.

2. Education data to census data
- Join key:
  - education.state_name -> census state geography / census bridge table
- Recommended path:
  - Map education state names to the census canonical state code table.

3. Education data to water quality data
- Join key:
  - education.state_name -> water_quality.state_name
- Recommended path:
  - Reuse the shared state bridge table so all three domains land on one canonical state dimension.

4. Best shared mart grain
- state_name + academic_year + metric_name
- Why:
  - The education archive is mostly state and district oriented.
  - Crime, census, and water datasets can all be aggregated to the state level.

## Shared Geo Bridge

The scheduled DAG also builds a shared geo bridge at data/geo_bridge/dim_geo_bridge_<date>.csv.

That table merges the latest state dimensions from all four domains into one canonical lookup with columns such as:

- canonical_state_name
- crime_state_ut
- census_state_name
- census_state_code_2011
- water_state_name
- education_state_name
- education_state_code

Use that table as the first join point before moving into domain-specific facts.

## Suggested Bridge Table

Create a reusable bridge table for all joins:

- dim_geo_bridge
  - canonical_state_name
  - education_state_name
  - crime_state_ut
  - census_state_name
  - state_code_2011
  - water_state_name
  - optional canonical_city_name
  - optional crime_city

This keeps the naming differences across datasets in one place and makes downstream joins deterministic.