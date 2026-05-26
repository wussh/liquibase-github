# HOW-TO: Liquibase Database Migration

Panduan lengkap penggunaan Liquibase dari nol — semua skenario, semua kasus.

---

## Daftar Isi

1. [Apa itu Liquibase?](#1-apa-itu-liquibase)
2. [Prerequisites](#2-prerequisites)
3. [Struktur Folder Project](#3-struktur-folder-project)
4. [Setup Pertama Kali (Local Dev)](#4-setup-pertama-kali-local-dev)
5. [Membuat Changeset Baru](#5-membuat-changeset-baru)
6. [Generate Master XML Otomatis](#6-generate-master-xml-otomatis)
7. [Menjalankan Migrasi](#7-menjalankan-migrasi)
8. [Rollback](#8-rollback)
9. [Onboarding Database yang Sudah Ada](#9-onboarding-database-yang-sudah-ada)
10. [Multi Database & Multi Version](#10-multi-database--multi-version)
11. [Perintah Pembantu Lainnya](#11-perintah-pembantu-lainnya)
12. [Konfigurasi via .env](#12-konfigurasi-via-env)
13. [GitHub Actions (CI/CD)](#13-github-actions-cicd)
14. [Troubleshooting](#14-troubleshooting)
15. [Referensi Perintah Lengkap](#15-referensi-perintah-lengkap)

---

## 1. Apa itu Liquibase?

Liquibase adalah tools **database version control**. Sama seperti Git untuk kode, Liquibase digunakan untuk melacak, menerapkan, dan membatalkan perubahan skema database secara terstruktur dan aman.

**Masalah yang diselesaikan:**
- ❌ Tidak ada lagi SQL yang dikirim via WhatsApp / Email
- ❌ Tidak ada lagi "lupa apply SQL di server staging"
- ✅ Setiap perubahan database terdokumentasi di Git
- ✅ Deploy database bisa otomatis lewat CI/CD
- ✅ Rollback database bisa dilakukan kapan saja

---

## 2. Prerequisites

### Opsi A — Menggunakan Docker (Direkomendasikan)

| Tool | Versi Minimal | Cara Cek |
|---|---|---|
| Docker | 20.x+ | `docker --version` |
| Docker Compose | v2.x+ | `docker compose version` |
| Git | 2.x+ | `git --version` |

> [!NOTE]
> Dengan Docker, **Liquibase tidak perlu diinstall** secara lokal — semua berjalan di dalam container.

### Opsi B — Menggunakan Native Binary

| Tool | Versi Minimal | Cara Cek |
|---|---|---|
| Java (JRE/JDK) | 11+ | `java -version` |
| Liquibase | 4.x+ | `liquibase --version` |
| Git | 2.x+ | `git --version` |

**Install Liquibase Native:**
- Windows: Download dari https://github.com/liquibase/liquibase/releases
- Mac: `brew install liquibase`
- Linux: `snap install liquibase`

---

## 3. Struktur Folder Project

```
liquibase-github/
├── docker/
│   └── Dockerfile                      ← Custom Liquibase + MySQL JDBC image
├── scripts/
│   └── lb.sh                           ← Script helper utama
├── docker-compose.yml                  ← Konfigurasi Docker (MySQL local)
├── .env.example                        ← Template konfigurasi
├── .env                                ← Konfigurasi lokal (git-ignored)
└── liquibase/
    ├── liquibase.local.properties      ← Dibuat otomatis, git-ignored
    └── {NAMA_DATABASE}/                ← Satu folder per database
        └── {VERSI}/                    ← Satu folder per versi (v1.0, v1.1, ...)
            ├── changelog/
            │   ├── db.changelog-master.xml   ← Di-generate OTOMATIS oleh generate-master
            │   └── changes/                  ← SQL forward migration (CREATE, ALTER, INSERT)
            │       ├── 0001-init-table.sql
            │       └── 0002-*.sql
            └── rollback/                     ← SQL rollback (DROP, revert)
                ├── 0001-rollback.sql         ← Pasangan dari 0001-init-table.sql
                └── 0002-rollback.sql
```

> [!IMPORTANT]
> Konvensi penamaan file: **4 digit angka + nama deskriptif** → `0001-init-table.sql`.
> File rollback menggunakan format **{PREFIX}-rollback.sql** → `0001-rollback.sql`.
> `db.changelog-master.xml` **tidak perlu diedit manual** — gunakan perintah `generate-master`.

---

## 4. Setup Pertama Kali (Local Dev)

### Langkah 1 — Clone Repository

```bash
git clone <url-repo>
cd liquibase-github
```

### Langkah 2 — Buat file `.env`

```bash
cp .env.example .env
```

Edit `.env` sesuai kebutuhanmu (lihat [Bab 11 — Konfigurasi via .env](#11-konfigurasi-via-env)).

### Langkah 3 — (Opsional) Build Custom Docker Image

Hanya diperlukan jika kamu menggunakan **mode Docker** (Opsi A):

```bash
docker compose build liquibase
```

### Langkah 4 — Jalankan MySQL Lokal (Opsional)

Hanya diperlukan jika ingin menjalankan database di Docker lokal:

```bash
docker compose up -d mysql
```

### Langkah 5 — Test Koneksi

```bash
# Mode Docker internal (MySQL di Docker)
./scripts/lb.sh status

# Mode External (database existing di luar)
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 status
```

---

## 5. Membuat Changeset Baru

> [!TIP]
> **Tidak perlu menyentuh `db.changelog-master.xml` secara manual!**
> Setelah membuat 2 file SQL, jalankan `generate-master` dan XML akan diperbarui otomatis.
> Lihat [Bab 6 — Generate Master XML Otomatis](#6-generate-master-xml-otomatis).

### Langkah 1 — Buat File SQL di Folder `changes/`

Buat file SQL di folder `liquibase/{NAMA_DB}/{VERSI}/changelog/changes/`:

```sql
-- File: 0007-add-column-user-status.sql

ALTER TABLE `international_trx`
  ADD COLUMN `user_status` VARCHAR(20) DEFAULT 'active';
```

> [!IMPORTANT]
> - Ikuti konvensi angka **4 digit berurutan**: `0001`, `0002`, `0007`, dst.
> - **Jangan pernah edit file yang sudah pernah dijalankan** di database manapun!
> - Untuk mengubah/menghapus sesuatu, selalu buat file baru dengan nomor berikutnya.

### Langkah 2 — Buat File SQL Rollback di Folder `rollback/`

Buat file rollback yang merupakan **kebalikan** dari file `changes/`.
Konvensi nama: **{NOMOR_SAMA}-rollback.sql**

```sql
-- File: 0007-rollback.sql

ALTER TABLE `international_trx`
  DROP COLUMN `user_status`;
```

| Operasi di `changes/` | Rollback di `rollback/` |
|---|---|
| `CREATE TABLE` | `DROP TABLE IF EXISTS` |
| `ALTER TABLE ADD COLUMN` | `ALTER TABLE DROP COLUMN` |
| `ALTER TABLE MODIFY COLUMN` | `ALTER TABLE MODIFY COLUMN` (ukuran semula) |
| `ALTER TABLE ADD KEY` | `ALTER TABLE DROP KEY` |
| `ALTER TABLE ADD CONSTRAINT` | `ALTER TABLE DROP FOREIGN KEY` lalu `DROP COLUMN` |
| `INSERT` (seed data) | `DELETE FROM ... WHERE ...` |
| `CREATE INDEX` | `DROP INDEX` |

### Langkah 3 — Generate Master XML & Commit

```bash
# Generate ulang db.changelog-master.xml secara otomatis
./scripts/lb.sh --db-name=MBTL_INT_COBA --ver=v1.0 generate-master

# Commit semua file (2 SQL + 1 XML yang di-generate)
git add liquibase/MBTL_INT_COBA/v1.0/changelog/changes/0007-add-column-user-status.sql
git add liquibase/MBTL_INT_COBA/v1.0/rollback/0007-rollback.sql
git add liquibase/MBTL_INT_COBA/v1.0/changelog/db.changelog-master.xml
git commit -m "feat(db): add user_status column to international_trx"
git push
```

---

## 6. Generate Master XML Otomatis

Perintah `generate-master` akan **memindai otomatis** folder `changelog/changes/` dan `rollback/`, kemudian membangun ulang `db.changelog-master.xml` — tanpa perlu koneksi database.

### Cara Pakai

```bash
./scripts/lb.sh --db-name=MBTL_INT_COBA --ver=v1.0 generate-master
```

### Contoh Output

```
═══════════════════════════════════════════════
 generate-master
 DB   : MBTL_INT_COBA
 Ver  : v1.0
 Src  : .../changelog/changes
 Out  : .../changelog/db.changelog-master.xml
═══════════════════════════════════════════════
  ✅ 0001-init-table.sql           →  0001-rollback.sql
  ✅ 0002-init-master-bank.sql     →  0002-rollback.sql
  ✅ 0007-add-column-status.sql    →  0007-rollback.sql
  ⚠️  0008-new-feature.sql         →  rollback/0008-rollback.sql (TIDAK DITEMUKAN)

══════════════════════════════════
 ✅ Selesai! db.changelog-master.xml berhasil di-generate.
    Total changeset      : 4
    ⚠️  Missing rollback  : 1 file
══════════════════════════════════
```

### Aturan Pemasangan (Pairing)

Script mencocokkan file berdasarkan **prefix angka**:

| File di `changes/` | Dicari pasangannya di `rollback/` |
|---|---|
| `0001-init-table.sql` | `0001-rollback.sql` |
| `0007-add-column.sql` | `0007-rollback.sql` |
| `0012-seed-data.sql` | `0012-rollback.sql` |

> [!WARNING]
> Jika file rollback tidak ditemukan, changeset tersebut akan didaftarkan dengan **empty rollback** (`<rollback/>`), artinya rollback pada changeset itu tidak akan melakukan apa-apa.
> Script akan menampilkan peringatan ⚠️ untuk setiap file yang tidak punya pasangan rollback.

### Kapan Harus Dijalankan?

- Setiap kali menambahkan file SQL baru ke folder `changes/` atau `rollback/`
- Setelah `git pull` yang berisi penambahan file SQL dari rekan tim
- Sebelum menjalankan `update` ke database

---

## 7. Menjalankan Migrasi

### Mode Docker Internal (MySQL di Docker Lokal)

```bash
# Lihat perubahan yang belum diterapkan
./scripts/lb.sh status

# Preview SQL yang akan dijalankan (TANPA mengubah DB)
./scripts/lb.sh updateSQL

# Terapkan semua perubahan yang belum dijalankan
./scripts/lb.sh update
```

### Mode External (Database Existing)

```bash
# Format: --external --db-name=NAMA_DB --ver=VERSI

# Lihat status
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 status

# Preview SQL
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 updateSQL

# Apply migrasi
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 update
```

### Override Koneksi Database

```bash
# Override host dan nama DB via flag
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 \
  --host=192.168.1.100 --db=NAMA_DB_TARGET update

# Override via environment variable
EXT_DB_HOST=192.168.1.100 EXT_DB_NAME=NAMA_DB \
  ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 update
```

### Memaksa Menggunakan Runner Tertentu

```bash
# Paksa Docker
./scripts/lb.sh --runner=docker --external --db-name=MBTL_INT_COBA --ver=v1.0 update

# Paksa native binary
./scripts/lb.sh --runner=native --external --db-name=MBTL_INT_COBA --ver=v1.0 update
```

---

## 8. Rollback

> [!CAUTION]
> Rollback **mengubah data database** secara permanen. Selalu backup terlebih dahulu di environment production!

### Rollback N Changeset Terakhir

```bash
# Rollback 1 changeset terakhir
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 rollback-count --count=1

# Rollback 3 changeset terakhir
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 rollback-count --count=3
```

> [!TIP]
> Preview SQL rollback terlebih dahulu sebelum eksekusi:
> ```bash
> ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 rollback-count-sql --count=1
> ```

### Rollback ke Tag Tertentu

Pertama, tandai titik checkpoint dengan `tag` di database:

```bash
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 tag --tag=v1.0-stable
```

Kemudian, rollback ke tag tersebut kapan pun dibutuhkan:

```bash
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 rollback --tag=v1.0-stable
```

### Rollback ke Tanggal Tertentu

```bash
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 rollback-to-date --date=2025-01-01
```

### Agar Rollback Bisa Berfungsi

Rollback hanya bisa berjalan jika kamu mendefinisikan file SQL rollback dan mendaftarkannya di `db.changelog-master.xml` dengan format:

```xml
<changeSet id="..." author="...">
    <sqlFile path="changelog/changes/000X-*.sql" .../>
    <rollback>
        <sqlFile path="rollback/000X-rollback.sql" .../>  <!-- ← Wajib ada ini -->
    </rollback>
</changeSet>
```

Jika file SQL di `changes/` kamu adalah **raw SQL tanpa format Liquibase** dan tidak ada rollback yang terdaftar, Liquibase akan menolak perintah rollback.

---

## 9. Onboarding Database yang Sudah Ada

Kamu bisa membawa database yang sudah berjalan ke bawah manajemen Liquibase.

### Skenario A — DB Sudah Ada, Ingin Pakai Struktur Project Ini

Langkah ini untuk kondisi database kamu **sudah berisi tabel-tabel** dan ingin menggunakan changeset dari project ini.

**Langkah 1** — Jalankan update untuk menerapkan semua changeset:

```bash
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 update
```

Jika tabel sudah ada di database dan muncul error, lanjutkan ke Langkah 2.

**Langkah 2** — Jika tabel sudah ada, lakukan `changelogSync` untuk menandai semua changeset sebagai "sudah dijalankan" tanpa benar-benar menjalankan SQL-nya:

```bash
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 changelogSync
```

Setelah ini, Liquibase akan mencatat semua changeset tersebut di tabel `DATABASECHANGELOG` sebagai sudah EXECUTED.

### Skenario B — Ingin Generate Baseline dari DB yang Ada

Kamu ingin membuat file SQL changeset secara **otomatis** berdasarkan struktur tabel yang sudah ada di database.

**Langkah 1** — Generate file baseline ke folder `changes/`:

```bash
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 generateChangeLog \
  --changelog-file=changelog/changes/0001-baseline.sql
```

> [!NOTE]
> Gunakan nama file **baru** yang belum pernah ada. Jangan menulis ulang ke file yang sudah ada.

**Langkah 2** — Buat file rollback yang berisi DROP TABLE untuk semua tabel di baseline:

```sql
-- File: rollback/0001-rollback.sql
DROP TABLE IF EXISTS `nama_tabel_1`;
DROP TABLE IF EXISTS `nama_tabel_2`;
-- ... dan seterusnya
```

**Langkah 3** — Generate master XML otomatis:

```bash
./scripts/lb.sh --db-name=NAMA_DB --ver=v1.0 generate-master
```

**Langkah 4** — Tandai sebagai sudah dijalankan (karena tabel sudah ada):

```bash
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 changelogSync
```

### Skenario C — Reset Total (Mulai dari Awal)

Hapus semua objek database (tabel, view, index, dll.) sekaligus tabel tracking Liquibase:

```bash
# ⚠️ HATI-HATI: Semua data dan tabel akan TERHAPUS PERMANEN!
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 dropAll

# Lalu apply ulang dari awal
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 update
```

---

## 10. Multi Database & Multi Version

### Mengelola Beberapa Database

Project ini mendukung banyak database dalam satu repository. Cukup buat folder baru di bawah `liquibase/`:

```
liquibase/
├── MBTL_INT_COBA/        ← Database pertama
│   ├── v1.0/
│   └── v1.1/
├── MBTL_PAYMENT/         ← Database kedua
│   └── v1.0/
└── MBTL_AUDIT/           ← Database ketiga
    └── v1.0/
```

### Berpindah Antar Database

```bash
# Jalankan untuk database MBTL_INT_COBA
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 update

# Jalankan untuk database MBTL_PAYMENT
./scripts/lb.sh --external --db-name=MBTL_PAYMENT --ver=v1.0 update
```

### Mengelola Versi (v1.0, v1.1, v2.0, dsb.)

Setiap versi adalah folder terpisah. Untuk membuat versi baru:

**Langkah 1** — Buat folder versi baru dan file SQL:

```
liquibase/MBTL_INT_COBA/v1.1/
├── changelog/
│   ├── db.changelog-master.xml   ← Di-generate otomatis, jangan diedit manual
│   └── changes/
│       └── 0001-new-feature.sql
└── rollback/
    └── 0001-rollback.sql
```

**Langkah 2** — Generate master XML untuk versi baru:

```bash
./scripts/lb.sh --db-name=MBTL_INT_COBA --ver=v1.1 generate-master
```

**Langkah 3** — Apply secara berurutan:

```bash
# Apply perubahan v1.0 dulu
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 update

# Apply perubahan v1.1
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.1 update
```

> [!NOTE]
> Setiap versi memiliki `db.changelog-master.xml` tersendiri yang hanya mendaftarkan changeset untuk versi tersebut. Liquibase merekam setiap changeset berdasarkan kombinasi `id + author` di tabel `DATABASECHANGELOG`, sehingga tidak akan dijalankan dua kali meskipun kamu menjalankan v1.0 dan v1.1 secara bergantian.

---

## 11. Perintah Pembantu Lainnya

### Lihat Riwayat Migrasi

```bash
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 history
```

### Lihat Status Changeset

```bash
# Changeset mana yang belum dijalankan?
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 status
```

### Validasi Format Changelog

```bash
# Cek apakah format XML/SQL changelog sudah benar
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 validate
```

### Lihat Perbedaan DB vs Changelog (Diff)

```bash
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 diff
```

### Reset Checksum (Jika File SQL Diedit)

> [!WARNING]
> Jangan mengedit file SQL yang sudah pernah dijalankan di database production!
> Fitur ini khusus untuk developer lokal jika terpaksa mengedit file.

```bash
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 clearCheckSums
```

Setelah ini, Liquibase akan menghitung ulang semua checksum tanpa mereset data.

---

## 12. Konfigurasi via .env

Script `lb.sh` secara otomatis memuat file `.env` dari root project jika ada.

### Setup file `.env`

```bash
cp .env.example .env
```

### Isi file `.env`

```env
# ── Koneksi External Database ──────────────────────────
EXT_DB_HOST=172.24.169.100
EXT_DB_PORT=3306
EXT_DB_NAME=MBTL_INT_COBA
EXT_DB_USER=root
EXT_DB_PASS=password_rahasia

# ── Docker Internal (opsional, ada defaultnya) ─────────
# LIQUIBASE_IMAGE=liquibase-mysql:4.27
# MYSQL_CONTAINER=liquibase-mysql
```

> [!CAUTION]
> **Jangan pernah commit file `.env` ke Git!**
> File `.env` sudah masuk `.gitignore`, pastikan tidak pernah dihapus dari `.gitignore`.

### Prioritas Konfigurasi

Konfigurasi akan dibaca dengan urutan prioritas (lebih atas = lebih diprioritaskan):

```
1. Flag langsung di command line  →  --host=192.168.1.100
2. Environment variable di shell  →  EXT_DB_HOST=192.168.1.100 ./scripts/lb.sh ...
3. File .env                      →  EXT_DB_HOST=192.168.1.100 di .env
4. Nilai default di script        →  127.0.0.1:3306
```

---

## 13. GitHub Actions (CI/CD)

Setiap `push` ke branch `main` akan otomatis menjalankan migrasi ke database yang dikonfigurasi via GitHub Secrets.

### Setup GitHub Secrets

Buka repository GitHub → **Settings** → **Secrets and variables** → **Actions**:

| Secret | Contoh Nilai | Keterangan |
|---|---|---|
| `DB_URL` | `jdbc:mysql://host:3306/db?useSSL=false` | URL koneksi JDBC |
| `DB_USERNAME` | `liquibase_user` | Username database |
| `DB_PASSWORD` | `password_rahasia` | Password database |

### Setup Environment Protection (Manual Approval)

Untuk environment **staging** atau **production**, tambahkan reviewer yang harus menyetujui sebelum deploy berjalan:

1. Buka GitHub → **Settings** → **Environments**
2. Buat environment baru: `staging` atau `production`
3. Centang **Required reviewers**
4. Tambahkan nama reviewer yang berwenang

### Cara Deploy via GitHub Actions

```bash
# Push ke branch main untuk trigger otomatis
git push origin main

# Atau trigger manual via GitHub UI:
# Repository → Actions → Pilih workflow → Run workflow
```

---

## 14. Troubleshooting

### ❌ `option '--changelog-file' (PARAM) should be specified only once`

**Penyebab:** Liquibase membaca nilai `changeLogFile` dari file `liquibase.properties` sekaligus menerima `--changelog-file` dari command line — menjadi duplikat.

**Solusi:** Script `lb.sh` sudah menangani ini secara otomatis dengan membuat file `liquibase.local.properties` kosong. Pastikan kamu menggunakan script `lb.sh`, bukan memanggil `liquibase` langsung.

---

### ❌ `Could not find defaults file nul` (Windows)

**Penyebab:** Path `/dev/null` tidak valid di Windows.

**Solusi:** Script `lb.sh` sudah menangani ini secara otomatis dengan menggunakan file `liquibase.local.properties` kosong. Pastikan script sudah versi terbaru (`git pull`).

---

### ❌ `You have an error in your SQL syntax` (Multi-statement SQL)

**Penyebab:** Driver MySQL memblokir eksekusi banyak perintah SQL sekaligus dalam satu transaksi.

**Solusi:** Script `lb.sh` sudah menambahkan `allowMultiQueries=true` di URL koneksi.
Jika masih terjadi, pastikan di `db.changelog-master.xml` parameter `splitStatements="true"` dan `endDelimiter=";"` sudah ada di `<sqlFile>`:

```xml
<sqlFile path="..." splitStatements="true" endDelimiter=";"/>
```

---

### ❌ `Output ChangeLogFile already exists!`

**Penyebab:** Kamu menjalankan `generateChangeLog` tanpa menentukan file tujuan baru, sehingga Liquibase mencoba menimpa `db.changelog-master.xml`.

**Solusi:** Selalu tentukan nama file baru saat menjalankan `generateChangeLog`:

```bash
# ✅ Benar: tentukan file baru
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 generateChangeLog \
  --changelog-file=changelog/changes/0001-baseline.sql

# ❌ Salah: tanpa --changelog-file
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 generateChangeLog
```

---

### ❌ `Liquibase does not support automatic rollback generation for raw sql changes`

**Penyebab:** Kamu menjalankan `rollback-count` pada changeset yang menggunakan raw SQL (file `.sql` langsung) tanpa mendefinisikan rollback-nya.

**Solusi:** Pastikan setiap `<changeSet>` di `db.changelog-master.xml` memiliki blok `<rollback>` yang mengarah ke file SQL rollback di folder `rollback/`:

```xml
<changeSet id="..." author="...">
    <sqlFile path="changelog/changes/000X.sql" .../>
    <rollback>
        <sqlFile path="rollback/000X-rollback.sql" .../>
    </rollback>
</changeSet>
```

---

### ❌ `MD5Sum Check Failed` (Checksum Mismatch)

**Penyebab:** File SQL changeset diedit setelah pernah dijalankan di database.

**Solusi (Development only):**

```bash
./scripts/lb.sh --external --db-name=NAMA_DB --ver=v1.0 clearCheckSums
```

> [!CAUTION]
> Di Production, jangan pernah mengedit file yang sudah dijalankan. Buat file baru sebagai gantinya.

---

### ❌ `Communications link failure` / `Connection refused`

**Penyebab:** Script tidak bisa terhubung ke database target.

**Checklist:**
- [ ] Host dan port database benar? Cek di `.env` atau flag `--host`.
- [ ] Database berjalan? Coba ping host-nya.
- [ ] Jika pakai Docker: apakah kamu mengakses `localhost` dari dalam container? Ganti `localhost` dengan `host.docker.internal`.
- [ ] Firewall / VPN aktif? Pastikan port database bisa diakses.
- [ ] Username dan password benar?

---

## 15. Referensi Perintah Lengkap

### Format Perintah

```bash
./scripts/lb.sh [FLAGS] COMMAND [COMMAND_OPTIONS]
```

### Flags Global

| Flag | Contoh | Keterangan |
|---|---|---|
| `--external` | `--external` | Gunakan koneksi database external |
| `--db-name` | `--db-name=MBTL_INT_COBA` | Nama folder database |
| `--ver` | `--ver=v1.0` | Versi changelog |
| `--host` | `--host=192.168.1.100` | Override host database |
| `--db` | `--db=NAMA_DATABASE` | Override nama database (di JDBC URL) |
| `--runner` | `--runner=native` | Paksa runner: `docker` atau `native` |

### Daftar Semua Perintah

**Perintah Script (tidak butuh koneksi DB):**

| Perintah | Fungsi |
|---|---|
| `generate-master` | Scan `changes/` + `rollback/` → generate `db.changelog-master.xml` otomatis |

**Perintah Liquibase (butuh koneksi DB):**

| Perintah | Fungsi |
|---|---|
| `update` | Apply semua changeset yang belum dijalankan |
| `updateSQL` | Preview SQL yang akan dijalankan (tanpa apply) |
| `status` | Lihat changeset yang belum dijalankan |
| `validate` | Validasi format file changelog |
| `history` | Lihat riwayat semua changeset yang sudah dijalankan |
| `diff` | Bandingkan skema database dengan changelog |
| `rollback-count --count=N` | Rollback N changeset terakhir |
| `rollback-count-sql --count=N` | Preview SQL rollback (tanpa eksekusi) |
| `rollback --tag=NAMA_TAG` | Rollback ke tag tertentu |
| `rollback-sql --tag=NAMA_TAG` | Preview SQL rollback ke tag (tanpa eksekusi) |
| `rollback-to-date --date=YYYY-MM-DD` | Rollback ke tanggal tertentu |
| `tag --tag=NAMA_TAG` | Buat checkpoint/tag di database |
| `generateChangeLog` | Generate changelog dari struktur DB existing |
| `changelogSync` | Tandai semua changeset sebagai sudah dijalankan (tanpa eksekusi SQL) |
| `changelogSyncSQL` | Preview SQL yang akan dijalankan changelogSync |
| `clearCheckSums` | Reset semua checksum di tabel DATABASECHANGELOG |
| `dropAll` | Hapus semua objek database (BERBAHAYA!) |

### Contoh Lengkap — Workflow Sehari-hari

```bash
# ─── Menambah Changeset Baru ────────────────────────────────
# 1. Buat file SQL perubahan
vim liquibase/MBTL_INT_COBA/v1.0/changelog/changes/0007-new-table.sql

# 2. Buat file SQL rollback
vim liquibase/MBTL_INT_COBA/v1.0/rollback/0007-rollback.sql

# 3. Generate master XML otomatis (tidak perlu koneksi DB!)
./scripts/lb.sh --db-name=MBTL_INT_COBA --ver=v1.0 generate-master

# 4. Commit
git add liquibase/MBTL_INT_COBA/v1.0/
git commit -m "feat(db): add new table"
git push

# ─── Apply & Verifikasi ────────────────────────────────────
# 5. Cek status
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 status

# 6. Preview SQL sebelum apply
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 updateSQL

# 7. Apply migrasi
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 update

# 8. Verifikasi history
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 history

# ─── Jika Ada Masalah ──────────────────────────────────────
# 9. Rollback changeset terakhir
./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 rollback-count --count=1
```
