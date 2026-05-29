-- ============================================================
-- ROLLBACK 1: DROP TABLE users
-- File   : rollback/0001-rollback.sql
-- Pasangan: changelog/changes/0001-create-table-users.sql
-- ============================================================

DROP TABLE IF EXISTS `users`;
