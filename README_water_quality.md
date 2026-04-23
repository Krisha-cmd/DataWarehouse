# Water Quality Ingestion (Airflow + HDFS)

This README documents the dedicated Indian water-quality ingestion pipeline.

- Ingestion script: dags/water_quality_ingestion.py
- Source dataset: rishabchitloor/indian-water-quality-data-2021-2023
- Core file: Indian_water_data.csv

## Dataset Summary

This dataset contains annual water-quality observations for multiple monitoring stations across India for 2021, 2022, and 2023. Each row represents a station-year observation with min/max values for key water-quality parameters.

## Core Fields

### Geographic and Station Fields

- station_code
- monitoring_location
- year
- water_body_type
- state_name

### Water Quality Parameters

Each parameter is recorded as min/max pairs where available:

- temperature_c_min / temperature_c_max
- dissolved_min / dissolved_max
- ph_min / ph_max
- conductivity_umho_cm_min / conductivity_umho_cm_max
- bod_mg_l_min / bod_mg_l_max
- nitraten_mg_l_min / nitraten_mg_l_max
- fecal_coliform_mpn_100ml_min / fecal_coliform_mpn_100ml_max
- total_coliform_mpn_100ml_min / total_coliform_mpn_100ml_max
- fecal_min / fecal_max

## What the Dataset Shows

- How water quality varies across Indian states.
- How water parameters change by year and by water body type.
- Station-level pollution patterns for river and drain monitoring locations.
- Min/max ranges for physical, chemical, and biological indicators.

## Cleaning Rules

The ingestion script applies standard cleanup:

- Column names are normalized to snake_case.
- Null markers such as NA, N/A, empty strings, and dashes are converted to null.
- Station and year fields are cast to numeric where possible.
- Water-quality measurements are coerced to numeric for analysis.
- Column naming noise from the source metadata is normalized for stable downstream joins.

## Normalized Outputs

The script writes both raw and normalized outputs.

### Raw Output

- data/water_quality/water_quality_raw_<date>.csv
  - cleaned wide-format source file

### Dimension Tables

- dim_water_state_<date>.csv
  - unique `state_name` values
- dim_water_station_<date>.csv
  - unique station records with `station_code`, `monitoring_location`, `state_name`, and `water_body_type`

### Fact Tables

- fact_water_quality_measurements_<date>.csv
  - long-format measurement table with:
    - `station_code`
    - `monitoring_location`
    - `year`
    - `water_body_type`
    - `state_name`
    - `parameter`
    - `bound` (`min` or `max`)
    - `value`
    - `unit`
- fact_water_quality_state_year_summary_<date>.csv
  - aggregated summary by `state_name`, `year`, `parameter`, and `bound`
  - includes `avg_value`, `min_value`, `max_value`, and `station_count`

## Output Locations

### Local

- data/water_quality/

### HDFS

- ${WATER_HDFS_BASE_PATH}/<yyyy-mm-dd>/
- default `WATER_HDFS_BASE_PATH`: /water_quality/state_data

## Runtime Configuration

Environment variables supported by dags/water_quality_ingestion.py:

- WATER_DATASET_ENABLED
  - default: true
- WATER_KAGGLE_DATASET_REF
  - default: rishabchitloor/indian-water-quality-data-2021-2023
- WATER_KAGGLE_DATASET_FILE
  - default: Indian_water_data.csv
- WATER_LOCAL_DATA_DIR
  - default: data/water_quality
- WATER_HDFS_BASE_PATH
  - default: /water_quality/state_data
- HDFS_URL
  - default: http://namenode:9870
- HDFS_UPLOAD_ENABLED
  - default: true

## Run

From host:

```powershell
python dags/water_quality_ingestion.py
```

From Airflow container:

```powershell
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/water_quality_ingestion.py
```

## Convergence with Existing Crime and Census Data

This dataset converges most cleanly at the state level.

1. Water data to crime data
- Join key:
  - `water_quality.state_name` -> crime state dimension / `crime.state_ut`
- Recommended path:
  - Use the state bridge pattern described in README_crime.md.
  - Standardize state names first, then join water state-level summaries to crime state-level facts such as literacy, inmate admissions, and undertrials.

2. Water data to census data
- Join key:
  - `water_quality.state_name` -> census state geography / census bridge table
- Recommended path:
  - Use a canonical state bridge table that maps water state names to `state_code_2011` and census geography names.

3. Shared analytical mart
- Best convergence grain:
  - state_name + year + parameter
- Why:
  - Water is year-based.
  - Crime can be aggregated by incident year.
  - Census contributes structural background at state level.

4. Location-level caution
- The water dataset has monitoring locations, but they are not guaranteed to align cleanly with crime city names.
- If you want a city-level join, create a curated location normalization table before joining.

## Suggested Bridge Table

A shared bridge table can unify all three domains:

- dim_geo_bridge
  - canonical_state_name
  - water_state_name
  - crime_state_ut
  - census_state_name
  - state_code_2011
  - optional canonical_city_name
  - optional crime_city
