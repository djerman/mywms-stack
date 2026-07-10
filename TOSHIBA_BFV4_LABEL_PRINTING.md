# TOSHIBA B-FV4 штампање myWMS етикета

Овај документ описује проверено production подешавање за штампање myWMS етикета
на мрежном штампачу `TOSHIBA B-FV4` преко Docker myWMS сервера.

Проверена комбинација:

- штампач: `TOSHIBA B-FV4`, 203 dpi
- IP адреса: `192.168.1.5`
- TCP порт: `9100`
- emulation mode на штампачу: `TPCL`
- CUPS queue: `TOSHIBA_BFV4_203_TPCL`
- myWMS Docker container: `mywms`
- приступ штампачу из myWMS-а: преко host CUPS socket-а
- myWMS параметар за ручну штампу пријемних етикета:
  `cmd:/usr/bin/lp -d TOSHIBA_BFV4_203_TPCL :file:`

Не користити `Z Mode` за овај штампач у овом окружењу, јер је тестом утврђено
да ремети постојеће директно Windows штампање преко Toshiba driver-а.

## 1. Архитектура решења

myWMS етикете при пријему робе штампају се серверски:

1. NetBeans/RCP клијент покрене штампу из Goods Receipt процеса.
2. myWMS сервер генерише PDF етикету преко Jasper извештаја `StockUnitLabel`.
3. myWMS сервер позива команду из системског параметра.
4. Команда `lp` шаље PDF у CUPS queue на production серверу.
5. CUPS преко Toshiba TEC driver-а шаље посао на мрежни штампач
   `socket://192.168.1.5:9100`.

Због тога штампач мора бити доступан са production сервера, не са корисничког
рачунара на ком је покренут NetBeans/RCP клијент.

## 2. Провера мрежне доступности штампача

На production серверу проверити да је порт `9100` доступан:

```bash
nc -vz 192.168.1.5 9100
```

Очекиван резултат:

```text
Connection to 192.168.1.5 9100 port [tcp/*] succeeded!
```

Ако ова провера не пролази, CUPS и myWMS не могу стабилно да штампају. Прво
решити IP адресу, VLAN/firewall, кабл или switch.

## 3. CUPS и Toshiba driver

На production серверу морају бити доступни CUPS алати:

```bash
apt update
apt install -y cups cups-client
systemctl enable --now cups
```

За овај штампач потребан је Toshiba TEC driver пакет:

```text
toshiba-tec-barcode-printer-drivers_2.09_debian_amd64.deb
```

Инсталација:

```bash
cd /home/vukohem/Package_Files_V2.09
apt install ./toshiba-tec-barcode-printer-drivers_2.09_debian_amd64.deb
```

Ако се користи `dpkg -i`, после тога по потреби покренути:

```bash
apt -f install
```

Проверити да је driver регистрован у CUPS-у:

```bash
lpinfo -m | grep -Ei 'toshiba|tec|b-fv|bfv|barcode'
```

Очекивано је да постоје PPD модели:

```text
ToshibaTEC_B-FV4-G.ppd TOSHIBA B-FV4-G
ToshibaTEC_B-FV4-T.ppd TOSHIBA B-FV4-T
```

У овом окружењу користи се:

```text
ToshibaTEC_B-FV4-T.ppd
```

## 4. Креирање CUPS queue-а

Креирати queue:

```bash
lpadmin -p TOSHIBA_BFV4_203_TPCL -E \
  -v socket://192.168.1.5:9100 \
  -m ToshibaTEC_B-FV4-T.ppd
```

CUPS може приказати упозорење да су printer drivers deprecated. То није грешка
за тренутну Ubuntu/CUPS верзију и ова комбинација је проверено радила.

Проверити queue:

```bash
lpstat -p TOSHIBA_BFV4_203_TPCL
lpstat -v TOSHIBA_BFV4_203_TPCL
```

Очекивано:

```text
printer TOSHIBA_BFV4_203_TPCL is idle
device for TOSHIBA_BFV4_203_TPCL: socket://192.168.1.5:9100
```

## 5. Подешавање формата налепнице

Налепница која је коришћена при тестирању је приближно `100x50 mm`.

Поставити проверене CUPS опције:

```bash
lpadmin -p TOSHIBA_BFV4_203_TPCL \
  -o PageSize=2x4Rotated.FullBleed \
  -o Sensor=Transmissive \
  -o LabelGap=20
```

Проверити активне вредности:

```bash
lpoptions -p TOSHIBA_BFV4_203_TPCL -l | grep -E 'PageSize|Sensor|LabelGap'
```

Очекивано:

```text
PageSize/Media Size: ... *2x4Rotated.FullBleed ...
Sensor/Sensor: None Reflective *Transmissive
LabelGap/Label-to-label gap: *20 ...
```

Напомена: не мењати остале опције ако штампа ради. Посебно не мењати emulation
mode на `Z Mode`, јер је у тесту утврђено да тај режим није компатибилан са
постојећим директним Windows штампањем.

## 6. Docker stack подршка за CUPS

