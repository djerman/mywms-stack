# myWMS Stack deployment на Ubuntu 24.04 VPS

Овај документ бележи кораке који су проверено прошли при подизању `mywms-stack`
на новом Ubuntu 24.04 VPS серверу.

Тренутно покривено:
- припрема сервера
- Docker/Compose инсталација
- основни firewall и fail2ban
- чист PostgreSQL старт без myWMS dump-а
- ReportServer schema init
- старт myWMS-а на host порту `80`
- старт ReportServer-а на host порту `8085`
- основно SMTP подешавање ReportServer-а за промену иницијалне лозинке

За каснију допуну:
- основна myWMS подешавања након првог login-а
- backup/restore политика
- production hardening ReportServer config фајлова

## 1. Припрема сервера

Проверено на:

```bash
lsb_release -a
```

Очекивано:

```text
Distributor ID: Ubuntu
Description:    Ubuntu 24.04.x LTS
Release:        24.04
Codename:       noble
```

Инсталирани основни пакети:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg lsb-release git unzip htop ufw fail2ban
```

## 2. fail2ban за SSH

SSH jail је укључен у `/etc/fail2ban/jail.local`.

Проверено:

```bash
sudo fail2ban-client status sshd
```

Пример исправног стања:

```text
Status for the jail: sshd
Currently failed: 0
Currently banned: 0
```

Напомена: ово не ограничава приступ по фиксним IP адресама. Бан се активира
на основу неуспелих SSH покушаја.

## 3. Firewall

Минимално отворени портови:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 8085/tcp
sudo ufw enable
```

Проверено:

```bash
sudo ufw status verbose
```

Очекивано:

```text
Default: deny (incoming), allow (outgoing), deny (routed)
22/tcp     ALLOW IN
80/tcp     ALLOW IN
8085/tcp   ALLOW IN
```

Порт `5050` за pgAdmin није отворен подразумевано. Отворити га само по потреби.

## 4. Docker Engine и Docker Compose

Инсталација преко званичног Docker APT repo-а за Ubuntu `noble`:

