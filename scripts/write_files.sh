#!/usr/bin/env bash
set -euo pipefail
ROOT=${1:-/opt/stacks/mywms-stack}

mkdir -p "$ROOT"/postgres/init \
         "$ROOT"/mywms-wildfly/{drivers,deployments} \
         "$ROOT"/reportserver/{webapp/reportserver,config,logs,lucene} \
         "$ROOT"/.github/workflows

# .env (DEV/PoC vrednosti — u produkciji zameni lozinke)
cat > "$ROOT/.env" <<'ENV'
TZ=Europe/Belgrade
DB_HOST=postgres
DB_PORT=5432
DB_NAME=mywms
DB_USER=mywms
DB_PASSWORD=mywms
DS_NAME=PostgreSQLPool
JNDI_NAME=java:/losDS
RS_DB_NAME=reportserver
RS_DB_USER=reportserver
RS_DB_PASSWORD=reportserver
ENV

# PostgreSQL init skripte
cat > "$ROOT/postgres/init/01-create-mywms.sql" <<'SQL1'
CREATE USER mywms WITH ENCRYPTED PASSWORD 'mywms';
CREATE DATABASE mywms OWNER mywms;
GRANT ALL PRIVILEGES ON DATABASE mywms TO mywms;
SQL1

cat > "$ROOT/postgres/init/02-create-reportserver.sql" <<'SQL2'
CREATE USER reportserver WITH ENCRYPTED PASSWORD 'reportserver';
CREATE DATABASE reportserver OWNER reportserver;
GRANT ALL PRIVILEGES ON DATABASE reportserver TO reportserver;
SQL2

# docker-compose.yml
cat > "$ROOT/docker-compose.yml" <<'COMPOSE'
version: "3.9"

services:
  postgres:
    image: postgres:13
    container_name: pg
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      TZ: ${TZ}
    volumes:
      - /srv/pgdata:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 15
    ports:
      - "5432:5432"

  mywms:
    build: ./mywms-wildfly
    container_name: mywms
    environment:
      TZ: ${TZ}
      DB_HOST: ${DB_HOST}
      DB_PORT: ${DB_PORT}
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DS_NAME: ${DS_NAME}
      JNDI_NAME: ${JNDI_NAME}
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8080:8080"
      - "9990:9990"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/ || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 15
    # volumes:
    #   - ./mywms-wildfly/deployments:/opt/jboss/wildfly/standalone/deployments

  reportserver:
    image: tomcat:9.0-jdk11
    container_name: reportserver
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8085:8080"
    environment:
      - TZ=${TZ}
      - JAVA_OPTS=-Xms1g -Xmx2g -Drs.configdir=/config -Drs.lucene.dir=/lucene_index -Djava.net.preferIPv4Stack=true
    volumes:
      - ./reportserver/webapp/reportserver:/usr/local/tomcat/webapps/reportserver:ro
      - ./reportserver/config:/config:ro
      - ./reportserver/logs:/usr/local/tomcat/logs
      - ./reportserver/lucene:/lucene_index
    restart: unless-stopped
COMPOSE

# Dockerfile
cat > "$ROOT/mywms-wildfly/Dockerfile" <<'DOCKERFILE'
ARG WF_IMAGE=quay.io/wildfly/wildfly:22.0.1.Final-jdk11
FROM ${WF_IMAGE}

ENV JBOSS_HOME=/opt/jboss/wildfly
COPY drivers/postgresql-42.2.19.jar ${JBOSS_HOME}/postgresql.jar
COPY deployments/ ${JBOSS_HOME}/standalone/deployments/
COPY configure-and-run.sh ${JBOSS_HOME}/bin/configure-and-run.sh
RUN chmod +x ${JBOSS_HOME}/bin/configure-and-run.sh
EXPOSE 8080 9990
ENTRYPOINT ["/opt/jboss/wildfly/bin/configure-and-run.sh"]
DOCKERFILE

