-- Optional: init script yang dijalankan sekali saat MySQL pertama kali dibuat.
-- Digunakan untuk membuat database tambahan (staging simulation) jika perlu.

-- Tidak wajib — liquibase_dev sudah dibuat via MYSQL_DATABASE env var.
-- Uncomment jika butuh database tambahan:

-- CREATE DATABASE IF NOT EXISTS liquibase_staging;
-- GRANT ALL PRIVILEGES ON liquibase_staging.* TO 'liquibase_user'@'%';
-- FLUSH PRIVILEGES;
