# myWMS Stack (PostgreSQL 16.9 + WildFly 22 + ReportServer CE)

> Production‑ready dockerized stack for myWMS and ReportServer.
> This repository contains compose files, Dockerfiles, configs and helper scripts.

## Contents
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Environment variables](#environment-variables)
- [Directory layout](#directory-layout)
- [Startup & shutdown](#startup--shutdown)
- [PostgreSQL schema import for ReportServer](#postgresql-schema-import-for-reportserver)
- [Updating `mywms.ear`](#updating-mywms-ear)
- [Backups & restore](#backups--restore)
- [Troubleshooting](#troubleshooting)
- [License & disclaimer](#license--disclaimer)

## Architecture
- **PostgreSQL 16.9** — databases: `mywms`, `reportserver`.
- **myWMS on WildFly 22 (JDK 11)** — local WF tree, `standalone.xml`, and `deployments/` with `mywms.ear` + `postgresql-42.2.19.jar`.
- **ReportServer CE (Tomcat 9 + JDK 11)** — unpacked `webapp/reportserver`, externalized configs in `reportserver/config/`.
- **Startup order:** `postgres` → (optional `rs_init`) → `mywms` + `reportserver`.

## Prerequisites
- Docker ≥ 24, Docker Compose v2
- Ubuntu 20.04/22.04/24.04 (or compatible)
- RAM: 8–16 GB, CPU: 2–4 vCPU recommended
- Host paths created: `/srv/pgadata`, `/srv/pgbackup` (owned by the Docker user)

## Quick start
```bash
cp .env.example .env
mkdir -p /srv/pgadata /srv/pgbackup && sudo chown -R $USER:$USER /srv/pgadata /srv/pgbackup

# 1) PostgreSQL
docker compose up -d postgres

# 2) (Optional) Import ReportServer schema once
docker compose run --rm rs_init

# 3) App containers
docker compose up -d mywms reportserver

# Health checks / logs
docker compose ps
docker compose logs -f postgres
docker compose logs -f mywms
docker compose logs -f reportserver
```

## Environment variables
| Key | Default | Description |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Superuser |
| `POSTGRES_PASSWORD` | `postgres` | Superuser password |
| `MYWMS_DB` | `mywms` | myWMS database name |
| `MYWMS_USER` | `mywms` | myWMS DB user |
| `MYWMS_PASS` | `mywms` | myWMS DB password |
| `RS_DB` | `reportserver` | ReportServer DB name |
| `RS_USER` | `reportserver` | ReportServer DB user |
| `RS_PASS` | `reportserver` | ReportServer DB password |
| `PG_PORT` | `5432` | Host port for PostgreSQL |
| `MYWMS_HTTP` | `8080` | Host port → WF HTTP |
| `MYWMS_MGMT` | `9990` | Host port → WF management |
| `RS_HTTP` | `8085` | Host port → Tomcat |
| `PGADMIN_HTTP` | `5050` | (If using pgAdmin container) |
| `PG_HOST_DATA` | `/srv/pgadata` | Host volume for PGDATA |
| `PG_HOST_BACKUP` | `/srv/pgbackup` | Host volume for dumps |

## Directory layout
```
mywms-stack/
├─ .env
├─ docker-compose.yml
├─ postgres/
│  ├─ conf/{pg_hba.conf, postgresql.conf}
│  └─ init/{01-create-db-users.sql, 02-load-mywms.sh, rs_post_init.sql}
├─ mywms/
│  ├─ Dockerfile
│  ├─ standalone.xml
│  └─ deployments/{mywms.ear, postgresql-42.2.19.jar}
└─ reportserver/
   ├─ Dockerfile
   ├─ webapp/reportserver/…
   └─ config/{persistence.properties, reportserver.properties}
```

## Startup & shutdown
```bash
# Up
docker compose up -d postgres
docker compose run --rm rs_init    # once
docker compose up -d mywms reportserver

# Down (reverse order)
docker compose stop reportserver mywms
docker compose stop postgres
```

## PostgreSQL schema import for ReportServer
The `rs_init` one-shot service runs the official DDL:
- `reportserver/webapp/reportserver/ddl/reportserver-RS4.7.7-6117-schema-PostgreSQL_CREATE.sql`
- plus grants from `postgres/init/rs_post_init.sql`

Re-run on a fresh database if needed:
```bash
docker compose run --rm rs_init
```

## Updating `mywms.ear`
```bash
cp NEW_mywms.ear mywms/deployments/mywms.ear
touch mywms/deployments/mywms.ear.dodeploy
docker compose restart mywms
```

## Backups & restore
Use scripts under `postgres/backup/` (mounted to `/backups` in the PG container).
```bash
# Full example
docker exec -it pg bash -lc '/backups/backup-all.sh'
# Restore mywms
docker exec -it pg bash -lc '/backups/restore-mywms.sh /backups/mywms_YYYY-MM-DD_HHMMSS.dump'
```

## Troubleshooting
- Verify `.env` and `docker-compose.yml` values.
- If RS says “permission denied” on tables, re-apply grants (`postgres/init/rs_post_init.sql`).
- For Jasper Cyrillic PDFs: make sure `fonts/ttf/DejaVuSans*.ttf`, `fonts/dejavu.xml`, and Jasper extension properties exist inside the container; then restart RS and clear Tomcat work/temp.

## License & disclaimer
This example is provided **AS IS**, without warranties. Review and harden before production (users/roles, `pg_hba.conf`, secrets, network policies, backups, monitoring).
