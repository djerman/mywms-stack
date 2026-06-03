#!/usr/bin/env bash
set -euo pipefail

: "${DB_HOST:=pg}"
: "${DB_PORT:=5432}"
: "${RS_DB:?RS_DB is required}"
: "${RS_USER:?RS_USER is required}"
: "${RS_PASS:?RS_PASS is required}"

mkdir -p /runtime-config
cp -a /config/. /runtime-config/

cat > /runtime-config/persistence.properties <<EOF
hibernate.dialect=net.datenwerke.rs.utils.hibernate.PostgreSQLDialect
hibernate.connection.driver_class=org.postgresql.Driver
hibernate.connection.url=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${RS_DB}
hibernate.connection.username=${RS_USER}
hibernate.connection.password=${RS_PASS}
hibernate.connection.autocommit=false
EOF

exec "$@"
