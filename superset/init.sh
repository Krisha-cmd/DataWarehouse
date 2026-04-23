#!/bin/bash
set -e

superset db upgrade

superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@admin.com \
    --password admin || true

superset init

echo "superset-init-done"
