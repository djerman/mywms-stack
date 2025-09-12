#!/usr/bin/env bash
set -euo pipefail

# Idempotentno: preskoči ako već ima tabela u public šemi
if [ "$(psql -tAc "select count(*) from information_schema.tables where table_schema='public'")" != "0" ]; then
  echo "[rs_init] RS schema već postoji; preskačem import."
  exit 0
fi

# Nađi zvanični DDL
DDL="$(ls -1 /ddl/*PostgreSQL*_CREATE.sql | head -n1 || true)"
if [ -z "${DDL}" ]; then
  echo "[rs_init] Greška: DDL fajl nije pronađen u /ddl"
  exit 1
fi

echo "[rs_init] Uvozim DDL: ${DDL}"
psql -v ON_ERROR_STOP=1 -f "${DDL}"

echo "[rs_init] Podešavam vlasništvo i privilegije..."
psql -v ON_ERROR_STOP=1 \
  -c "ALTER DATABASE ${PGDATABASE} OWNER TO ${RS_USER};" \
  -c "ALTER SCHEMA public OWNER TO ${RS_USER};" \
  -c "GRANT USAGE ON SCHEMA public TO ${RS_USER};" \
  -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${RS_USER};" \
  -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${RS_USER};" \
  -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${RS_USER};" \
  -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${RS_USER};"

# Prenesi vlasništvo nad postojećim objektima
psql -Atc "SELECT 'ALTER TABLE '||quote_ident(schemaname)||'.'||quote_ident(tablename)||' OWNER TO ${RS_USER};' FROM pg_tables WHERE schemaname='public';" | psql
psql -Atc "SELECT 'ALTER SEQUENCE '||quote_ident(sequence_schema)||'.'||quote_ident(sequence_name)||' OWNER TO ${RS_USER};' FROM information_schema.sequences WHERE sequence_schema='public';" | psql

echo "[rs_init] Gotovo."
