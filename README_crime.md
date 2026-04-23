# Crime Data Ingestion (Airflow + HDFS)

This project ingests multiple crime-related datasets (data.gov.in + Kaggle) and stores both:

- cleaned dataset-specific CSVs (raw shape retained), and
- normalized CSVs (shared schema across overlapping fields)

All ingestion is handled in a single script:

- `dags/crime_ingestion.py`

## Datasets Ingested

The script ingests these 7 resources in one run:

1. Statewise literacy rate
- Resource ID: `ebb33c4b-ed21-4f69-8896-571b55523447`
- Typical fields:
  - `Sl. No.`
  - `State/UT`
  - `2019-20`
  - `2020-21`

2. State/UT-wise and age-group-wise percentage share of convicts (as on 31-12-2023)
- Resource ID: `b09505ad-8054-4c03-a1fc-bdbb0e1b29ee`
- Typical fields:
  - `State/UT`
  - Age buckets (16-18, 18-30, 30-50, 50+)
  - Each bucket contains:
    - `No. of Convicts`
    - `Percentage Share`
  - Total convicts + total percentage

3. State/UT-wise number of inmates admitted during 2023
- Resource ID: `0f12beab-bb77-42e8-8307-6c5b47b9cc3a`
- Typical fields:
  - `State/UT`
  - `Male`
  - `Female`
  - `Transgender`
  - `Total`

4. State/UT-wise education profile of detenues (as on 31-12-2023)
- Resource ID: `4953eca4-e466-44ce-b554-2bbde2d9360e`
- Typical fields:
  - `State/UT`
  - `Educational Standard - Illiterate`
  - `Educational Standard - Below Class X`
  - `Educational Standard - Class X and above but below Graduation`
  - `Educational Standard - Graduate`
  - `Educational Standard - Holding Tech. Degree/Diploma`
  - `Educational Standard - Post Graduate`
  - `Educational Standard - Total`

5. Category-wise details of female inmates in different jails (as on 31-12-2023)
- Resource ID: `ad097c44-2c2b-4549-9792-f1c64233f703`
- Typical fields:
  - `Type` (Central Jail, District Jail, etc.)
  - `Convicts` (+ percentage share)
  - `Undertrials` (+ percentage share)
  - `Detenues` (+ percentage share)
  - `Others` (+ percentage share)
  - `Total`

6. State/UT-wise undertrials in jails by gender and age-group (as on 31-12-2023)
- Resource ID: `e34efa75-5f4e-4258-b5d6-fbafaaa46c85`
- Typical fields:
  - `State/UT`
  - For each age-group: Male, Female, Transgender, Total

7. Indian Crimes Dataset (Kaggle)
- Dataset reference: `sudhanvahg/indian-crimes-dataset`
- File: `crime_dataset_india.csv`
- Typical fields:
  - `Report Number`
  - `Date Reported`
  - `Date of Occurrence`
  - `Time of Occurrence`
  - `City`
  - `Crime Code`
  - `Crime Description`
  - `Victim Age`
  - `Victim Gender`
  - `Weapon Used`
  - `Crime Domain`
  - `Police Deployed`
  - `Case Closed`
  - `Date Case Closed`

## What Each Dataset Shows

- Dataset 1: Literacy comparison across states/UTs across years.
- Dataset 2: Convict composition by age-group, including count and % share.
- Dataset 3: New inmate admissions by gender in 2023.
- Dataset 4: Educational composition of detenues by state/UT.
- Dataset 5: Female inmate distribution by jail type and legal category.
- Dataset 6: Undertrial population split by age-group and gender.
- Dataset 7: Incident-level crime records across cities, including victim profile and case closure details.

## Cleaning Rules Applied

During ingestion, each dataset is standardized using common cleaning logic:

- Column names normalized to snake_case.
- Symbols and punctuation removed from column names.
- Common null markers (`NA`, `N/A`, empty, `-`) converted to null.
- Numeric-looking columns auto-cast to numeric (robust against commas).
- `stateut` is normalized to `state_ut`.

