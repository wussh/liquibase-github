-- ============================================================
-- CONTOH 4: CREATE INDEX — Menambah Index Baru
-- File   : changelog/changes/0004-add-index-users-phone.sql
-- Rollback: rollback/0004-rollback.sql
-- ============================================================

-- Menambahkan index pada kolom phone untuk mempercepat pencarian
ALTER TABLE `users`
  ADD KEY `idx_users_phone` (`phone`);