```bash
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Проверено:

```bash
docker --version
docker compose version
sudo systemctl status docker --no-pager
```

## 5. Clone stack repo-а

Радни директоријум:

```bash
sudo mkdir -p /opt/mywms
cd /opt/mywms
git clone https://github.com/djerman/mywms-stack.git
cd /opt/mywms/mywms-stack
```

Проверити:

```bash
git status --short --branch
grep -n "MYWMS_HTTP" .env.example
docker compose config --quiet
```

`MYWMS_HTTP` треба да буде:

```env
MYWMS_HTTP=80
```

## 6. `.env`

Направити runtime `.env`:

```bash
cd /opt/mywms/mywms-stack
cp .env.example .env
nano .env
```

Обавезно променити лозинке:

```env
POSTGRES_PASSWORD=<јака_лозинка>
MYWMS_PASS=<јака_лозинка>
RS_PASS=<јака_лозинка>
```

Портови у провереној поставци:

```env
MYWMS_HTTP=80
RS_HTTP=8085
PGADMIN_HTTP=5050
```

PostgreSQL и WildFly management нису објављени на host портовима у
подразумеваном `docker-compose.yml`.

## 7. Runtime фајлови за WildFly

Deployment директоријум мора да садржи:

```text
mywms/deployments/mywms.ear
mywms/deployments/postgresql-42.2.19.jar
```

JDBC driver је копиран из repo-а:

```bash
cd /opt/mywms/mywms-stack
cp mywms/drivers/postgresql-42.2.19.jar mywms/deployments/postgresql-42.2.19.jar
```

`mywms.ear` је ручно пребачен на VPS у:

```text
/opt/mywms/mywms-stack/mywms/deployments/mywms.ear
```

Проверити:

```bash
ls -lah mywms/deployments/mywms.ear
ls -lah mywms/deployments/postgresql-42.2.19.jar
```

## 8. Чист PostgreSQL старт без myWMS dump-а

За нову инсталацију не убацивати `mywms` dump са подацима.

Пре првог старта проверити да у init директоријуму нема фајла `mywms`,
`mywms.dump`, `mywms.sql` или сличног seed dump-а:

```bash
cd /opt/mywms/mywms-stack
ls -lah postgres/init
```

За чисту инсталацију `postgres/init` треба да садржи само init скрипте и README,
без myWMS dump фајла.

Persistent директоријуми:

```bash
sudo mkdir -p /srv/pgadata /srv/pgbackup
ls -lah /srv/pgadata
ls -lah /srv/pgbackup
```

Ако је PostgreSQL претходно погрешно иницијализован, зауставити га и очистити
само на новом серверу где нема production података:

```bash
docker compose stop postgres
rm -rf /srv/pgadata/*
```

Старт PostgreSQL-а:

```bash
docker compose up -d postgres
docker compose ps postgres
docker compose logs postgres --tail=80
```

Очекивано у логовима:

```text
CREATE DATABASE mywms OWNER mywms
CREATE DATABASE reportserver OWNER reportserver
[INIT] Нема mywms (дамп) — прескачем иницијални увоз
PostgreSQL init process complete; ready for start up.
```

Проверити да PostgreSQL није изложен на host порту:

```bash
ss -ltnp | grep 5432 || true
```

Очекивано: нема излаза.

## 9. ReportServer schema init

Једнократно покренути:

```bash
docker compose run --rm rs_init
```

Проверити табеле:

```bash
docker exec pg psql -U postgres -d reportserver -c '\dt'
```

Очекивано: ReportServer табеле постоје и owner је `reportserver`.

## 10. myWMS старт

Покренути:

```bash
docker compose up -d mywms
docker compose ps mywms
docker compose logs mywms --tail=160
```

Очекивано у логовима:

```text
Bound data source [java:/losDS]
Create Users...
Create defaults...
Completed Setup
Deployed "mywms.ear"
WildFly Full 22.0.1.Final started
```

Проверено:

```bash
docker exec pg psql -U postgres -d mywms -c '\dt'
```

Очекивано: Hibernate креира myWMS табеле у празној бази.

Проверен приступ:

```text
http://SERVER/los-mobile
```

Login са подразумеваним корисником је прошао.

## 11. ReportServer старт

Покренути:

```bash
docker compose up -d reportserver
docker compose ps reportserver
docker compose logs reportserver --tail=120
```

Очекивано у логовима:

```text
Connection Test: OK
Schema Version: RS3.0-29
Server startup
Startup completed
```

HTTP провера:

```bash
curl -I http://127.0.0.1:8085/reportserver/
```

Очекивано:

```text
HTTP/1.1 200
```

## 12. Финална провера портова и container-а

```bash
docker compose ps
ss -ltnp | grep -E ':(80|8085|5050|5432|9990)\b' || true
```

Очекивано:

```text
0.0.0.0:80->8080/tcp      myWMS
0.0.0.0:8085->8080/tcp    ReportServer
```

Не треба да постоје host listener-и за:

```text
5432
9990
5050
```

У `docker compose ps` је прихватљиво да се виде container-only портови као
`5432/tcp` или `9990/tcp`, све док не постоји `0.0.0.0:PORT->...` mapping.

## 13. Основно ReportServer SMTP подешавање

Промена лозинке иницијалног/root корисника активира email notification hook.
Ако default Email SMTP datasink није исправно подешен, ReportServer враћа грешку:

```text
No default Email - SMTP server datasink configured
```

Проверено решење на овој инсталацији:

1. У ReportServer UI отворити:

```text
Administration -> Datasinks
```

2. Креирати или уредити Email SMTP datasink.

3. За datasink поставити key тачно на:

```text
DEFAULT_EMAIL_DATASINK
```

4. У ReportServer FileServer-у отворити:

```text
Administration -> File System -> FileServer Root -> etc -> datasinks -> datasinks.cf
```

5. У `datasinks.cf` поставити:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <email disabled="false" supportsScheduling="true">
    <defaultDatasinkKey>DEFAULT_EMAIL_DATASINK</defaultDatasinkKey>
  </email>
</configuration>
```

6. Сачувати измену и рестартовати ReportServer:

```bash
cd /opt/mywms/mywms-stack
docker compose restart reportserver
```

7. Након тога промена лозинке иницијалног/root корисника је прошла.

Напомена: очекивано би било да `datasinks.cf` може да референцира било који
постојећи Email SMTP datasink key. На овој инсталацији промена није прорадила
док key самог datasink-а није постављен баш на `DEFAULT_EMAIL_DATASINK`. Ово
треба касније додатно проверити, јер може указивати на cache/config reload
понашање или специфичност ReportServer baseconfig-а.

## 14. Тренутно отворене ставке

Ово није завршна production hardening листа. Треба допунити:

- основна myWMS подешавања након првог login-а
- додатна ReportServer admin подешавања након првог login-а
- разлог зашто default Email SMTP datasink није радио са произвољним key-ом
- ReportServer config фајлове који тренутно користе default вредности:
  - `ui/ui.cf`
  - `mail/mail.cf`
  - `scheduler/scheduler.cf`
  - `security/passwordpolicy.cf`
- backup cron/systemd timer
- поступак ажурирања `mywms.ear`
- поступак привременог подизања pgAdmin-а
