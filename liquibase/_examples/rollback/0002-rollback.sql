-- ============================================================
-- ROLLBACK 2: DROP COLUMN is_verified, verified_at, verified_by
-- File   : rollback/0002-rollback.sql
-- Pasangan: changelog/changes/0002-add-column-users-verified.sql
-- ============================================================

ALTER TABLE `users`
  DROP COLUMN `verified_by`,
  DROP COLUMN `verified_at`,
  DROP COLUMN `is_verified`;
