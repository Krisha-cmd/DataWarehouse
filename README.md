# Data Ingestion Pipelines

This repository now has separate ingestion pipelines by domain.

## Available Pipelines

- Crime datasets (data.gov.in + Kaggle): see README_crime.md
  - Script: dags/crime_ingestion.py

- Census 2011 dataset (data.gov.in): see README_census_2011.md
  - Script: dags/census_ingestion.py

- Water quality dataset (Kaggle): see README_water_quality.md
  - Script: dags/water_quality_ingestion.py

- Education in India dataset (Kaggle): see README_education_in_india.md
  - Script: dags/education_ingestion.py

- Shared geo bridge and scheduled DAG:
  - Bridge builder: dags/geo_bridge_ingestion.py
  - Airflow schedule: dags/domain_ingestion_dag.py
  - Gold transform: dags/hive_warehouse_transform.py

- Setup guide: README_SETUP.md

## Quick Run Commands

Host execution:

```powershell
python dags/crime_ingestion.py
python dags/census_ingestion.py
python dags/water_quality_ingestion.py
python dags/education_ingestion.py
python dags/geo_bridge_ingestion.py
/home/airflow/.local/bin/spark-submit --master spark://spark-master:7077 --deploy-mode client dags/hive_warehouse_transform.py --run-date 2026-04-23
```

Container execution:

```powershell
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/crime_ingestion.py
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/census_ingestion.py
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/water_quality_ingestion.py
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/education_ingestion.py
docker exec -it airflow-hdfs-airflow-webserver-1 python /opt/airflow/dags/geo_bridge_ingestion.py
docker exec -it airflow-hdfs-airflow-webserver-1 /home/airflow/.local/bin/spark-submit --master spark://spark-master:7077 --deploy-mode client /opt/airflow/dags/hive_warehouse_transform.py --run-date 2026-04-23
```

## Notes

- Output locations and schema details are documented in each dedicated README.
- Keep README_crime.md, README_census_2011.md, README_water_quality.md, and README_education_in_india.md as the source of truth for dataset-level fields and normalization logic.
- The shared state bridge is written to data/geo_bridge/ and is built from the latest state dimension outputs across crime, census, water, and education.
