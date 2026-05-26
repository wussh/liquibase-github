-- ============================================================
-- ROLLBACK 4: DROP INDEX idx_users_phone
-- File   : rollback/0004-rollback.sql
-- Pasangan: changelog/changes/0004-add-index-users-phone.sql
-- ============================================================

ALTER TABLE `users`
  DROP KEY `idx_users_phone`;
