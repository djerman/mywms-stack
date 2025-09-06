FROM eclipse-temurin:11-jre

# Додај WF 22 сервер (директоријум мора бити присутан локално у mywms/)
ADD wildfly-22.0.1.Final /opt/wildfly
ENV JBOSS_HOME=/opt/wildfly
WORKDIR ${JBOSS_HOME}

# Убаци наш standalone.xml (већ подешен на pg:5432, DS/JNDI итд.)
COPY standalone.xml ${JBOSS_HOME}/standalone/configuration/standalone.xml

# deployments НЕ печемо у слику — .ear и PgJDBC .jar долазе као volume
EXPOSE 8080 9990
ENTRYPOINT ["bash","-lc","${JBOSS_HOME}/bin/standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0"]

