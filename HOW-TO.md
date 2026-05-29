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
13. [Atlassian Bamboo CI/CD](#13-atlassian-bamboo-cicd)
14. [Strategi Multi-DB & Multi-Server di CI/CD](#14-strategi-multi-db--multi-server-di-cicd)
15. [GitHub Actions (CI/CD)](#15-github-actions-cicd)
16. [Troubleshooting](#16-troubleshooting)
17. [Referensi Perintah Lengkap](#17-referensi-perintah-lengkap)

---

## 1. Apa itu Liquibase?

Liquibase adalah tools **database version control**. Sama seperti Git untuk kode, Liquibase digunakan untuk melacak, menerapkan, dan membatalkan perubahan skema database secara terstruktur dan aman.

**Masalah yang diselesaikan:**
- ❌ Tidak ada lagi SQL yang dikirim via WhatsApp / Email
- ❌ Tidak ada lagi "lupa apply SQL di server staging/production"
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
- Windows: Download installer dari https://github.com/liquibase/liquibase/releases
- Mac: `brew install liquibase`
- Linux: `snap install liquibase`

---

## 3. Struktur Folder Project

Struktur folder menggunakan **Opsi B** (folder `changes` dan `rollback` berada langsung di bawah folder versi, TANPA subfolder `changelog`):

```
liquibase-github/
├── docker/
│   └── liquibase/Dockerfile            ← Custom Liquibase image dengan MySQL driver
├── scripts/
│   └── lb.sh                           ← Script helper utama
├── docker-compose.yml                  ← Konfigurasi Docker (MySQL local dev)
├── .env.example                        ← Template konfigurasi
├── .env                                ← Konfigurasi koneksi (git-ignored)
└── liquibase/
    ├── liquibase.local.properties      ← Dibuat otomatis, git-ignored
    └── {NAMA_DATABASE}/                ← Satu folder per database (misal: db1)
        └── {VERSI}/                    ← Satu folder per versi (v.1.0, v.1.1, ...)
            ├── db.changelog-master.xml ← Di-generate OTOMATIS oleh generate-master
            ├── changes/                ← SQL forward migration (CREATE, ALTER, INSERT)
            │   ├── 0001-init-table.sql
            │   └── 0002-*.sql
            └── rollback/               ← SQL rollback (DROP, revert)
                ├── 0001-rollback.sql   ← Pasangan dari 0001-init-table.sql
                └── 0002-rollback.sql
```

> [!IMPORTANT]
> - Konvensi penamaan file: **4 digit angka + nama deskriptif** → `0001-create-table-users.sql`.
> - File rollback menggunakan format **{PREFIX}-rollback.sql** → `0001-rollback.sql`.
> - `db.changelog-master.xml` **tidak boleh diedit manual** — gunakan perintah `generate-master`.

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

Edit koneksi database di `.env` (lihat [Bab 12 — Konfigurasi via .env](#12-konfigurasi-via-env)).

### Langkah 3 — (Opsional) Build Custom Docker Image

Jika kamu menggunakan **mode Docker** (Opsi A):

```bash
docker compose build liquibase
```

### Langkah 4 — Jalankan MySQL Lokal (Opsional)

Jika ingin menjalankan database local development di Docker:

```bash
docker compose up -d mysql
```

### Langkah 5 — Test Koneksi

```bash
# Mode Docker internal (MySQL di Docker)
./scripts/lb.sh status

# Mode External (database target existing di luar)
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 status
```

---

## 5. Membuat Changeset Baru

> [!TIP]
> **Tidak perlu menyentuh `db.changelog-master.xml` secara manual!**
> Setelah membuat 2 file SQL (changes & rollback), jalankan perintah `generate-master` untuk memperbarui XML secara otomatis.

### Langkah 1 — Buat File SQL di Folder `changes/`

Buat file SQL di folder `liquibase/{NAMA_DB}/{VERSI}/changes/`:

```sql
-- File: liquibase/db1/v.1.0/changes/0007-add-column-user-status.sql

ALTER TABLE `users`
  ADD COLUMN `user_status` VARCHAR(20) DEFAULT 'active';
```

> [!IMPORTANT]
> - Ikuti konvensi angka **4 digit berurutan**: `0001`, `0002`, `0003`, dst.
> - **Jangan pernah edit file SQL yang sudah pernah dijalankan (deployed)** di database manapun!
> - Untuk merubah/menghapus skema, selalu buat file SQL baru dengan nomor berikutnya.

### Langkah 2 — Buat File SQL Rollback di Folder `rollback/`

Buat file rollback di folder `liquibase/{NAMA_DB}/{VERSI}/rollback/` sebagai kebalikan dari file `changes/`.
Konvensi nama: **{NOMOR_SAMA}-rollback.sql**

```sql
-- File: liquibase/db1/v.1.0/rollback/0007-rollback.sql

ALTER TABLE `users`
  DROP COLUMN `user_status`;
```

| Operasi di `changes/` | Rollback di `rollback/` |
|---|---|
| `CREATE TABLE` | `DROP TABLE IF EXISTS` |
| `ALTER TABLE ADD COLUMN` | `ALTER TABLE DROP COLUMN` |
| `ALTER TABLE MODIFY COLUMN` | `ALTER TABLE MODIFY COLUMN` (kembalikan ke tipe/ukuran semula) |
| `ALTER TABLE ADD KEY` | `ALTER TABLE DROP KEY` |
| `ALTER TABLE ADD CONSTRAINT` | `ALTER TABLE DROP FOREIGN KEY` |
| `INSERT` (seed data) | `DELETE FROM ... WHERE ...` |
| `CREATE INDEX` | `DROP INDEX` |

### Langkah 3 — Generate Master XML & Commit

```bash
# 1. Generate ulang db.changelog-master.xml secara otomatis
./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master

# 2. Commit semua file (2 SQL + 1 XML hasil generate)
git add liquibase/db1/v.1.0/
git commit -m "feat(db): add user_status column to users table"
git push
```

---

## 6. Generate Master XML Otomatis

Perintah `generate-master` memindai folder `changes/` and `rollback/`, lalu membangun ulang `db.changelog-master.xml` dengan XML-safe format (menghindari error double-hyphen `--` di dalam komentar XML).

### Cara Pakai

```bash
./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master
```

### Contoh Output

```
═══════════════════════════════════════════════
 generate-master
 DB     : db1
 Ver    : v.1.0
 Mode   : opsiB
 Src    : .../db1/v.1.0/changes
 Out    : .../db1/v.1.0/db.changelog-master.xml
═══════════════════════════════════════════════
  ✅ 0001-create-table-users.sql      →  0001-rollback.sql
  ✅ 0002-add-column-users.sql         →  0002-rollback.sql
  ⚠️  0003-new-feature.sql             →  rollback/0003-rollback.sql (TIDAK DITEMUKAN)

══════════════════════════════════
 ✅ Selesai! db.changelog-master.xml berhasil di-generate.
    Total changeset : 3
    ⚠️  Missing rollback : 1 file
══════════════════════════════════
```

> [!WARNING]
> Jika file rollback tidak ditemukan, changeset didaftarkan dengan **empty rollback** (`<rollback/>`).
> Perintah `generate-master` akan menampilkan peringatan ⚠️ untuk file tanpa rollback.

---

## 7. Menjalankan Migrasi

### Mode Docker Internal (MySQL di Docker Lokal)

```bash
# Lihat changeset yang belum diterapkan
./scripts/lb.sh status

# Preview SQL yang akan dijalankan (tanpa menyentuh DB)
./scripts/lb.sh updateSQL

# Terapkan semua perubahan
./scripts/lb.sh update
```

### Mode External (Database Target Existing)

```bash
# Format: --external --db-name=NAMA_DB --ver=VERSI

# Lihat status
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 status

# Preview SQL
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 updateSQL

# Terapkan perubahan
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 update
```

### Override Koneksi via Command Line

```bash
# Override host dan DB name target saat menjalankan update
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 \
  --host=192.168.1.100 --db=my_target_db update
```

---

## 8. Rollback

> [!CAUTION]
> Rollback **mengubah skema/data database**. Selalu lakukan backup database terlebih dahulu di environment production!

### Rollback N Changeset Terakhir

```bash
# Rollback 1 changeset terakhir
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 rollback-count --count=1

# Rollback 3 changeset terakhir
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 rollback-count --count=3
```

> [!TIP]
> Preview SQL rollback terlebih dahulu untuk memastikan tidak ada kesalahan:
> ```bash
> ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 rollback-count-sql --count=1
> ```

### Rollback ke Tag Checkpoint

1. Tandai titik aman (checkpoint) sebelum melakukan migrasi baru:
   ```bash
   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 tag --tag=before-v1.1
   ```

2. Terapkan versi baru:
   ```bash
   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.1 update
   ```

3. Jika terjadi masalah, rollback database kembali ke tag checkpoint:
   ```bash
   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.1 rollback --tag=before-v1.1
   ```

### Aturan Rollback: Harus Berurutan (LIFO), Tidak Bisa Lompat

> [!WARNING]
> Dalam Liquibase, **rollback TIDAK BISA dilakukan secara melompat (acak/selektif)**. Rollback **harus dilakukan secara berurutan mundur** dari changeset paling baru ke changeset yang lebih lama (prinsip LIFO - *Last In, First Out*).

#### Mengapa Tidak Bisa Melompat?
Misalnya kamu memiliki urutan changeset berikut yang sudah diaplikasikan (dari lama ke baru):
1. `0001-create-table-users`
2. `0002-add-column-email`
3. `0003-create-table-orders` (yang memiliki Foreign Key ke tabel `users`)

Jika kamu mencoba melakukan rollback **hanya** untuk changeset `0001` (menghapus tabel `users`) secara melompat tanpa melakukan rollback untuk `0002` dan `0003`, database akan error karena ada constraint/dependensi (tabel `orders` masih merujuk ke tabel `users` yang ingin kamu hapus). Oleh karena itu, Liquibase menjaga integritas database dengan memaksa rollback berjalan mundur secara berurutan.

#### Opsi Jika Ingin Membatalkan Perubahan di Tengah-Tengah (Forward-Migration / Roll-Forward)
Jika changeset yang ingin kamu batalkan berada di tengah-tengah (misalnya, kamu ingin membatalkan efek dari changeset `0002` tapi tidak ingin menyentuh changeset `0003` dan `0004` yang sudah sukses di production), **jangan gunakan perintah rollback**. 

Caranya adalah membuat **changeset baru** yang isinya membatalkan perubahan changeset lama tersebut:

1. **Buat file changes baru** (misal `0005-drop-column-email.sql`):
   ```sql
   ALTER TABLE `users` DROP COLUMN `email`;
   ```
2. **Buat file rollback pasangannya** (`0005-rollback.sql`):
   ```sql
   ALTER TABLE `users` ADD COLUMN `email` VARCHAR(255);
   ```
3. **Generate master XML dan jalankan update**:
   ```bash
   ./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master
   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 update
   ```

---

## 9. Onboarding Database yang Sudah Ada

Jika kamu memiliki database existing yang sudah berisi tabel, ada 3 skenario yang bisa kamu ikuti:

### Skenario 1 — Sinkronisasi Saja (Tabel Sudah Sama, Skip Eksekusi SQL)

Jika kamu sudah membuat file SQL di folder `changes/` yang isinya sama persis dengan tabel yang sudah terbuat di database, kamu hanya ingin Liquibase **mengakui** migrasi tersebut tanpa menjalankan perintah SQL-nya (agar tidak error `Table already exists`).

```bash
# 1. Generate master XML dari file changes/ yang ada
./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master

# 2. Sync changelog (menandai changeset sebagai EXECUTED di DATABASECHANGELOG)
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 changelogSync

# 3. Verifikasi (status seharusnya menunjukkan 0 changeset pending)
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 status
```

### Skenario 2 — Generate Baseline Baru dari DB Existing

Jika kamu ingin mengekspor seluruh struktur database existing ke dalam file SQL migrasi Liquibase sebagai starting point (baseline).

```bash
# 1. Generate skema database ke file SQL baru
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 generateChangeLog \
  --changelog-file=changes/0001-baseline.sql

# 2. Buat rollback baseline secara manual
#    (isi file ini dengan perintah DROP TABLE untuk semua tabel di baseline.sql)
vim liquibase/db1/v.1.0/rollback/0001-rollback.sql

# 3. Generate master XML
./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master

# 4. Sync agar database mengenali baseline ini (tabel sudah ada di DB)
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 changelogSync
```

### Skenario 3 — Menambah Changeset Baru Setelah Onboarding

Skenario paling umum: database production sudah ada datanya, dan kamu ingin mulai menggunakan Liquibase untuk perubahan-perubahan berikutnya.

```bash
# 1. Buat changeset kosong (baseline marker)
echo "-- Baseline: existing tables before Liquibase management" \
  > liquibase/db1/v.1.0/changes/0001-baseline-existing.sql

# Rollback baseline kosong karena tabel sudah ada sebelum Liquibase
echo "-- No rollback for baseline" \
  > liquibase/db1/v.1.0/rollback/0001-rollback.sql

# 2. Generate XML & Sync database existing
./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 changelogSync

# 3. Buat changeset perubahan berikutnya seperti biasa
vim liquibase/db1/v.1.0/changes/0002-add-new-column.sql
vim liquibase/db1/v.1.0/rollback/0002-rollback.sql

# 4. Generate-master & Apply update (hanya menjalankan changeset 0002 ke atas)
./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 update
```

---

## 10. Multi Database & Multi Version

### Struktur Folder Multi-DB

Cukup buat folder database baru di dalam `liquibase/`:

```
liquibase/
├── db1/                  ← Database pertama
│   ├── v.1.0/
│   └── v.1.1/
└── db_payment/           ← Database kedua
    ├── v.1.0/
    └── v.2.0/
```

### Apply Migrasi Spesifik

Tentukan `--db-name` dan `--ver` database tujuan saat memanggil helper:

```bash
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 update
./scripts/lb.sh --external --db-name=db_payment --ver=v.1.0 update
```

---

## 11. Perintah Pembantu Lainnya

### Lihat Riwayat Migrasi

```bash
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 history
```

### Validasi Format File Changelog

```bash
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 validate
```

### Lihat Perbedaan Skema (Diff)

```bash
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 diff
```

### Reset Checksum (Jika File SQL Terpaksa Diedit di Local Dev)

```bash
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 clearCheckSums
```

---

## 12. Konfigurasi via .env

Helper `lb.sh` mendukung konfigurasi multi-database. Kamu dapat memetakan host, user, dan password per-database secara spesifik menggunakan prefix `DB_{NAMA_DATABASE}_{FIELD}`.

### Contoh File `.env`

```env
# ── Koneksi Default / Fallback (jika DB_ khusus tidak diisi) ──
EXT_DB_HOST=127.0.0.1
EXT_DB_PORT=3306
EXT_DB_USER=root
EXT_DB_PASS=password

# ── Koneksi Spesifik Database: db1 ──
DB_DB1_HOST=172.24.169.100
DB_DB1_PORT=3306
DB_DB1_NAME=MBTL_INT_COBA_2
DB_DB1_USER=root
DB_DB1_PASS=password

# ── Koneksi Spesifik Database: db_payment ──
DB_DB_PAYMENT_HOST=172.24.169.101
DB_DB_PAYMENT_PORT=3306
DB_DB_PAYMENT_NAME=mbtl_payment
DB_DB_PAYMENT_USER=payment_user
DB_DB_PAYMENT_PASS=password_rahasia
```

> [!CAUTION]
> **Jangan pernah commit file `.env` ke Git!** File ini sudah di-ignore di `.gitignore`.

## 13. Atlassian Bamboo CI/CD

Mengintegrasikan Liquibase dengan Bamboo sangat mudah karena kita menggunakan script helper `lb.sh`.

### Alur Kerja (Build & Deploy)

1. **Build Plan (CI):** Dijalankan otomatis untuk validasi file SQL & XML pada Pull Request/Commit.
2. **Deployment Project (CD):** Digunakan untuk rilis (`update`) ke database target (Staging/Production).

### Setup Task di Bamboo

#### A. Task pada Build Plan (Tahap Validasi)
* **Type:** Script Task (Interpreter: Shell/Bash)
* **Script Body:**
  ```bash
  # 1. Pastikan XML up-to-date
  ./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master

  # 2. Validasi format XML/SQL
  ./scripts/lb.sh --db-name=db1 --ver=v.1.0 validate

  # 3. Dry-run updateSQL ke database testing
  ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 updateSQL
  ```

#### B. Task pada Deployment Project (Tahap Eksekusi)
* **Type:** Script Task (Interpreter: Shell/Bash)
* **Script Body:**
  ```bash
  # Inject kredensial dari Bamboo Environment Variables (gunakan tipe Password agar ter-masking)
  export EXT_DB_HOST="${bamboo.db.host}"
  export EXT_DB_PORT="${bamboo.db.port}"
  export EXT_DB_USER="${bamboo.db.username}"
  export EXT_DB_PASS="${bamboo.db.password}"

  # Jalankan migrasi
  ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 --db="${bamboo.db.name}" update
  ```

---

## 14. Strategi Multi-DB & Multi-Server di CI/CD

### Skenario 1 — Satu Database tapi Banyak Server (Dev -> Staging -> Prod)

Gunakan fitur **Bamboo Deployment Environments**. Buat environment berbeda (*Staging*, *Production*) dan berikan variabel yang sesuai pada masing-masing environment:
- **Environment Staging:** `bamboo.db.host=staging-db.local`
- **Environment Production:** `bamboo.db.host=prod-db.local`

Script task tetap generic dan otomatis berjalan di server tujuan sesuai environment yang kamu rilis.

### Skenario 2 — Banyak Database Berbeda di Banyak Server (Microservices)

#### Skenario A: Menggunakan File `.env` Multi-DB (Berurutan)
Definisikan semua target server di dalam file `.env` agen Bamboo menggunakan format `DB_{NAMA_DB}_{FIELD}`:
```env
DB_DB1_HOST=172.24.169.100
DB_DB1_NAME=db1_prod
# ...
DB_DB_PAYMENT_HOST=172.24.169.105
DB_DB_PAYMENT_NAME=payment_prod
# ...
```
Lalu panggil script secara berurutan:
```bash
./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 update
./scripts/lb.sh --external --db-name=db_payment --ver=v.1.0 update
```

#### Skenario B: Menggunakan Jobs Paralel Bamboo (Cepat)
Buat beberapa **Jobs** independen yang berjalan secara parallel di bawah satu Stage Bamboo. Masing-masing Job akan menjalankan migrasi database-nya sendiri secara bersamaan, sehingga menghemat waktu deploy.

### Skenario 3 — Banyak Database Berbeda di Satu Server MySQL yang Sama

Jika semua database berada di satu server MySQL (berbagi host, port, user, dan password yang sama), kamu hanya perlu mendefinisikan host & kredensial sekali saja di bagian global fallback `.env`:

```env
# Global Fallback (Server yang sama)
EXT_DB_HOST=172.24.169.100
EXT_DB_PORT=3306
EXT_DB_USER=root
EXT_DB_PASS=password_rahasia

# Petakan nama DB target jika berbeda dengan nama folder
DB_DB1_NAME=mbtl_int_coba
DB_DB2_NAME=mbtl_payment
```

Lalu jalankan menggunakan looping di Bash task Bamboo:
```bash
DATABASES=("db1" "db2" "db3")

for db in "${DATABASES[@]}"; do
  echo "Running migration for database: $db"
  ./scripts/lb.sh --external --db-name="$db" --ver=v.1.0 update
done
```

### Skenario 4 — Deteksi Otomatis & Deploy Statis Berdasarkan Commit (SANGAT DIREKOMENDASIKAN)

Jika kamu ingin konfigurasi YAML Bamboo kamu bersifat **statis** (tidak perlu diganti-ganti lagi selamanya), gunakan script detektor `deploy-changed.sh`. Script ini secara otomatis membandingkan git diff dari commit terakhir, mencari database mana yang berubah, lalu menjalankan deploy hanya ke database & IP tersebut.

#### 1. Cara Konfigurasi `.env` di Agen Bamboo:
Definisikan semua variabel koneksi database per-layanan:
```env
# Database db1
DB_DB1_HOST=172.24.169.100
DB_DB1_USER=root
DB_DB1_PASS=securepass_db1

# Database db_payment
DB_DB_PAYMENT_HOST=172.24.169.105
DB_DB_PAYMENT_USER=root
DB_DB_PAYMENT_PASS=securepass_payment
```

#### 2. Jalankan di Task Bamboo (Script Task):
Cukup panggil script detektor dengan menyertakan range commit (di Bamboo, kita bisa bandingkan `HEAD~1`):
```bash
./scripts/deploy-changed.sh HEAD~1
```

Script akan mengeluarkan output seperti berikut jika mendeteksi adanya penambahan SQL di folder `db1`:
```
==================================================
 Database Deployment Detector
 Commit Range: HEAD~1
==================================================
Database yang terdeteksi mengalami perubahan:
  📍 Database: db1  |  Versi: v.1.0
==================================================
🚀 Memulai deploy untuk database: db1 (v.1.0)...
...
✅ Berhasil deploy database: db1 (v.1.0)
--------------------------------------------------
🎉 Semua proses deployment database selesai!
```

---

## 15. GitHub Actions (CI/CD)

Setiap push ke branch `main` atau `staging` dapat dikonfigurasi untuk menjalankan migrasi skema database secara otomatis.

### Setup GitHub Secrets

Buka repository GitHub → **Settings** → **Secrets and variables** → **Actions**:
- `DB_URL`
- `DB_USERNAME`
- `DB_PASSWORD`

---

## 16. Troubleshooting

### ❌ `SAXParseException: The string "--" is not permitted within comments`

- **Penyebab:** XML melarang penggunaan double-hyphen `--` di dalam baris komentar `<!-- ... -->`.
- **Solusi:** Jalankan script helper `lb.sh` versi terbaru (`generate-master` sudah diformat agar aman dari double-hyphen).

### ❌ `option '--changelog-file' (PARAM) should be specified only once`

- **Penyebab:** Bentrokan pembacaan option di native Liquibase.
- **Solusi:** Jangan panggil command `liquibase` langsung. Gunakan helper `./scripts/lb.sh` yang otomatis mengisolasi properties lokal.

### ❌ `Liquibase does not support automatic rollback generation for raw sql changes`

- **Penyebab:** Perintah rollback dipanggil, tetapi changeset SQL tidak memiliki pasangan file rollback terdaftar di XML.
- **Solusi:** Pastikan file rollback `{PREFIX}-rollback.sql` ada di folder `rollback/` sebelum menjalankan `generate-master`.

---

## 17. Referensi Perintah Lengkap

### Format Perintah

```bash
./scripts/lb.sh [FLAGS] COMMAND [COMMAND_OPTIONS]
```

### Flags Global

| Flag | Contoh | Keterangan |
|---|---|---|
| `--external` | `--external` | Gunakan koneksi database external |
| `--db-name` | `--db-name=db1` | Nama database (sesuai folder di `liquibase/`) |
| `--ver` | `--ver=v.1.0` | Versi changelog yang dituju |
| `--host` | `--host=1.2.3.4` | Override host target |
| `--db` | `--db=target_db` | Override nama schema target |
| `--runner` | `--runner=native` | Gunakan runner `docker` atau `native` |

### Perintah Utama

| Perintah | Fungsi |
|---|---|
| `generate-master` | Scan `changes/` & `rollback/` lalu tulis ulang master XML |
| `update` | Jalankan semua migrasi pending |
| `updateSQL` | Preview SQL migrasi pending (dry-run) |
| `status` | Tampilkan changeset pending |
| `history` | Tampilkan riwayat migrasi yang sudah masuk |
| `rollback-count --count=N` | Rollback sejumlah N changeset terakhir |
| `rollback --tag=TAG` | Rollback skema ke checkpoint tag tertentu |
| `tag --tag=TAG` | Beri tag checkpoint pada database |
| `changelogSync` | Tandai semua changeset sebagai executed di DB (tanpa eksekusi SQL) |
| `clearCheckSums` | Reset checksum changeset |
| `dropAll` | Bersihkan database target (Hapus semua tabel & objek) |