# configure-and-run.sh
cat > "$ROOT/mywms-wildfly/configure-and-run.sh" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
JBOSS_HOME=${JBOSS_HOME:-/opt/jboss/wildfly}
DS_NAME=${DS_NAME:-PostgreSQLPool}
JNDI_NAME=${JNDI_NAME:-java:/losDS}
${JBOSS_HOME}/bin/standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0 &
until ${JBOSS_HOME}/bin/jboss-cli.sh --connect ":read-attribute(name=server-state)" | grep -q running; do sleep 1; done
${JBOSS_HOME}/bin/jboss-cli.sh --connect <<'EOF'
if (outcome != success) of /subsystem=datasources/jdbc-driver=postgresql:read-resource; then
  module add --name=org.postgresql --resources=/opt/jboss/wildfly/postgresql.jar --dependencies=javax.api,javax.transaction.api
  /subsystem=datasources/jdbc-driver=postgresql:add(driver-name=postgresql, driver-module-name=org.postgresql, driver-class-name=org.postgresql.Driver)
end-if
EOF
${JBOSS_HOME}/bin/jboss-cli.sh --connect <<EOF
if (outcome == success) of /subsystem=datasources/data-source=${DS_NAME}:read-resource; then
  /subsystem=datasources/data-source=${DS_NAME}:write-attribute(name=connection-url,value=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME})
  /subsystem=datasources/data-source=${DS_NAME}:write-attribute(name=user-name,value=${DB_USER})
  /subsystem=datasources/data-source=${DS_NAME}:write-attribute(name=password,value=${DB_PASSWORD})
  /subsystem=datasources/data-source=${DS_NAME}:write-attribute(name=driver-name,value=postgresql)
  :reload
else
  data-source add --name=${DS_NAME} --jndi-name=${JNDI_NAME} --driver-name=postgresql \
    --connection-url=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME} --user-name=${DB_USER} --password=${DB_PASSWORD} \
    --check-valid-connection-sql="SELECT 1" --validate-on-match=true --background-validation=false --min-pool-size=2 --max-pool-size=20
  :reload
end-if
EOF
wait -n
RUNNER
chmod +x "$ROOT/mywms-wildfly/configure-and-run.sh"

# ReportServer konfiguracija
cat > "$ROOT/reportserver/config/persistence.properties" <<'RSP1'
hibernate.connection.driver_class=org.postgresql.Driver
hibernate.connection.url=jdbc:postgresql://postgres:5432/reportserver
hibernate.connection.username=reportserver
hibernate.connection.password=reportserver
hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
RSP1

cat > "$ROOT/reportserver/config/reportserver.properties" <<'RSP2'
rs.configdir=/config
rs.baseurl=http://localhost:8085/reportserver
rs.scheduleThreads=2
logging.dir=/usr/local/tomcat/logs
RSP2

# README placeholdere
echo "Ovde ubaci postgresql JDBC drajver tacne verzije: postgresql-42.2.19.jar" > "$ROOT/mywms-wildfly/drivers/README.txt"
echo "Ovde ubaci tvoj mywms.ear (build koji želiš da pokrećeš u kontejneru)" > "$ROOT/mywms-wildfly/deployments/README.txt"
echo "Ovde ide ReportServer webapp (exploded) ili raspakovan .war" > "$ROOT/reportserver/webapp/reportserver/README.txt"

# GitHub Actions skeleton (.env.example i .gitignore po želji dodaj kasnije)
cat > "$ROOT/.github/workflows/deploy.yml" <<'WF'
name: Build & Deploy
on:
  push:
    branches: [ "main" ]
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ secrets.GHCR_USERNAME }}
          password: ${{ secrets.GHCR_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: ./mywms-wildfly
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/mywms:latest
            ghcr.io/${{ github.repository }}/mywms:${{ github.sha }}
WF

echo "[OK] Fajlovi su napisani u $ROOT. Dodaj mywms.ear, postgresql-42.2.19.jar i ReportServer webapp, pa: docker compose build && docker compose up -d"
