-- ============================================================
-- ROLLBACK 6: DROP FOREIGN KEY + DROP COLUMN role_id
-- File   : rollback/0006-rollback.sql
-- Pasangan: changelog/changes/0006-add-fk-users-roles.sql
-- ============================================================

-- PENTING: Harus hapus FK constraint terlebih dahulu sebelum DROP COLUMN!
ALTER TABLE `users`
  DROP FOREIGN KEY `fk_users_role_id`;

ALTER TABLE `users`
  DROP COLUMN `role_id`;
