-- ============================================================
-- ROLLBACK 5: Hapus data seed dan drop tabel roles
-- File   : rollback/0005-rollback.sql
-- Pasangan: changelog/changes/0005-seed-data-roles.sql
-- ============================================================

-- Hapus data seed yang diinsert
-- (opsional jika langsung DROP TABLE, tapi baik untuk eksplisit)
DELETE FROM `roles` WHERE `code` IN ('ADMIN', 'MANAGER', 'STAFF', 'VIEWER');

-- Drop tabel yang dibuat
DROP TABLE IF EXISTS `roles`;
