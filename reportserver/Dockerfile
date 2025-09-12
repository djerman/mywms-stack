FROM tomcat:9.0-jdk11-temurin

# Конфигурација ReportServer-а (мапира се и као volume у compose-у)
COPY config /config

# РАСПАКОВАНА веб-апликација (уместо .war):
COPY webapp/reportserver /usr/local/tomcat/webapps/reportserver

EXPOSE 8080
ENV CATALINA_OPTS="-Xms1g -Xmx4g -Djava.net.preferIPv4Stack=true -Drs.configdir=/config -Drs.lucene.dir=/lucene_index"