## Normalization of Overlapping Fields

The script creates shared normalized tables from all datasets.

### Shared Dimensions

- `dim_state_<date>.csv`
  - Canonical list of `state_ut` values across all state-level datasets.

- `dim_city_<date>.csv`
  - Canonical list of `city` values from the Kaggle incident-level dataset.

### Shared Facts

- `fact_literacy_rate_<date>.csv`
  - Columns: `state_ut`, `year`, `literacy_rate`
  - Derived from wide year columns in dataset 1.

- `fact_convicts_age_share_<date>.csv`
  - Columns: `state_ut`, `age_group`, `no_of_convicts`, `percentage_share`
  - Derived from age-bucket columns in dataset 2.

- `fact_undertrials_age_gender_<date>.csv`
  - Columns: `state_ut`, `age_group`, `gender`, `count`, `metric`, `year`
  - Derived from age + gender columns in dataset 6.

- `fact_inmates_admitted_gender_<date>.csv`
  - Columns: `state_ut`, `age_group`, `gender`, `count`, `metric`, `year`
  - Derived from gender columns in dataset 3.
  - Uses `age_group = all_ages` so it can align with dataset 6 format.

- `fact_gender_age_counts_<date>.csv`
  - Union of admitted and undertrial facts with common schema.
  - Useful for combined gender-age analytics across multiple sources.

- `fact_detenues_education_<date>.csv`
  - Columns: `state_ut`, `education_level`, `value`, `year`
  - Long-form projection of educational categories from dataset 4.

- `fact_female_inmates_category_<date>.csv`
  - Columns: `jail_type`, `category`, `count`, `percentage_share`, `total`, `year`
  - Long-form projection from dataset 5.

- `fact_kaggle_crime_incidents_<date>.csv`
  - Columns include: `report_number`, `date_reported`, `date_of_occurrence`, `time_of_occurrence`, `city`, `crime_code`, `crime_description`, `crime_domain`, `weapon_used`, `victim_age`, `victim_gender`, `police_deployed`, `case_closed`, `date_case_closed`, `source`
  - Normalized incident-level projection from dataset 7.

- `fact_kaggle_victim_age_gender_<date>.csv`
  - Columns: `city`, `age_group`, `gender`, `count`, `metric`, `year`
  - Aggregated victim demographic view derived from dataset 7.
  - Age groups are bucketed to align with prison dataset style: `under_18`, `18_29`, `30_49`, `50_and_above`, `unknown`.

## Output Locations

### Local

All output CSV files are written to:

- `data/crime/`

### HDFS

If HDFS upload is enabled, all generated CSVs are uploaded to:

- `${HDFS_BASE_PATH}/<yyyy-mm-dd>/`
- default `HDFS_BASE_PATH` is `/crime/state_data`

## Runtime Configuration

Environment variables supported by `dags/crime_ingestion.py`:

- `DATA_GOV_API_KEY`
  - API key for data.gov.in
- `HDFS_URL`
  - default: `http://namenode:9870`
- `HDFS_BASE_PATH`
  - default: `/crime/state_data`
- `HDFS_UPLOAD_ENABLED`
  - default: `true`
- `LOCAL_DATA_DIR`
  - default: `data/crime`
- `KAGGLE_DATASET_ENABLED`
  - default: `true`
- `KAGGLE_DATASET_REF`
  - default: `sudhanvahg/indian-crimes-dataset`
- `KAGGLE_DATASET_FILE`
  - default: `crime_dataset_india.csv`

Kaggle note:

- The script uses `kagglehub` for download.
- If Kaggle access is restricted in your environment, this dataset will log a failure while other datasets continue.

## Run Example

From project root:

```powershell
python dags/crime_ingestion.py
```

Or from Airflow container:

```powershell
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/crime_ingestion.py
```

## Notes

- The script uses pagination (`limit` + `offset`) to fetch large datasets.
- If one dataset fails, the script continues ingesting others and logs the failure.
- HDFS upload failures are logged per file and do not stop local file generation.