myWMS image мора да садржи CUPS client алате. У `mywms/Dockerfile` је зато
додато:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends cups-client \
    && rm -rf /var/lib/apt/lists/*
```

Host CUPS runtime директоријум се у myWMS container прослеђује преко override
compose фајла `docker-compose.printing.yml`:

```yaml
services:
  mywms:
    volumes:
      - /var/run/cups:/var/run/cups
```

Намерно се mount-ује цео `/var/run/cups` директоријум, а не конкретан
`cups.sock` фајл. Host CUPS може после restart-а да поново креира socket са
новим inode-ом; ако је у container mount-ован само стари socket фајл, `lpstat`
у container-у може да врати `Scheduler is not running` иако CUPS на host-у ради.

Сервери који немају штампач не морају да користе овај override. Основни
`docker-compose.yml` остаје исти за све сервере.

## 7. Покретање production stack-а са штампом

На серверу који користи штампање:

```bash
cd /opt/stacks/mywms-stack
git pull
docker compose -f docker-compose.yml -f docker-compose.printing.yml build mywms
docker compose -f docker-compose.yml -f docker-compose.printing.yml up -d mywms
```

Ако су и остали сервиси угашени или је потребан комплетан restart:

```bash
docker compose -f docker-compose.yml -f docker-compose.printing.yml up -d
```

Сервер без штампача покреће се стандардно, без override фајла:

```bash
docker compose up -d
```

## 8. Провера из Docker container-а

Проверити да container види CUPS runtime mount:

```bash
docker inspect mywms --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' | grep cups
```

Очекивано:

```text
/var/run/cups -> /var/run/cups
```

Проверити да container види CUPS queue:

```bash
docker exec -it mywms which lp
docker exec -it mywms lpstat -p
docker exec -it mywms lpstat -v TOSHIBA_BFV4_203_TPCL
```

Очекивано је да се види:

```text
printer TOSHIBA_BFV4_203_TPCL is idle
device for TOSHIBA_BFV4_203_TPCL: socket://192.168.1.5:9100
```

Ако `lpstat` у container-у врати `Scheduler is not running`, container најчешће
не види host CUPS runtime директоријум или је myWMS покренут без
`docker-compose.printing.yml`.

## 9. myWMS системска својства

У NetBeans/RCP клијенту отворити системска својства и подесити:

```text
Кључ: GOODS_RECEIPT_PRINT_LABEL
Вредност: false
```

Ово држи аутоматску штампу искљученом. Ручна штампа из Goods Receipt процеса и
даље ради.

За штампач подесити:

```text
Кључ: GOODS_RECEIPT_PRINTER_NAME
Контекст: DEFAULT
Вредност: cmd:/usr/bin/lp -d TOSHIBA_BFV4_203_TPCL :file:
Група: NB
```

Ако се штампач касније буде разликовао по радној станици, могуће је уместо
`DEFAULT` користити конкретан workstation контекст, али проверена production
поставка је била `DEFAULT`.

Важно: за ову Docker/CUPS поставку користи се `cmd:` вредност, не `prn:`.
Разлог је што myWMS генерише PDF, а команда `lp` га предаје host CUPS-у који
зна Toshiba driver и queue.

## 10. Jasper шаблон етикете

Подразумевани myWMS шаблон је:

```text
mywms/dev/wms2-ejb/src/main/resources/reports/StockUnitLabel.jrxml
```

Тај фајл не треба мењати за production upload.

Прилагођена копија за Vukohem налепнице налази се у радном фолдеру:

```text
Izvestaji/StockUnitLabel_100x50_Vukohem.jrxml
```

Ова копија је прилагођена за налепнице приближно `100x50 mm` и користи:

- QR код за ознаку товарне јединице
- поља `Oznaka`, `Datum`, `Artikal`, `Lot`, `Naziv`
- латиничне називе поља, да би се избегли encoding проблеми при upload-у
  JRXML-а кроз NetBeans/RCP клијент
- сужено поље `Naziv`, да би Jasper преломио дужи назив унутар реалне ширине
  налепнице

Шаблон се учитава кроз NetBeans/RCP клијент:

1. Отворити `Jasper Reports`.
2. Наћи извештај `StockUnitLabel`.
3. Учитај JRXML фајл.
4. Изабрати `Izvestaji/StockUnitLabel_100x50_Vukohem.jrxml`.
5. Покренути компајлирање ако није аутоматски урађено.
6. Проверити да је верзија активна за одговарајућег клијента.

## 11. Контролни тестови

### 11.1 CUPS queue тест

Провера да CUPS прихвата посао:

```bash
lp -d TOSHIBA_BFV4_203_TPCL /usr/share/cups/data/default-testpage.pdf
lpstat -W completed -o TOSHIBA_BFV4_203_TPCL | tail -n 5
```

Овај тест служи само за проверу путање сервер -> CUPS -> штампач. Изглед
штампе не мора бити смислен за малу налепницу.

### 11.2 myWMS container тест

Провера да container види исти queue:

```bash
docker exec -it mywms lpstat -p TOSHIBA_BFV4_203_TPCL
docker exec -it mywms lpstat -v TOSHIBA_BFV4_203_TPCL
```

### 11.3 Апликативни тест

Најважнији тест је ручна штампа из Goods Receipt процеса у NetBeans/RCP
клијенту, јер тај пут проверава све:

- Jasper шаблон
- myWMS параметар `GOODS_RECEIPT_PRINTER_NAME`
- `cmd:/usr/bin/lp ... :file:`
- Docker container приступ CUPS-у
- CUPS Toshiba driver
- мрежни штампач

## 12. Дијагностика

### Штампач не постоји у container-у

Симптом:

```text
lpstat: Scheduler is not running.
```

Проверити:

```bash
docker inspect mywms --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' | grep cups
docker compose -f docker-compose.yml -f docker-compose.printing.yml up -d mywms
```

### Queue не постоји на host-у

Проверити:

```bash
lpstat -p
lpinfo -v | grep 192.168.1.5
```

### Посао стоји у queue-у

Проверити активне и завршене послове:

```bash
lpstat -o TOSHIBA_BFV4_203_TPCL
lpstat -W completed -o TOSHIBA_BFV4_203_TPCL | tail -n 10
lpstat -p TOSHIBA_BFV4_203_TPCL
```

Отказивање свих послова за queue:

```bash
cancel -a TOSHIBA_BFV4_203_TPCL
```

Ово користити пажљиво, само када је јасно да су послови заглављени или погрешни.

### Ништа не излази на штампач

Проверити редом:

1. `nc -vz 192.168.1.5 9100`
2. `lpstat -v TOSHIBA_BFV4_203_TPCL`
3. да је Toshiba driver инсталиран
4. да је queue направљен са `ToshibaTEC_B-FV4-T.ppd`
5. да је штампач у `TPCL` emulation mode-у
6. да myWMS container види CUPS runtime mount
7. да је myWMS параметар тачно:
   `cmd:/usr/bin/lp -d TOSHIBA_BFV4_203_TPCL :file:`

### Ћирилица у JRXML-у излази као погрешни знакови

У овом окружењу је утврђено да директан UTF-8 текст у JRXML-у може бити
проблематичан при upload-у кроз NetBeans/RCP клијент. Зато је проверена
практична варијанта да називи поља на етикети буду латиницом:

```text
Oznaka, Datum, Artikal, Lot, Naziv
```

## 13. Оперативна напомена после restart-а CUPS-а или rebuild-а container-а

Ако је myWMS container покренут са `docker-compose.printing.yml`, али штампа
после restart-а/rebuild-а не ради, прво проверити CUPS из container-а:

```bash
docker exec -it mywms lpstat -p
```

Ако команда врати:

```text
lpstat: Scheduler is not running.
```

а host CUPS ради:

```bash
systemctl status cups --no-pager
```

најчешћи узрок је да container не види активан host CUPS runtime директоријум.
Override мора да mount-ује директоријум `/var/run/cups:/var/run/cups`, а не
само фајл `/var/run/cups/cups.sock`.

Проверити override:

```bash
cd /opt/stacks/mywms-stack
cat docker-compose.printing.yml
```

Исправан садржај:

```yaml
services:
  mywms:
    volumes:
      - /var/run/cups:/var/run/cups
```

После измене override-а поново креирати само `mywms` container:

```bash
cd /opt/stacks/mywms-stack
docker compose -f docker-compose.yml -f docker-compose.printing.yml up -d --force-recreate mywms
```

После recreate-а обавезно проверити:

```bash
docker inspect mywms --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' | grep cups
docker exec -it mywms lpstat -p
docker exec -it mywms lpstat -v TOSHIBA_BFV4_203_TPCL
```

Очекивано је да mount буде:

```text
/var/run/cups -> /var/run/cups
```

Ако је потребно само хитно враћање штампе пре измене override-а, може се
привремено restart-овати container:

```bash
cd /opt/stacks/mywms-stack
docker compose -f docker-compose.yml -f docker-compose.printing.yml restart mywms
```

То не дира PostgreSQL нити податке, али није трајно решење ако override и даље
mount-ује само `cups.sock`.

Препоручена провера после сваког deploy-а на серверу који користи штампу:

```bash
cd /opt/stacks/mywms-stack
docker exec -it mywms lpstat -p
```

Ако се добије списак штампача, Docker/CUPS део је спреман за myWMS штампу.

## 14. Резиме проверене production поставке

Минимални скуп који мора бити тачан:

```text
Printer IP: 192.168.1.5
Printer port: 9100
Printer emulation: TPCL
CUPS queue: TOSHIBA_BFV4_203_TPCL
CUPS device: socket://192.168.1.5:9100
CUPS driver: ToshibaTEC_B-FV4-T.ppd
CUPS PageSize: 2x4Rotated.FullBleed
CUPS Sensor: Transmissive
CUPS LabelGap: 20
Docker override: docker-compose.printing.yml
Container mount: /var/run/cups:/var/run/cups
myWMS printer value: cmd:/usr/bin/lp -d TOSHIBA_BFV4_203_TPCL :file:
Jasper template: Izvestaji/StockUnitLabel_100x50_Vukohem.jrxml
```
