-- Runs automatically on first postgres container start (empty data volume).
-- If postgres already has data, run these manually — see README_SETUP.md.

-- Hive metastore database
CREATE USER hive WITH PASSWORD 'hive';
CREATE DATABASE hive_metastore OWNER hive;
GRANT ALL PRIVILEGES ON DATABASE hive_metastore TO hive;

-- Superset metadata database
CREATE USER superset WITH PASSWORD 'superset';
CREATE DATABASE superset OWNER superset;
GRANT ALL PRIVILEGES ON DATABASE superset TO superset;
