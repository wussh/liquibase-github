-- ============================================================
-- CONTOH 6: RENAME TABLE + ADD FOREIGN KEY
-- File   : changelog/changes/0006-add-fk-users-roles.sql
-- Rollback: rollback/0006-rollback.sql
-- ============================================================

-- Tambah kolom role_id di tabel users
ALTER TABLE `users`
  ADD COLUMN `role_id` TINYINT NOT NULL DEFAULT 3 COMMENT 'FK ke tabel roles' AFTER `status`;

-- Tambah foreign key constraint
ALTER TABLE `users`
  ADD CONSTRAINT `fk_users_role_id`
    FOREIGN KEY (`role_id`)
    REFERENCES `roles` (`id`)
    ON UPDATE CASCADE
    ON DELETE RESTRICT;
