-- =====================================================================
-- warehouse_gold_ddl.hql
-- ---------------------------------------------------------------------
-- Hive DDL for the gold-layer star schema produced by
-- hive_warehouse_transform.py.
--
-- Running this file is OPTIONAL. The Spark job calls
-- `saveAsTable(...)`, which registers each table on first write, so a
-- clean environment can skip this script entirely.
--
-- Run it explicitly when you want:
--   - to pre-create the database before the first ingestion,
--   - to enforce column types and partitioning independently of Spark,
--   - to grant table-level privileges before any data lands.
--
-- All tables are STORED AS PARQUET and point at an HDFS location under
-- /warehouse/gold so they survive `DROP TABLE` (external tables).
-- =====================================================================

CREATE DATABASE IF NOT EXISTS warehouse_gold
COMMENT 'Gold-layer star schema: conformed dimensions + domain fact tables'
LOCATION '/warehouse/gold';

USE warehouse_gold;

-- =====================================================================
-- Conformed dimensions
-- =====================================================================

CREATE EXTERNAL TABLE IF NOT EXISTS dim_state (
    state_key           BIGINT    COMMENT 'Surrogate key (xxhash64 of canonical state name)',
    state_name          STRING    COMMENT 'Canonical state/UT name',
    state_code          STRING    COMMENT 'First-3-letter code derived from name',
    is_union_territory  BOOLEAN,
    effective_from      DATE,
    effective_to        DATE      COMMENT 'SCD-1: fixed at 9999-12-31 for all rows',
    is_current          BOOLEAN,
    etl_run_date        DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_state'
TBLPROPERTIES ('scd_type' = '1', 'conformed' = 'true');


CREATE EXTERNAL TABLE IF NOT EXISTS dim_district (
    district_key     BIGINT,
    district_name    STRING,
    district_code    STRING,
    state_key        BIGINT    COMMENT 'FK -> dim_state.state_key',
    state_name       STRING,
    effective_from   DATE,
    effective_to     DATE,
    is_current       BOOLEAN,
    etl_run_date     DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_district'
TBLPROPERTIES (
    'scd_type'       = '2',
    'conformed'      = 'true',
    'scd_notes'      = 'Closes old rows on Telangana 2014 split and Ladakh 2019 split via separate MERGE job'
);


CREATE EXTERNAL TABLE IF NOT EXISTS dim_date (
    calendar_date         DATE,
    date_key              INT       COMMENT 'Integer yyyyMMdd form',
    year                  INT,
    quarter               INT,
    month                 INT,
    day_of_month          INT,
    day_of_week           INT,
    fiscal_year_india     INT       COMMENT 'India fiscal year (Apr-Mar)',
    fiscal_quarter_india  INT,
    academic_year_start   INT       COMMENT 'School academic year start (Jul-Jun)',
    academic_year_label   STRING    COMMENT 'e.g. "2015-16"',
    is_weekend            BOOLEAN,
    etl_run_date          DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_date';


CREATE EXTERNAL TABLE IF NOT EXISTS dim_age_group (
    age_group_key    STRING,
    age_group_label  STRING,
    age_lower        INT,
    age_upper        INT,
    source_domain    STRING,
    etl_run_date     DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_age_group';


CREATE EXTERNAL TABLE IF NOT EXISTS dim_gender (
    gender_key    STRING,
    gender_label  STRING,
    etl_run_date  DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_gender';


CREATE EXTERNAL TABLE IF NOT EXISTS dim_education_level (
    education_level_key    STRING,
    education_level_label  STRING,
    ordinal                INT,
    etl_run_date           DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_education_level';


CREATE EXTERNAL TABLE IF NOT EXISTS dim_metric (
    metric_key    BIGINT,
    metric_code   STRING    COMMENT 'Raw metric name from source',
    domain        STRING    COMMENT 'Owning domain: crime / census / water_quality / education',
    unit          STRING,
    description   STRING,
    etl_run_date  DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_metric';


CREATE EXTERNAL TABLE IF NOT EXISTS dim_source_system (
    source_system_key  STRING,
    domain             STRING,
    description        STRING,
    schema_version     STRING,
    last_ingested_on   DATE,
    etl_run_date       DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_source_system';


CREATE EXTERNAL TABLE IF NOT EXISTS dim_water_station (
    station_key             BIGINT,
    station_code            STRING,
    monitoring_location     STRING,
    water_body_type         STRING,
    state_key               BIGINT,
    canonical_state_name    STRING,
    etl_run_date            DATE
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_water_station';


CREATE EXTERNAL TABLE IF NOT EXISTS dim_census_geography (
    state_code_2011     STRING,
    district_code       STRING,
    subdistt_code       STRING,
    town_village_code   STRING,
    ward_code           STRING,
    eb_code             STRING,
    level               STRING,
    geo_name            STRING,
    tru                 STRING,
    canonical_state_name STRING,
    state_key           BIGINT
)
STORED AS PARQUET
LOCATION '/warehouse/gold/dim_census_geography';


-- =====================================================================
-- Fact tables (all partitioned by year)
-- =====================================================================

CREATE EXTERNAL TABLE IF NOT EXISTS fact_crime_incident (
    incident_key        BIGINT,
    state_key           BIGINT,
    date_key            INT,
    incident_date       DATE,
    raw_state_name      STRING,
    city                STRING,
    crime_description   STRING,
    crime_code          STRING,
    victim_gender       STRING,
    victim_age          INT,
    weapon_used         STRING,
    crime_domain        STRING,
    police_deployed     INT,
    case_closed         STRING,
    source_system_key   STRING,
    etl_inserted_at     TIMESTAMP
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION '/warehouse/gold/fact_crime_incident';


CREATE EXTERNAL TABLE IF NOT EXISTS fact_inmate_population (
    inmate_fact_key        BIGINT,
    state_key              BIGINT,
    inmate_status          STRING    COMMENT 'ADMITTED / UNDERTRIAL / CONVICT / DETENUE / FEMALE_INMATE',
    gender_key             STRING,
    age_group_key          STRING,
    education_level_key    STRING,
    category               STRING,
    metric_value           DOUBLE,
    metric_unit            STRING,
    source_table           STRING,
    source_system_key      STRING,
    etl_inserted_at        TIMESTAMP
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION '/warehouse/gold/fact_inmate_population';


CREATE EXTERNAL TABLE IF NOT EXISTS fact_literacy_rate (
    literacy_rate_key  BIGINT,
    state_key          BIGINT,
    literacy_rate      DOUBLE,
    unit               STRING,
    source_system_key  STRING,
    etl_inserted_at    TIMESTAMP
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION '/warehouse/gold/fact_literacy_rate';


CREATE EXTERNAL TABLE IF NOT EXISTS fact_population (
    population_fact_key  BIGINT,
    state_key            BIGINT,
    district_code        STRING,
    geo_level            STRING,
    total_rural_urban    STRING,
    geo_name             STRING,
    metric_code          STRING,
    gender_key           STRING,
    metric_value         DOUBLE,
    source_system_key    STRING,
    etl_inserted_at      TIMESTAMP
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION '/warehouse/gold/fact_population';


CREATE EXTERNAL TABLE IF NOT EXISTS fact_workforce (
    population_fact_key  BIGINT,
    state_key            BIGINT,
    district_code        STRING,
    geo_level            STRING,
    total_rural_urban    STRING,
    geo_name             STRING,
    metric_code          STRING,
    gender_key           STRING,
    metric_value         DOUBLE,
    source_system_key    STRING,
    etl_inserted_at      TIMESTAMP
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION '/warehouse/gold/fact_workforce';


CREATE EXTERNAL TABLE IF NOT EXISTS fact_water_measurement (
    measurement_key   BIGINT,
    station_key       BIGINT,
    state_key         BIGINT,
    parameter_code    STRING,
    min_value         DOUBLE,
    max_value         DOUBLE,
    measure_unit      STRING,
    source_system_key STRING,
    etl_inserted_at   TIMESTAMP
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION '/warehouse/gold/fact_water_measurement';


CREATE EXTERNAL TABLE IF NOT EXISTS fact_education_indicator (
    education_fact_key   BIGINT,
    state_key            BIGINT,
    district_code        STRING,
    geo_grain            STRING    COMMENT 'state | district',
    academic_year        STRING,
    metric_code          STRING,
    metric_value         DOUBLE,
    source_file          STRING,
    source_system_kind   STRING,
    source_system_key    STRING,
    etl_inserted_at      TIMESTAMP
)
PARTITIONED BY (year INT)
STORED AS PARQUET
LOCATION '/warehouse/gold/fact_education_indicator';

-- =====================================================================
-- Useful analytical views (optional)
-- =====================================================================

CREATE OR REPLACE VIEW vw_state_year_population AS
SELECT
    s.state_name,
    p.year,
    SUM(CASE WHEN p.gender_key = 'P' AND p.metric_code = 'total_population'
             AND p.geo_level = 'STATE' AND p.total_rural_urban = 'Total'
             THEN p.metric_value END) AS total_population,
    SUM(CASE WHEN p.gender_key = 'M' AND p.metric_code = 'total_population'
             AND p.geo_level = 'STATE' AND p.total_rural_urban = 'Total'
             THEN p.metric_value END) AS male_population,
    SUM(CASE WHEN p.gender_key = 'F' AND p.metric_code = 'total_population'
             AND p.geo_level = 'STATE' AND p.total_rural_urban = 'Total'
             THEN p.metric_value END) AS female_population
FROM fact_population p
JOIN dim_state s ON s.state_key = p.state_key
GROUP BY s.state_name, p.year;
