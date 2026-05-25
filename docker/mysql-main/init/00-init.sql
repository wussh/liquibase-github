-- Init mysql-main: buat 2 database + grant akses ke liquibase_user
CREATE DATABASE IF NOT EXISTS db_users;
CREATE DATABASE IF NOT EXISTS db_orders;

GRANT ALL PRIVILEGES ON db_users.*  TO 'liquibase_user'@'%';
GRANT ALL PRIVILEGES ON db_orders.* TO 'liquibase_user'@'%';
FLUSH PRIVILEGES;
