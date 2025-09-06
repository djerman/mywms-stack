#!/usr/bin/env bash
set -euo pipefail

DB="${MYWMS_DB:-mywms}"
SRC=""

# Пронађи дамп: без екстензије, *.sql, *.dump, *.backup, *.gz
for f in \
  /docker-entrypoint-initdb.d/mywms \
  /docker-entrypoint-initdb.d/mywms.*; do
  if [ -e "$f" ]; then SRC="$f"; break; fi
done

if [ -z "$SRC" ]; then
  echo "[INIT] Нема mywms (дамп) — прескачем иницијални увоз"
  exit 0
fi

echo "[INIT] Утврђујем формат дампа: $SRC"
MAGIC="$(head -c 5 "$SRC" 2>/dev/null || true)"

if [ "$MAGIC" = "PGDMP" ]; then
  echo "[INIT] Детектован PostgreSQL custom dump → pg_restore --no-owner --no-privileges --role=${MYWMS_USER:-mywms}"
  pg_restore -U "$POSTGRES_USER" -d "$DB" \
    --no-owner --no-privileges --role="${MYWMS_USER:-mywms}" \
    "$SRC"
else
  case "$SRC" in
    *.gz)
      echo "[INIT] ГЗ компресован SQL → gunzip | psql"
      gunzip -c "$SRC" | psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB"
      ;;
    *)
      echo "[INIT] Обичан SQL → psql -f"
      psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" -f "$SRC"
      ;;
  esac
fi

# Привилегије за апликационог корисника
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" -c "ALTER SCHEMA public OWNER TO ${MYWMS_USER:-mywms};"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" -c "REVOKE ALL ON DATABASE $DB FROM PUBLIC; GRANT ALL ON DATABASE $DB TO ${MYWMS_USER:-mywms};"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${MYWMS_USER:-mywms};"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${MYWMS_USER:-mywms};"

# Подразумеване привилегије за нове објекте
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" -c "ALTER DEFAULT PRIVILEGES FOR ROLE ${MYWMS_USER:-mywms} IN SCHEMA public GRANT ALL ON TABLES TO ${MYWMS_USER:-mywms};"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB" -c "ALTER DEFAULT PRIVILEGES FOR ROLE ${MYWMS_USER:-mywms} IN SCHEMA public GRANT ALL ON SEQUENCES TO ${MYWMS_USER:-mywms};"

