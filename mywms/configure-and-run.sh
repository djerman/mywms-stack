#!/usr/bin/env bash
set -euo pipefail
JBOSS_HOME=${JBOSS_HOME:-/opt/jboss/wildfly}
DS_NAME=${DS_NAME:-PostgreSQLPool}
JNDI_NAME=${JNDI_NAME:-java:/losDS}
DB_PASSWORD=${DB_PASSWORD:-${DB_PASS:?DB_PASS is required}}

${JBOSS_HOME}/bin/standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0 &
until ${JBOSS_HOME}/bin/jboss-cli.sh --connect ":read-attribute(name=server-state)" | grep -q running; do sleep 1; done

DRIVER_DEPLOYMENT=${DRIVER_DEPLOYMENT:-postgresql-42.2.19.jar}
for i in {1..60}; do
  if ${JBOSS_HOME}/bin/jboss-cli.sh --connect "/subsystem=datasources/jdbc-driver=${DRIVER_DEPLOYMENT}:read-resource" | grep -q "outcome"; then
    break
  fi
  sleep 1
done

${JBOSS_HOME}/bin/jboss-cli.sh --connect <<EOF
if (outcome == success) of /subsystem=datasources/data-source=${DS_NAME}:read-resource; then
  /subsystem=datasources/data-source=${DS_NAME}:write-attribute(name=connection-url,value=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME})
  /subsystem=datasources/data-source=${DS_NAME}:write-attribute(name=user-name,value=${DB_USER})
  /subsystem=datasources/data-source=${DS_NAME}:write-attribute(name=password,value=${DB_PASSWORD})
  /subsystem=datasources/data-source=${DS_NAME}:write-attribute(name=driver-name,value=${DRIVER_DEPLOYMENT})
  :reload
else
  data-source add \
    --name=${DS_NAME} \
    --jndi-name=${JNDI_NAME} \
    --driver-name=${DRIVER_DEPLOYMENT} \
    --connection-url=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME} \
    --user-name=${DB_USER} \
    --password=${DB_PASSWORD} \
    --check-valid-connection-sql="SELECT 1" \
    --validate-on-match=true \
    --background-validation=false \
    --min-pool-size=2 \
    --max-pool-size=20
  :reload
end-if
EOF

wait -n
