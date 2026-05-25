# Liquibase + GitHub Actions CI/CD

Setup lengkap Liquibase database migration dengan Docker lokal dan GitHub Actions pipeline untuk staging & production.

## Struktur Project

```
.
├── .github/
│   └── workflows/
│       └── liquibase.yml          # CI/CD pipeline
├── docker/
│   ├── liquibase/
│   │   └── Dockerfile             # Custom image dengan MySQL JDBC driver
│   └── mysql/
│       └── init/
│           └── 00-init.sql        # Optional init script
├── liquibase/
│   ├── changelog/
│   │   ├── db.changelog-master.xml
│   │   └── changes/
│   │       ├── v1.0/
│   │       │   ├── 001-create-users-table.sql
│   │       │   └── 002-create-orders-table.sql
│   │       └── v1.1/
│   │           └── 001-add-email-column.sql
│   ├── liquibase.docker.properties   # Untuk Docker lokal (jangan di-commit jika ada secret)
│   └── liquibase.properties          # Template CI (safe to commit, pakai env vars)
├── scripts/
│   └── lb.sh                         # Helper script untuk CLI lokal
├── docker-compose.yml
└── README.md
```

---

## 🐳 Quick Start — Local Docker

### 1. Jalankan MySQL + Adminer

```bash
docker compose up -d mysql adminer
```

### 2. Jalankan Migrasi

```bash
# Build image Liquibase (hanya pertama kali)
DOCKER_BUILDKIT=0 docker compose build liquibase

# Jalankan update (apply semua pending changeset)
docker compose run --rm liquibase
```

Atau gunakan helper script:

```bash
chmod +x scripts/lb.sh

./scripts/lb.sh update        # Apply migrasi
./scripts/lb.sh status        # Lihat changeset pending
./scripts/lb.sh updateSQL     # Preview SQL tanpa apply
./scripts/lb.sh validate      # Validasi format changelog
./scripts/lb.sh rollback --rollbackCount=1   # Rollback 1 changeset
```

### 3. Buka Adminer (GUI Database)

- URL: **http://localhost:8080**
- System: `MySQL`
- Server: `mysql`
- Username: `liquibase_user`
- Password: `liquibase_pass`
- Database: `liquibase_dev`

### 4. Stop & Cleanup

```bash
docker compose down              # Stop containers (data tetap)
docker compose down -v           # Stop + hapus volume (reset DB)
```

---

## ✍️ Cara Tambah Changeset Baru

1. Buat file SQL baru di folder version yang sesuai:

```
liquibase/changelog/changes/v1.2/001-add-phone-column.sql
```

2. Format wajib:

```sql
--liquibase formatted sql

--changeset developer:001-add-phone-column labels:v1.2 context:all
ALTER TABLE users ADD COLUMN phone VARCHAR(20) NULL;
--rollback ALTER TABLE users DROP COLUMN phone;
```

> ⚠️ **Aturan penting:**
> - Baris pertama **harus** `--liquibase formatted sql` (tanpa spasi, tanpa komentar sebelumnya)
> - `--changeset` langsung setelah baris header, tanpa comment block di antaranya
> - **Jangan edit** changeset yang sudah di-apply — Liquibase tracking pakai checksum MD5
> - **Selalu buat** `--rollback` untuk setiap changeset

3. Test lokal dulu:

```bash
./scripts/lb.sh updateSQL   # Preview
./scripts/lb.sh update      # Apply
```

---

## 🔄 GitHub Actions CI/CD

### Alur Kerja

```
Developer push ke branch staging
        ↓
  [🔍 Validate] — cek changelog valid (pakai MySQL ephemeral di runner)
  [📋 updateSQL] — dry-run preview SQL
        ↓
  [🚀 Deploy Staging] — apply migrasi ke DB staging
        ↓
  Merge PR ke main
        ↓
  [🔍 Validate] ✅
        ↓
  ⏳ Tunggu approval manual (GitHub Environment protection)
        ↓
  [🏭 Deploy Production] 🚀 apply migrasi ke DB prod
```

### Setup GitHub Secrets

Pergi ke **Settings → Secrets and variables → Actions**, tambahkan:

| Secret Name | Contoh Value |
|---|---|
| `DB_USERNAME` | `liquibase_user` |
| `DB_PASSWORD` | `yourpassword` |
| `DB_URL_STAGING` | `jdbc:mysql://host:3306/db_staging?useSSL=true` |
| `DB_USERNAME_PROD` | `liquibase_prod` |
| `DB_PASSWORD_PROD` | `prodpassword` |
| `DB_URL_PROD` | `jdbc:mysql://host:3306/db_prod?useSSL=true` |

### Setup Manual Approval untuk Production

1. Pergi ke **Settings → Environments → production**
2. Aktifkan **"Required reviewers"**
3. Tambahkan reviewer yang harus approve sebelum deploy ke production

---

## 🗃️ Konfigurasi Koneksi

| File | Digunakan Saat |
|---|---|
| `liquibase.docker.properties` | Local Docker (`docker compose run`) |
| `liquibase.properties` | CI/CD (nilai dari env vars) |

---

## 💡 Tips

- Gunakan `labels` dan `context` di changeset untuk filter eksekusi per environment
- Jalankan `./scripts/lb.sh status` sebelum apply untuk melihat apa yang akan dijalankan
- DATABASECHANGELOG dan DATABASECHANGELOGLOCK adalah tabel sistem Liquibase — jangan dihapus
