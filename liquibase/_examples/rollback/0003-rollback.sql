-- ============================================================
-- ROLLBACK 3: Kembalikan tipe kolom ke definisi semula
-- File   : rollback/0003-rollback.sql
-- Pasangan: changelog/changes/0003-modify-column-users-email.sql
-- ============================================================

-- Kembalikan email VARCHAR(255) → VARCHAR(150)
-- dan phone VARCHAR(30) → VARCHAR(20)
ALTER TABLE `users`
  MODIFY COLUMN `email` VARCHAR(150) NOT NULL,
  MODIFY COLUMN `phone` VARCHAR(20)      NULL;
