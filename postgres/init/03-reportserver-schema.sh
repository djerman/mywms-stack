#!/usr/bin/env bash
set -euo pipefail

DB="${RS_DB:-reportserver}"
DDL_DIR="/reportserver_ddl"

# Ако већ постоји бар једна RS табела, прескочи
EXISTS=$(psql -U "$POSTGRES_USER" -d "$DB" -Atc "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND LOWER(table_name)='rs_ace' LIMIT 1;" || true)
if [ "${EXISTS}" = "1" ]; then
  echo "[INIT] ReportServer шема већ постоји — прескачем"
  exit 0
fi

SQL=$(ls -1 ${DDL_DIR}/*-schema-PostgreSQL_CREATE.sql 2>/dev/null | head -n1 || true)
if [ -z "${SQL}" ]; then
  echo "[INIT] Нема CREATE .sql у ${DDL_DIR} — прескачем"
  exit 0
fi

echo "[INIT] Креирам ReportServer шему из: ${SQL}"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" -f "$SQL"
