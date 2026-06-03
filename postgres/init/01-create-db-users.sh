#!/usr/bin/env bash
set -euo pipefail

require_identifier() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "[INIT] Invalid SQL identifier for ${name}: ${value}" >&2
    exit 1
  fi
}

sql_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${MYWMS_DB:?MYWMS_DB is required}"
: "${MYWMS_USER:?MYWMS_USER is required}"
: "${MYWMS_PASS:?MYWMS_PASS is required}"
: "${RS_DB:?RS_DB is required}"
: "${RS_USER:?RS_USER is required}"
: "${RS_PASS:?RS_PASS is required}"

require_identifier "MYWMS_DB" "$MYWMS_DB"
require_identifier "MYWMS_USER" "$MYWMS_USER"
require_identifier "RS_DB" "$RS_DB"
require_identifier "RS_USER" "$RS_USER"

MYWMS_PASS_SQL="$(sql_literal "$MYWMS_PASS")"
RS_PASS_SQL="$(sql_literal "$RS_PASS")"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${MYWMS_USER}') THEN
      CREATE ROLE ${MYWMS_USER} LOGIN PASSWORD '${MYWMS_PASS_SQL}';
   ELSE
      ALTER ROLE ${MYWMS_USER} WITH PASSWORD '${MYWMS_PASS_SQL}';
   END IF;

   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${RS_USER}') THEN
      CREATE ROLE ${RS_USER} LOGIN PASSWORD '${RS_PASS_SQL}';
   ELSE
      ALTER ROLE ${RS_USER} WITH PASSWORD '${RS_PASS_SQL}';
   END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${MYWMS_DB} OWNER ${MYWMS_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${MYWMS_DB}');
\gexec

SELECT 'CREATE DATABASE ${RS_DB} OWNER ${RS_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${RS_DB}');
\gexec
SQL
