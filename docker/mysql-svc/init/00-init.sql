-- Init mysql-svc: buat 2 database + grant akses ke liquibase_user
CREATE DATABASE IF NOT EXISTS db_payments;
CREATE DATABASE IF NOT EXISTS db_inventory;

GRANT ALL PRIVILEGES ON db_payments.*  TO 'liquibase_user'@'%';
GRANT ALL PRIVILEGES ON db_inventory.* TO 'liquibase_user'@'%';
FLUSH PRIVILEGES;
