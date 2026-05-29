-- ============================================================
-- CONTOH 5: INSERT — Menyisipkan Data Awal (Seed / Master Data)
-- File   : changelog/changes/0005-seed-data-users-roles.sql
-- Rollback: rollback/0005-rollback.sql
-- ============================================================

CREATE TABLE `roles` (
  `id`          TINYINT      NOT NULL AUTO_INCREMENT,
  `code`        VARCHAR(20)  NOT NULL,
  `name`        VARCHAR(50)  NOT NULL,
  `description` VARCHAR(200)     NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_roles_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- Seed data role awal
INSERT INTO `roles` (`code`, `name`, `description`) VALUES
  ('ADMIN',   'Administrator',  'Akses penuh ke seluruh sistem'),
  ('MANAGER', 'Manager',        'Akses manajemen dan laporan'),
  ('STAFF',   'Staff',          'Akses operasional harian'),
  ('VIEWER',  'Viewer',         'Hanya bisa melihat data');
