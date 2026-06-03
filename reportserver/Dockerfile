FROM tomcat:9.0-jdk11-temurin

# Конфигурација ReportServer-а (мапира се и као volume у compose-у)
COPY config /config
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# РАСПАКОВАНА веб-апликација (уместо .war):
COPY webapp/reportserver /usr/local/tomcat/webapps/reportserver

EXPOSE 8080
ENV CATALINA_OPTS="-Xms1g -Xmx4g -Djava.net.preferIPv4Stack=true -Drs.configdir=/runtime-config -Drs.lucene.dir=/lucene_index"
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["catalina.sh", "run"]
