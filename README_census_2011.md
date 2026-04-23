# Census 2011 Ingestion (Airflow + HDFS)

This README documents the dedicated Census 2011 ingestion pipeline.

- Ingestion script: dags/census_ingestion.py
- Source resource (data.gov.in): 0764657f-00ec-4c6b-9ece-2d7b8a7401fa

## Dataset Summary

The dataset provides 2011 Census counts at multiple geographic levels using these key administrative fields:

- State Code
- District Code
- Subdistt Code
- Town/Village Code
- Ward Code
- EB Code
- Level
- Name
- TRU (Total/Rural/Urban)

It includes household, population, age, caste/tribe, literacy, worker, and non-worker measures.

## Key Field Groups

### Geographic Keys

- state_code
- district_code
- subdistt_code
- town_village_code
- ward_code
- eb_code
- level
- name
- tru

### Population and Demographics

- no_of_households
- total_population_person / male / female
- population_in_the_age_group_0_6_person / male / female
- scheduled_castes_population_person / male / female
- scheduled_tribes_population_person / male / female
- literates_population_person / male / female
- illiterate_persons / male / female
- non_working_population_person / male / female

### Workforce

- total_worker_population_person / male / female
- main_working_population_person / male / female
- main_cultivator_population_person / male / female
- main_agricultural_labourers_population_person / male / female
- main_household_industries_population_person / male / female
- main_other_workers_population_person / male / female
- marginal_worker_population_person / male / female
- marginal_cultivator_population_person / male / female
- marginal_agriculture_labourers_population_person / male / female
- marginal_household_industries_population_person / male / female
- marginal_other_workers_population_person / male / female

## Cleaning Rules

The pipeline applies consistent cleaning:

- snake_case normalization for all column names
- null marker normalization (NA, N/A, empty, -)
- numeric coercion for numeric-heavy columns
- string normalization for level, name, and TRU
- standardization of known malformed headers in source columns

## Output Files

### Local

- data/census_2011/census_2011_raw_<date>.csv
- data/census_2011/dim_census_geography_<date>.csv
- data/census_2011/fact_census_demographics_2011_<date>.csv
- data/census_2011/fact_census_workforce_2011_<date>.csv

### HDFS

Uploaded to:

- ${CENSUS_HDFS_BASE_PATH}/<yyyy-mm-dd>/
- default CENSUS_HDFS_BASE_PATH: /census_2011/state_data

## Runtime Configuration

Environment variables supported by dags/census_ingestion.py:

- DATA_GOV_API_KEY
- CENSUS_2011_RESOURCE_ID (default: 0764657f-00ec-4c6b-9ece-2d7b8a7401fa)
- CENSUS_LOCAL_DATA_DIR (default: data/census_2011)
- CENSUS_HDFS_BASE_PATH (default: /census_2011/state_data)
- HDFS_URL (default: http://namenode:9870)
- HDFS_UPLOAD_ENABLED (default: true)

## Run

From host:

```powershell
python dags/census_ingestion.py
```

From Airflow container:

```powershell
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/census_ingestion.py
```

## Convergence with Existing Crime Data

Your crime pipeline is documented in README_crime.md and produces state-level and city-level facts. Census 2011 can be converged with those crime outputs at these levels:

1. State-level convergence (recommended)
- Join keys:
  - census.geo_name where level indicates state-like rows
  - crime.state_ut in crime fact tables (for example fact_literacy_rate, fact_undertrials_age_gender, fact_inmates_admitted_gender)
- Strategy:
  - Build a state name mapping table to align naming variants (for example NCT of Delhi vs Delhi).
  - Keep state_code_2011 in census facts as canonical code and map crime names to it.

2. Urban/rural segmentation convergence
- Join keys:
  - census.tru (T/R/U)
  - crime dataset partitioning by geography when state-level join exists
- Value:
  - Compare crime indicators with rural/urban demographic and workforce structure.

3. Workforce and literacy contextual features
- Use census columns as explanatory features for crime analytics:
  - literacy and illiteracy counts
  - worker and marginal worker categories
  - SC/ST population composition
- Typical use:
  - Build analytical marts with one row per state and year snapshot using mapped state_code_2011.

4. City-level caution
- Current census ingest is code-heavy for multi-level geographies and does not directly output a city-name dimension aligned to Kaggle city names.
- For city-level convergence with crime incidents, add a curated city normalization table (city_alias -> canonical_city + state_code_2011).

## Suggested Integration Table

Create a reusable bridge table for all joins:

- dim_geo_bridge
  - state_code_2011
  - canonical_state_name
  - crime_state_ut
  - optional canonical_city_name
  - optional crime_city

This bridge decouples naming inconsistencies and makes joins deterministic.
