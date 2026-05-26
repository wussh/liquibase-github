-- ============================================================
-- CONTOH 3: ALTER TABLE — Mengubah Tipe / Ukuran Kolom
-- File   : changelog/changes/0003-modify-column-users-email.sql
-- Rollback: rollback/0003-rollback.sql
-- ============================================================

-- Memperbesar ukuran kolom email dari VARCHAR(150) → VARCHAR(255)
-- dan phone dari VARCHAR(20) → VARCHAR(30)
ALTER TABLE `users`
  MODIFY COLUMN `email` VARCHAR(255) NOT NULL,
  MODIFY COLUMN `phone` VARCHAR(30)      NULL;
