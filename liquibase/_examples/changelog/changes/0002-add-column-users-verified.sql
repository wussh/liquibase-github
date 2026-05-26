-- ============================================================
-- CONTOH 2: ALTER TABLE — Menambah Kolom Baru
-- File   : changelog/changes/0002-add-column-users-verified.sql
-- Rollback: rollback/0002-rollback.sql
-- ============================================================

ALTER TABLE `users`
  ADD COLUMN `is_verified`   TINYINT  NOT NULL DEFAULT 0 COMMENT '1=verified, 0=unverified' AFTER `status`,
  ADD COLUMN `verified_at`   DATETIME     NULL DEFAULT NULL AFTER `is_verified`,
  ADD COLUMN `verified_by`   VARCHAR(50)  NULL DEFAULT NULL AFTER `verified_at`;
