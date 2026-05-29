-- ============================================================
-- CONTOH 1: CREATE TABLE (Membuat Tabel Baru)
-- File   : changelog/changes/0001-create-table-users.sql
-- Rollback: rollback/0001-rollback.sql
-- ============================================================

CREATE TABLE `users` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT,
  `username`   VARCHAR(50)  NOT NULL,
  `email`      VARCHAR(150) NOT NULL,
  `phone`      VARCHAR(20)      NULL,
  `status`     TINYINT      NOT NULL DEFAULT 1 COMMENT '1=active, 0=inactive',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_username` (`username`),
  UNIQUE KEY `uq_users_email`    (`email`),
  KEY `idx_users_status`         (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin COMMENT='Tabel data pengguna';
