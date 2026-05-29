#!/usr/bin/env bash
# ==============================================================================
# Script Deteksi & Deploy Otomatis Database Berdasarkan Perubahan Commit (Git)
#
# Cara Kerja:
#   1. Memeriksa file .sql baru/berubah di: liquibase/{DB_NAME}/{VER}/changes/
#   2. Mengekstrak DB_NAME dan VER.
#   3. Menjalankan generate-master dan update ke database yang sesuai.
#
# Cara Pakai di CI/CD (Bamboo):
#   ./scripts/deploy-changed.sh HEAD~1
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Tentukan commit range (default: bandingkan commit terakhir HEAD~1 dengan HEAD)
COMMIT_RANGE="${1:-HEAD~1}"

echo "=================================================="
echo " Database Deployment Detector"
echo " Commit Range: $COMMIT_RANGE"
echo "=================================================="

# Ambil daftar file .sql yang berubah di folder changes/
# Filter regex untuk memastikan folder berstruktur: liquibase/{DB}/{VER}/changes/*.sql
CHANGED_FILES=$(git diff --name-only "$COMMIT_RANGE" -- "liquibase/*/*/changes/*.sql" 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "✅ Tidak ada perubahan database yang terdeteksi di commit range ini."
  exit 0
fi

# Ekstrak database & versi unik ke dalam associative array untuk menghindari duplikasi
declare -A TARGETS

while IFS= read -r file; do
  if [ -n "$file" ] && [[ "$file" =~ ^liquibase/([^/]+)/([^/]+)/changes/ ]]; then
    DB="${BASH_REMATCH[1]}"
    VER="${BASH_REMATCH[2]}"
    TARGETS["$DB:$VER"]=1
  fi
done <<< "$CHANGED_FILES"

echo "Database yang terdeteksi mengalami perubahan:"
for key in "${!TARGETS[@]}"; do
  IFS=":" read -r DB VER <<< "$key"
  echo "  📍 Database: $DB  |  Versi: $VER"
done
echo "=================================================="

# Eksekusi migrasi untuk setiap database & versi yang terdeteksi
for key in "${!TARGETS[@]}"; do
  IFS=":" read -r DB VER <<< "$key"
  
  echo "🚀 Memulai deploy untuk database: $DB ($VER)..."
  
  # 1. Pastikan XML master diperbarui secara otomatis
  "$SCRIPT_DIR/lb.sh" --db-name="$DB" --ver="$VER" generate-master
  
  # 2. Terapkan migrasi ke database external target
  # (Koneksi host/user/pass otomatis di-resolve oleh lb.sh dari .env)
  "$SCRIPT_DIR/lb.sh" --external --db-name="$DB" --ver="$VER" update
  
  echo "✅ Berhasil deploy database: $DB ($VER)"
  echo "--------------------------------------------------"
done

echo "🎉 Semua proses deployment database selesai!"
