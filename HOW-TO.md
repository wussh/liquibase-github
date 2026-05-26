# HOW-TO: Liquibase + Docker + GitHub Actions

Panduan langkah demi langkah — dari setup awal sampai deploy production.

---

## Daftar Isi

1. [Prerequisites](#1-prerequisites)
2. [Setup Pertama Kali (Local)](#2-setup-pertama-kali-local)
3. [Membuat Changeset Baru](#3-membuat-changeset-baru)
4. [Menjalankan Migrasi Lokal](#4-menjalankan-migrasi-lokal)
5. [Rollback Changeset](#5-rollback-changeset)
6. [Setup GitHub Secrets](#6-setup-github-secrets)
7. [Setup Environment Protection (Manual Approval)](#7-setup-environment-protection-manual-approval)
8. [Deploy via GitHub Actions](#8-deploy-via-github-actions)
9. [Onboarding DB yang Sudah Ada (Existing Database)](#9-onboarding-db-yang-sudah-ada-existing-database)
10. [Troubleshooting](#10-troubleshooting)
11. [Referensi Perintah](#11-referensi-perintah)

---

## 1. Prerequisites

Pastikan tools berikut sudah terinstall di mesin lokal:

| Tool | Versi Minimal | Cek |
|---|---|---|
| Docker | 20.x | `docker --version` |
| Docker Compose | v2.x | `docker compose version` |
| Git | 2.x | `git --version` |

> [!NOTE]
> Liquibase **tidak perlu diinstall** secara lokal — semua dijalankan via Docker container.

---

## 2. Setup Pertama Kali (Local)

### Langkah 1 — Clone Repository

```bash
git clone <url-repo>
cd liquibase-github
```

### Langkah 2 — Build Custom Liquibase Image

Image ini berisi Liquibase + MySQL JDBC driver (hanya perlu sekali):

```bash
DOCKER_BUILDKIT=0 docker compose build liquibase
```

Verifikasi image berhasil dibuat:

```bash
docker images | grep liquibase-mysql
# liquibase-mysql   4.27   ...
```

### Langkah 3 — Jalankan MySQL & Adminer

```bash
docker compose up -d mysql adminer
```

Cek status container:

```bash
docker compose ps
# NAME                 STATUS
# liquibase-adminer    Up
# liquibase-mysql      Up (healthy)
```

> [!IMPORTANT]
> Tunggu sampai status MySQL menjadi `(healthy)` sebelum menjalankan migrasi.
> Biasanya butuh 15–30 detik pertama kali.

### Langkah 4 — Jalankan Migrasi Pertama

```bash
docker compose run --rm liquibase
```

Output sukses akan terlihat seperti:

```
Running Changeset: changelog/changes/v1.0/001-create-users-table.sql::001-create-users-table::developer
Running Changeset: changelog/changes/v1.0/002-create-orders-table.sql::002-create-orders-table::developer
Running Changeset: changelog/changes/v1.1/001-add-email-column.sql::003-add-email-column::developer

UPDATE SUMMARY
Run:                          3
Previously run:               0
Total change sets:            3

Liquibase command 'update' was executed successfully.
```

### Langkah 5 — Verifikasi via Adminer

Buka browser: **http://localhost:8080**

| Field | Value |
|---|---|
| System | MySQL |
| Server | `mysql` |
| Username | `liquibase_user` |
| Password | `liquibase_pass` |
| Database | `liquibase_dev` |

Tabel yang seharusnya ada:
- `users` — tabel aplikasi
- `orders` — tabel aplikasi
- `DATABASECHANGELOG` — tracking changeset Liquibase
- `DATABASECHANGELOGLOCK` — lock saat migrasi berjalan

---

## 3. Membuat Changeset Baru

### Aturan Penamaan File

```
liquibase/changelog/changes/<versi>/<nomor>-<deskripsi>.sql
```

Contoh:
```
changes/v1.2/001-add-phone-column.sql
changes/v1.2/002-create-products-table.sql
changes/v2.0/001-add-index-users-email.sql
```

> [!IMPORTANT]
> File dieksekusi **secara alfabetikal** dalam setiap folder versi.
> Selalu gunakan prefix angka (`001-`, `002-`) agar urutan terjaga.

### Format Wajib SQL Changeset

```sql
--liquibase formatted sql

--changeset <author>:<unique-id> labels:<versi> context:all
<SQL STATEMENT>;
--rollback <SQL UNTUK UNDO>;
```

### Contoh: Tambah Kolom

```sql
--liquibase formatted sql

--changeset developer:004-add-phone-column labels:v1.2 context:all
ALTER TABLE users ADD COLUMN phone VARCHAR(20) NULL AFTER email;
--rollback ALTER TABLE users DROP COLUMN phone;
```

### Contoh: Buat Tabel Baru

```sql
--liquibase formatted sql

--changeset developer:005-create-products-table labels:v1.2 context:all
CREATE TABLE products (
    id         BIGINT          NOT NULL AUTO_INCREMENT,
    name       VARCHAR(200)    NOT NULL,
    price      DECIMAL(12, 2)  NOT NULL DEFAULT 0.00,
    stock      INT             NOT NULL DEFAULT 0,
    created_at TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_products PRIMARY KEY (id)
);
--rollback DROP TABLE IF EXISTS products;
```

### Contoh: Buat Index

```sql
--liquibase formatted sql

--changeset developer:006-add-index-users-email labels:v1.2 context:all
CREATE INDEX idx_users_email ON users (email);
--rollback DROP INDEX idx_users_email ON users;
```

### Contoh: Multiple Statement dalam Satu Changeset

```sql
--liquibase formatted sql

--changeset developer:007-seed-default-data labels:v1.2 context:all runOnChange:false
INSERT INTO products (name, price, stock) VALUES ('Product A', 10000.00, 100);
INSERT INTO products (name, price, stock) VALUES ('Product B', 25000.00, 50);
--rollback DELETE FROM products WHERE name IN ('Product A', 'Product B');
```

> [!WARNING]
> **Jangan pernah edit changeset yang sudah di-apply!**
> Liquibase menyimpan checksum MD5 setiap changeset.
> Jika checksum berubah, Liquibase akan error dan menolak menjalankan migrasi.

---

## 4. Menjalankan Migrasi Lokal

Gunakan helper script `scripts/lb.sh`. Script otomatis mendeteksi runner yang tersedia:

| Kondisi | Runner yang Dipakai |
|---|---|
| Docker tersedia & daemon running | **Docker** (default) |
| Docker tidak ada / daemon mati | **Native binary** `liquibase` (fallback) |
| `--runner=docker` | Paksa Docker (error jika tidak ada) |
| `--runner=native` | Paksa native binary (error jika tidak ada) |

> [!NOTE]
> Untuk menggunakan native binary, install Liquibase terlebih dahulu:
> [docs.liquibase.com/start/install/home.html](https://docs.liquibase.com/start/install/home.html)

### Lihat Changeset yang Belum Dijalankan

```bash
./scripts/lb.sh status
```

### Preview SQL (Tanpa Apply)

```bash
./scripts/lb.sh updateSQL
```

Output berupa SQL yang akan dieksekusi — gunakan ini untuk review sebelum apply.

### Apply Migrasi

```bash
./scripts/lb.sh update
# atau langsung via docker compose:
docker compose run --rm liquibase
```

### Validasi Format Changelog

```bash
./scripts/lb.sh validate
```

Gunakan sebelum push ke GitHub untuk memastikan format changeset benar.

### Lihat History Changeset yang Sudah Dijalankan

```bash
./scripts/lb.sh history
```

### Override Runner

```bash
# Paksa pakai Docker
./scripts/lb.sh --runner=docker update

# Paksa pakai native binary
./scripts/lb.sh --runner=native update
```

---

## 5. Rollback Changeset

> [!CAUTION]
> Rollback akan **mengubah data database**. Selalu backup terlebih dahulu di environment production.

### Rollback N Changeset Terakhir

```bash
# Rollback 1 changeset terakhir
./scripts/lb.sh rollback-count --count=1

# Rollback 3 changeset terakhir
./scripts/lb.sh rollback-count --count=3
```

### Rollback ke Tag Tertentu

Tambahkan tag di changeset:

```sql
--changeset developer:tag-v1.1 labels:v1.1 context:all
--comment: tag sebelum rilis v1.1
--rollback empty
```

Lalu rollback ke tag tersebut:

```bash
./scripts/lb.sh rollback --rollbackToTag=v1.1
```

### Rollback ke Tanggal Tertentu

```bash
./scripts/lb.sh rollback --rollbackToDate=2024-01-01
```

---

## 6. Setup GitHub Secrets

### Cara Tambah Secret

1. Buka repository di GitHub
2. Klik **Settings** → **Secrets and variables** → **Actions**
3. Klik **New repository secret**
4. Isi nama dan value, klik **Add secret**

### Daftar Secret yang Dibutuhkan

| Secret Name | Keterangan | Contoh Value |
|---|---|---|
| `DB_USERNAME` | Username DB staging | `liquibase_user` |
| `DB_PASSWORD` | Password DB staging | `StrongPass123!` |
| `DB_URL_STAGING` | JDBC URL staging | `jdbc:mysql://db-staging.example.com:3306/app_staging?useSSL=true&serverTimezone=UTC` |
| `DB_USERNAME_PROD` | Username DB production | `liquibase_prod` |
| `DB_PASSWORD_PROD` | Password DB production | `VeryStrongPass456!` |
| `DB_URL_PROD` | JDBC URL production | `jdbc:mysql://db-prod.example.com:3306/app_prod?useSSL=true&serverTimezone=UTC` |

### Format JDBC URL

```
jdbc:mysql://<HOST>:<PORT>/<DATABASE>?useSSL=true&allowPublicKeyRetrieval=true&serverTimezone=UTC
```

Untuk PostgreSQL:
```
jdbc:postgresql://<HOST>:<PORT>/<DATABASE>?sslmode=require
```

---

## 7. Setup Environment Protection (Manual Approval)

Agar deploy ke production butuh approval manual:

1. Buka repository di GitHub
2. Klik **Settings** → **Environments**
3. Klik **New environment**, beri nama `production`
4. Di halaman environment, aktifkan **"Required reviewers"**
5. Tambahkan username atau tim yang bisa approve
6. Klik **Save protection rules**

> [!NOTE]
> Workflow akan **berhenti dan menunggu** di job `deploy-production` sampai reviewer menyetujui.
> Reviewer akan mendapat notifikasi email dari GitHub.

---

## 8. Deploy via GitHub Actions

### Deploy ke Staging

```bash
# Buat atau checkout branch staging
git checkout -b staging
# atau
git checkout staging

# Buat changeset baru (lihat bagian 3)
# ...

# Commit dan push
git add liquibase/changelog/changes/v1.2/001-add-phone-column.sql
git commit -m "feat: add phone column to users table"
git push origin staging
```

Pipeline akan otomatis berjalan:
1. ✅ **Validate** — cek format changelog (pakai MySQL ephemeral di runner)
2. 📋 **updateSQL** — tampilkan dry-run SQL di log Actions
3. 🚀 **Deploy Staging** — apply migrasi ke DB staging

### Deploy ke Production

```bash
# Merge staging ke main via Pull Request di GitHub
# Setelah PR diapprove dan di-merge:

git checkout main
git pull origin main
```

Pipeline akan berjalan:
1. ✅ **Validate**
2. ⏳ **Tunggu approval** dari reviewer
3. 🏭 **Deploy Production** — apply migrasi ke DB production

### Monitor Pipeline

- Buka tab **Actions** di repository GitHub
- Klik workflow run yang sedang berjalan
- Expand setiap job untuk melihat log detail

---

## 9. Onboarding DB yang Sudah Ada (Existing Database)

> [!IMPORTANT]
> Gunakan section ini jika kamu sudah punya database dengan tabel-tabel yang berjalan
> dan ingin mulai menggunakan Liquibase **tanpa menghapus atau membuat ulang** database tersebut.

### Gambaran Alur

```
DB Existing (sudah ada tabel)
    │
    ▼
[1] generateChangelog  ──▶  000-baseline.sql (DDL semua objek existing)
    │
    ▼
[2] changelogSync      ──▶  Isi DATABASECHANGELOG (tandai baseline sebagai "done")
    │
    ▼
[3] Buat changeset baru normal (v1.1, v1.2, dst.)
    │
    ▼
[4] liquibase update   ──▶  Hanya jalankan changeset BARU saja
```

---

### Koneksi ke DB Existing dengan Flag `--external`

Script `lb.sh` mendukung mode **external** untuk connect ke database yang berada di luar Docker internal (misalnya server lain, VM, atau cloud RDS).

#### Cara 1 — Via File `.env` ⭐ (Direkomendasikan)

Buat file `.env` di root project dari template yang sudah tersedia:

```bash
cp .env.example .env
```

Edit file `.env` sesuai koneksi database kamu:

```bash
# .env
EXT_DB_HOST=192.168.1.100
EXT_DB_PORT=3306
EXT_DB_NAME=myapp_db
EXT_DB_USER=admin
EXT_DB_PASS=secret
```

Setelah itu cukup jalankan perintah tanpa perlu set env var apapun:

```bash
./scripts/lb.sh --external status
./scripts/lb.sh --external update
```

> [!CAUTION]
> File `.env` sudah masuk `.gitignore` — **jangan pernah commit `.env` ke Git**
> karena berisi kredensial database. Gunakan `.env.example` sebagai template yang aman untuk di-commit.

---

#### Cara 2 — Via Environment Variable (Inline)

Set env var langsung sebelum perintah (berguna untuk CI/CD atau one-time):

```bash
EXT_DB_HOST=192.168.1.100 \
EXT_DB_PORT=3306 \
EXT_DB_NAME=myapp_db \
EXT_DB_USER=admin \
EXT_DB_PASS=secret \
./scripts/lb.sh --external status
```

| Env Var | Keterangan | Default |
|---|---|---|
| `EXT_DB_HOST` | Host/IP database | `127.0.0.1` |
| `EXT_DB_PORT` | Port database | `3306` |
| `EXT_DB_NAME` | Nama database | `liquibase_dev` |
| `EXT_DB_USER` | Username | `liquibase_user` |
| `EXT_DB_PASS` | Password | `liquibase_pass` |

#### Cara 3 — Via Flag Inline

```bash
./scripts/lb.sh --external --host=192.168.1.100 --db=myapp_db update
```

> [!NOTE]
> Flag `--host` dan `--db` bisa dikombinasikan dengan env var atau `.env`.
> Prioritas override: **Flag inline** > **Env var** > **Nilai dari `.env`** > **Default**.

#### Cara 4 — DB di Host Machine (localhost)

Jika database jalan langsung di mesin kamu (bukan di Docker):

```bash
# Cukup set di .env:
EXT_DB_HOST=127.0.0.1
EXT_DB_NAME=myapp_local
EXT_DB_USER=root
EXT_DB_PASS=rootpass
```

Lalu:

```bash
./scripts/lb.sh --external status
```

> [!NOTE]
> Mode `--external` otomatis menggunakan `--network=host` di Docker,
> sehingga container Liquibase bisa menjangkau database di host machine atau jaringan LAN.

---

### Langkah 1 — Generate Baseline Changelog dari DB Existing

Liquibase akan connect ke database existing, membaca semua tabel, kolom, index, dan foreign key, lalu menuangkannya ke file changelog:

```bash
# Ke Docker internal
./scripts/lb.sh generateChangeLog --changelogFile=changelog/changes/v1.0/000-baseline.sql

# Ke DB external
EXT_DB_HOST=192.168.1.100 EXT_DB_NAME=myapp_db EXT_DB_USER=admin EXT_DB_PASS=secret \
./scripts/lb.sh --external generateChangeLog --changelogFile=changelog/changes/v1.0/000-baseline.sql
```

File `000-baseline.sql` yang dihasilkan akan berisi DDL semua objek yang sudah ada, misalnya:

```sql
--liquibase formatted sql

--changeset liquibase-generated:1 labels:v1.0 context:all
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    name       VARCHAR(100) NOT NULL,
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_users PRIMARY KEY (id)
);
--rollback DROP TABLE IF EXISTS users;

--changeset liquibase-generated:2 labels:v1.0 context:all
CREATE TABLE orders (
    id         BIGINT    NOT NULL AUTO_INCREMENT,
    user_id    BIGINT    NOT NULL,
    total      DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_orders PRIMARY KEY (id)
);
--rollback DROP TABLE IF EXISTS orders;
```

> [!NOTE]
> Review file hasil generate ini sebelum lanjut — pastikan semua tabel dan kolom sudah tercapture dengan benar.

---

### Langkah 2 — Sync Changelog ke DB (Tanpa Eksekusi SQL)

Karena tabel-tabel tersebut **sudah ada** di database, kita perlu memberi tahu Liquibase bahwa changeset baseline sudah "pernah dijalankan" — tanpa benar-benar mengeksekusi DDL-nya:

```bash
# Ke Docker internal
./scripts/lb.sh changelogSync

# Ke DB external
EXT_DB_HOST=192.168.1.100 EXT_DB_NAME=myapp_db EXT_DB_USER=admin EXT_DB_PASS=secret \
./scripts/lb.sh --external changelogSync
```

Perintah ini akan:
- Membuat tabel `DATABASECHANGELOG` dan `DATABASECHANGELOGLOCK` jika belum ada
- Mengisi `DATABASECHANGELOG` dengan semua entry dari baseline changelog
- **Tidak mengeksekusi satu pun SQL DDL** (tabel tidak disentuh)

Verifikasi hasilnya:

```bash
# Cek history di DB external
EXT_DB_HOST=192.168.1.100 EXT_DB_NAME=myapp_db EXT_DB_USER=admin EXT_DB_PASS=secret \
./scripts/lb.sh --external history
# OUTPUT:
# ID: 1  Author: liquibase-generated  File: 000-baseline.sql  Status: EXECUTED
# ID: 2  Author: liquibase-generated  File: 000-baseline.sql  Status: EXECUTED
```

---

### Langkah 3 — Verifikasi Status

Pastikan tidak ada changeset yang pending (semua sudah ter-sync):

```bash
./scripts/lb.sh --external status
# OUTPUT:
# liquibase-github is up to date
# 0 change sets have not been applied
```

---

### Langkah 4 — Mulai Buat Changeset Baru Seperti Biasa

Setelah baseline ter-sync, kamu bisa lanjut membuat changeset baru untuk perubahan ke depannya:

```bash
# Buat folder versi berikutnya
mkdir -p liquibase/changelog/changes/v1.1

# Buat changeset baru
cat > liquibase/changelog/changes/v1.1/001-add-email-column.sql << 'EOF'
--liquibase formatted sql

--changeset developer:v1.1-001-add-email-column labels:v1.1 context:all
ALTER TABLE users ADD COLUMN email VARCHAR(255) NULL AFTER name;
--rollback ALTER TABLE users DROP COLUMN email;
EOF

# Apply ke DB external
EXT_DB_HOST=192.168.1.100 EXT_DB_NAME=myapp_db EXT_DB_USER=admin EXT_DB_PASS=secret \
./scripts/lb.sh --external update
```

> [!WARNING]
> **Jangan edit file `000-baseline.sql`** setelah `changelogSync` dijalankan.
> Liquibase menyimpan checksum MD5 — mengubah file akan menyebabkan error `Checksum mismatch`.

---

### Alternatif: `changelogSyncSQL` untuk Preview Dulu

Jika ingin melihat SQL yang akan diinsert ke `DATABASECHANGELOG` sebelum benar-benar dijalankan:

```bash
# Docker internal
./scripts/lb.sh changelogSyncSQL

# DB external
./scripts/lb.sh --external changelogSyncSQL
```

Output berupa `INSERT INTO DATABASECHANGELOG ...` — cocok untuk review atau audit.

---

### Ringkasan Pilihan Command untuk Existing DB

| Situasi | Command |
|---|---|
| DB sudah ada schema, mau mulai track | `--external changelogSync` |
| Belum ada changelog, generate dari DB | `--external generateChangeLog` |
| Preview SQL sync sebelum dijalankan | `--external changelogSyncSQL` |
| Apply migration baru ke existing DB | `--external update` |
| Cek status migration di existing DB | `--external status` |
| Lihat riwayat migration di existing DB | `--external history` |

---

## 10. Troubleshooting

### ❌ Error: `Cannot find database driver`

**Penyebab:** Image Liquibase standar tidak include MySQL JDBC driver.

**Solusi:** Rebuild custom image:
```bash
DOCKER_BUILDKIT=0 docker compose build --no-cache liquibase
```

---

### ❌ Error: `Unexpected formatting in formatted changelog`

**Penyebab:** Ada komentar `--` setelah `--liquibase formatted sql` sebelum `--changeset`.

**Salah:**
```sql
--liquibase formatted sql

-- Ini komentar yang TIDAK boleh ada di sini
--changeset developer:001 ...
```

**Benar:**
```sql
--liquibase formatted sql

--changeset developer:001 labels:v1.0 context:all
```

---

### ❌ Error: `Checksum mismatch`

**Penyebab:** Changeset yang sudah di-apply diedit/diubah.

**Solusi:**
```bash
# Jangan edit changeset lama — buat changeset baru untuk perubahan
# Jika terpaksa di lokal (DEV ONLY):
./scripts/lb.sh clearCheckSums
./scripts/lb.sh update
```

> [!CAUTION]
> `clearCheckSums` hanya boleh dijalankan di environment development. **Jangan di production.**

---

### ❌ MySQL container tidak `healthy`

```bash
# Cek log MySQL
docker logs liquibase-mysql

# Cek status health
docker inspect liquibase-mysql --format '{{.State.Health.Status}}'

# Force restart
docker compose restart mysql
```

---

### ❌ Error di GitHub Actions: `Connection refused`

**Penyebab:** Secret `DB_URL_*` salah atau database tidak bisa diakses dari GitHub runner.

**Cek:**
- Pastikan firewall/security group mengizinkan koneksi dari GitHub Actions IP ranges
- Pastikan format JDBC URL benar
- Coba `ping` / `telnet` ke host:port dari dalam runner

---

## 11. Referensi Perintah

### Helper Script `./scripts/lb.sh` — Auto-detect Runner

Script otomatis memilih **Docker** jika tersedia, fallback ke **native binary** `liquibase`.

```bash
./scripts/lb.sh update                         # Apply semua pending changeset
./scripts/lb.sh updateSQL                      # Preview SQL tanpa apply
./scripts/lb.sh status                         # Lihat changeset yang belum dijalankan
./scripts/lb.sh validate                       # Validasi format changelog
./scripts/lb.sh history                        # Lihat riwayat changeset
./scripts/lb.sh rollback-count --count=1        # Rollback 1 changeset terakhir
./scripts/lb.sh rollback --rollbackToTag=v1.1  # Rollback ke tag
./scripts/lb.sh clearCheckSums                 # Reset checksum (DEV ONLY!)
./scripts/lb.sh diff                           # Bandingkan skema DB dengan changelog
./scripts/lb.sh generateChangeLog              # Generate changelog dari DB
./scripts/lb.sh changelogSync                  # Sync changelog tanpa eksekusi SQL
./scripts/lb.sh changelogSyncSQL               # Preview SQL sync
```

### Override Runner

```bash
./scripts/lb.sh --runner=docker update         # Paksa Docker
./scripts/lb.sh --runner=native update         # Paksa native binary
```

### Mode External DB

```bash
# Semua perintah bisa dikombinasikan dengan --external
./scripts/lb.sh --external update
./scripts/lb.sh --external status
./scripts/lb.sh --external history
./scripts/lb.sh --external generateChangeLog
./scripts/lb.sh --external changelogSync

# Override host & db via flag
./scripts/lb.sh --external --host=192.168.1.100 --db=myapp_db update

# Override via env var
EXT_DB_HOST=192.168.1.100 \
EXT_DB_NAME=myapp_db \
EXT_DB_USER=admin \
EXT_DB_PASS=secret \
./scripts/lb.sh --external update

# Kombinasi: native runner + external DB
./scripts/lb.sh --runner=native --external update
```

### Docker Compose

```bash
docker compose up -d mysql adminer          # Start MySQL + Adminer
docker compose run --rm liquibase           # Jalankan migrasi
docker compose build liquibase              # Rebuild custom Liquibase image
docker compose ps                           # Status container
docker compose logs -f mysql                # Tail log MySQL
docker compose down                         # Stop (data tetap)
docker compose down -v                      # Stop + hapus semua data (reset DB)
```

### MySQL CLI di Container

```bash
# Masuk ke MySQL shell
docker exec -it liquibase-mysql mysql -u liquibase_user -pliquibase_pass liquibase_dev

# Query singkat
docker exec liquibase-mysql mysql -u liquibase_user -pliquibase_pass liquibase_dev \
  -e "SELECT * FROM DATABASECHANGELOG ORDER BY DATEEXECUTED;"
```

---

> 📚 Dokumentasi resmi: [docs.liquibase.com](https://docs.liquibase.com)
