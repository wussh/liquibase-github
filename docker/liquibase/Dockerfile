FROM liquibase/liquibase:4.27

# Download MySQL JDBC driver into Liquibase lib directory
USER root
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    wget -qO /liquibase/lib/mysql-connector-j-8.3.0.jar \
      "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.3.0/mysql-connector-j-8.3.0.jar" && \
    apt-get remove -y wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

USER liquibase
