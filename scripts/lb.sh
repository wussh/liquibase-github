#!/usr/bin/env bash
# =============================================================
# Liquibase Local Helper — Docker (utama) atau native binary (fallback)
#
# MODE DEFAULT (Docker internal):
#   ./scripts/lb.sh update
#   ./scripts/lb.sh status
#   ./scripts/lb.sh validate
#   ./scripts/lb.sh updateSQL
#   ./scripts/lb.sh history
#   ./scripts/lb.sh rollback-count --count=1
#   ./scripts/lb.sh rollback --tag=v1.1
#   ./scripts/lb.sh clearCheckSums
#   ./scripts/lb.sh diff
#   ./scripts/lb.sh generateChangeLog
#   ./scripts/lb.sh changelogSync
#   ./scripts/lb.sh dropAll
#
# GENERATE MASTER XML (tidak perlu koneksi DB):
#   ./scripts/lb.sh --db-name=MBTL_INT_COBA --ver=v1.0 generate-master
#   (Auto-scan changelog/changes/ + rollback/ → generate db.changelog-master.xml)
#
# MODE EXTERNAL DB (existing database):
#   Struktur folder: liquibase/{DB_NAME}/{VERSION}/changelog/db.changelog-master.xml
#
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 update
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 status
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 validate
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 updateSQL
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 history
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 rollback-count --count=1
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 rollback --tag=v1.0
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 clearCheckSums
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 diff
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 generateChangeLog
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 changelogSync
#   ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 dropAll
#
#   Override host/db connection via .env atau env var:
#     EXT_DB_HOST=192.168.1.100 ./scripts/lb.sh --external --db-name=MBTL_INT_COBA --ver=v1.0 update
#
#   Atau via flag langsung:
#     ./scripts/lb.sh --external --host=192.168.1.100 --db=MBTL_INT_COBA --db-name=MBTL_INT_COBA --ver=v1.0 update
#
# RUNNER (auto-detect, bisa di-override):
#   Script otomatis pakai Docker jika tersedia, fallback ke binary 'liquibase'
#   Override manual:
#     ./scripts/lb.sh --runner=docker update
#     ./scripts/lb.sh --runner=native update
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Image & Network ──────────────────────────────────────────
LIQUIBASE_IMAGE="liquibase-mysql:4.27"
MYSQL_CONTAINER="liquibase-mysql"
NETWORK="liquibase-github_liquibase-net"

# ── Load .env jika ada (dari root project) ──────────────────
ENV_FILE="$ROOT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  # Hanya export baris yang valid (key=value), skip komentar & baris kosong
  set -o allexport
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +o allexport
fi

# ── Default koneksi (Docker internal) ───────────────────────
DB_URL="jdbc:mysql://mysql:3306/liquibase_dev?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
DB_USER="liquibase_user"
DB_PASS="liquibase_pass"
CHANGELOG="changelog/db.changelog-master.xml"

# ── Parse flags ──────────────────────────────────────────────
EXTERNAL_MODE=false
OVERRIDE_HOST=""
OVERRIDE_DB=""
RUNNER_OVERRIDE=""   # kosong = auto-detect, "docker" atau "native"
DB_NAME=""           # nama folder database, misal: MBTL_INT_COBA
DB_VER=""            # versi changelog, misal: v1.0

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --external)
      EXTERNAL_MODE=true
      ;;
    --host=*)
      OVERRIDE_HOST="${arg#--host=}"
      ;;
    --db=*)
      OVERRIDE_DB="${arg#--db=}"
      ;;
    --db-name=*)
      DB_NAME="${arg#--db-name=}"
      ;;
    --ver=*)
      DB_VER="${arg#--ver=}"
      ;;
    --runner=*)
      RUNNER_OVERRIDE="${arg#--runner=}"
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

# Reset positional params tanpa flag custom
set -- "${ARGS[@]+"${ARGS[@]}"}"

OPERATION="${1:-update}"
shift || true   # sisa argumen diteruskan ke liquibase

# ── Resolusi path changelog berdasarkan --db-name dan --ver ──
# Jika --db-name dan --ver ditentukan, gunakan struktur:
#   liquibase/{DB_NAME}/{VERSION}/changelog/db.changelog-master.xml
if [ -n "$DB_NAME" ] && [ -n "$DB_VER" ]; then
  LB_WORKDIR="$ROOT_DIR/liquibase/$DB_NAME/$DB_VER"
  if [ ! -d "$LB_WORKDIR" ]; then
    echo "❌ Folder tidak ditemukan: $LB_WORKDIR"
    echo "   Pastikan folder liquibase/$DB_NAME/$DB_VER/ sudah ada."
    exit 1
  fi
  CHANGELOG="changelog/db.changelog-master.xml"
elif [ -n "$DB_NAME" ] || [ -n "$DB_VER" ]; then
  echo "❌ Flag --db-name dan --ver harus digunakan bersamaan."
  echo "   Contoh: --db-name=MBTL_INT_COBA --ver=v1.0"
  exit 1
else
  LB_WORKDIR="$ROOT_DIR/liquibase"
fi

# ── Perintah generate-master: tidak butuh koneksi DB ─────────
# Intercept sebelum deteksi runner & koneksi database
if [ "$OPERATION" = "generate-master" ]; then
  CHANGES_DIR="$LB_WORKDIR/changelog/changes"
  ROLLBACK_DIR="$LB_WORKDIR/rollback"
  MASTER_XML="$LB_WORKDIR/changelog/db.changelog-master.xml"

  if [ ! -d "$CHANGES_DIR" ]; then
    echo "❌ Folder tidak ditemukan: $CHANGES_DIR"
    exit 1
  fi

  # Ambil author dari git config, fallback ke 'developer'
  GIT_AUTHOR=$(git config user.name 2>/dev/null || echo "developer")

  # Kumpulkan file .sql di folder changes/ secara terurut
  SQL_FILES=()
  while IFS= read -r -d '' f; do
    SQL_FILES+=("$(basename "$f")")
  done < <(find "$CHANGES_DIR" -maxdepth 1 -name "*.sql" -print0 | sort -z)

  if [ ${#SQL_FILES[@]} -eq 0 ]; then
    echo "⚠️  Tidak ada file .sql di: $CHANGES_DIR"
    exit 1
  fi

  echo "═══════════════════════════════════════════════"
  echo " generate-master"
  echo " DB   : ${DB_NAME:-default}"
  echo " Ver  : ${DB_VER:-default}"
  echo " Src  : $CHANGES_DIR"
  echo " Out  : $MASTER_XML"
  echo "═══════════════════════════════════════════════"

  # Tulis XML header
  cat > "$MASTER_XML" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.9.xsd">

    <!--
        ⚠️  File ini di-generate OTOMATIS oleh:
              ./scripts/lb.sh --db-name=... --ver=... generate-master

           JANGAN diedit manual — perubahan akan tertimpa.

           Cara menambah changeset baru:
             1. Buat file SQL di : changelog/changes/000X-nama.sql
             2. Buat rollback di : rollback/000X-rollback.sql
             3. Jalankan        : ./scripts/lb.sh --db-name=... --ver=... generate-master
    -->
EOF

  COUNT=0
  WARN_COUNT=0

  for SQL_FILE in "${SQL_FILES[@]}"; do
    # Ambil prefix angka (misal "0001" dari "0001-create-table-users.sql")
    PREFIX=$(echo "$SQL_FILE" | grep -oE '^[0-9]+')
    CHANGESET_ID="${SQL_FILE%.sql}"

    # Cari file rollback yang cocok: {PREFIX}-rollback.sql
    ROLLBACK_FILE=""
    if [ -d "$ROLLBACK_DIR" ]; then
      ROLLBACK_FILE=$(find "$ROLLBACK_DIR" -maxdepth 1 -name "${PREFIX}-rollback.sql" 2>/dev/null | head -1)
    fi

    {
      echo ""
      echo "    <!-- ═══ ${CHANGESET_ID} ═══ -->"
      echo "    <changeSet id=\"${CHANGESET_ID}\" author=\"${GIT_AUTHOR}\">"
      echo "        <sqlFile path=\"changelog/changes/${SQL_FILE}\""
      echo "                 relativeToChangelogFile=\"true\""
      echo "                 splitStatements=\"true\""
      echo "                 endDelimiter=\";\"/>"

      if [ -n "$ROLLBACK_FILE" ]; then
        ROLLBACK_BASENAME=$(basename "$ROLLBACK_FILE")
        echo "        <rollback>"
        echo "            <sqlFile path=\"rollback/${ROLLBACK_BASENAME}\""
        echo "                     relativeToChangelogFile=\"true\""
        echo "                     splitStatements=\"true\""
        echo "                     endDelimiter=\";\"/>"
        echo "        </rollback>"
      else
        echo "        <!-- ⚠️  rollback/${PREFIX}-rollback.sql tidak ditemukan — empty rollback -->"
        echo "        <rollback/>"
        WARN_COUNT=$((WARN_COUNT + 1))
      fi

      echo "    </changeSet>"
    } >> "$MASTER_XML"

    # Status per file
    if [ -n "$ROLLBACK_FILE" ]; then
      echo "  ✅ $SQL_FILE  →  $(basename "$ROLLBACK_FILE")"
    else
      echo "  ⚠️  $SQL_FILE  →  rollback/${PREFIX}-rollback.sql (TIDAK DITEMUKAN)"
    fi

    COUNT=$((COUNT + 1))
  done

  echo "" >> "$MASTER_XML"
  echo "</databaseChangeLog>" >> "$MASTER_XML"

  echo ""
  echo "══════════════════════════════════"
  echo " ✅ Selesai! db.changelog-master.xml berhasil di-generate."
  echo "    Total changeset : $COUNT"
  [ "$WARN_COUNT" -gt 0 ] && \
    echo "    ⚠️  Missing rollback : $WARN_COUNT file (buat rollback/{PREFIX}-rollback.sql-nya!)"
  echo "══════════════════════════════════"
  exit 0
fi

# ── Deteksi runner (Docker atau native) ──────────────────────
USE_DOCKER=false
USE_NATIVE=false

if [ "$RUNNER_OVERRIDE" = "docker" ]; then
  if ! command -v docker &>/dev/null; then
    echo "❌ Docker tidak ditemukan. Install Docker atau gunakan --runner=native"
    exit 1
  fi
  USE_DOCKER=true
elif [ "$RUNNER_OVERRIDE" = "native" ]; then
  if ! command -v liquibase &>/dev/null; then
    echo "❌ Binary 'liquibase' tidak ditemukan di PATH."
    echo "   Install: https://docs.liquibase.com/start/install/home.html"
    exit 1
  fi
  USE_NATIVE=true
else
  # Auto-detect: coba Docker dulu, fallback ke native
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    USE_DOCKER=true
  elif command -v liquibase &>/dev/null; then
    USE_NATIVE=true
  else
    echo "❌ Tidak ditemukan runner yang tersedia."
    echo "   Opsi:"
    echo "   1. Install Docker  : https://docs.docker.com/get-docker/"
    echo "   2. Install Liquibase: https://docs.liquibase.com/start/install/home.html"
    exit 1
  fi
fi

RUNNER_LABEL="Docker"
if [ "$USE_NATIVE" = true ]; then
  RUNNER_LABEL="Native ($(command -v liquibase))"
fi

# ── Mode External DB ─────────────────────────────────────────
if [ "$EXTERNAL_MODE" = true ]; then
  # Jika --db-name ditentukan, coba baca variabel spesifik per-database:
  #   DB_{NAMA_DB}_HOST, DB_{NAMA_DB}_PORT, DB_{NAMA_DB}_NAME,
  #   DB_{NAMA_DB}_USER, DB_{NAMA_DB}_PASS
  # Jika tidak ada, fallback ke variabel global EXT_DB_*
  if [ -n "$DB_NAME" ]; then
    # Ubah karakter non-alphanumeric menjadi _ agar valid sebagai nama variabel
    DB_KEY=$(echo "$DB_NAME" | tr '[:lower:]' '[:upper:]' | tr -cs 'A-Z0-9' '_')

    # Baca nilai spesifik per-DB (pakai indirect variable expansion)
    _SPEC_HOST=$(eval echo "\${DB_${DB_KEY}_HOST:-}")
    _SPEC_PORT=$(eval echo "\${DB_${DB_KEY}_PORT:-}")
    _SPEC_NAME=$(eval echo "\${DB_${DB_KEY}_NAME:-}")
    _SPEC_USER=$(eval echo "\${DB_${DB_KEY}_USER:-}")
    _SPEC_PASS=$(eval echo "\${DB_${DB_KEY}_PASS:-}")

    # Gabungkan: spesifik per-DB > override flag > global EXT_DB_* > default
    EXT_HOST="${OVERRIDE_HOST:-${_SPEC_HOST:-${EXT_DB_HOST:-"127.0.0.1"}}}"
    EXT_PORT="${_SPEC_PORT:-${EXT_DB_PORT:-3306}}"
    EXT_NAME="${OVERRIDE_DB:-${_SPEC_NAME:-${EXT_DB_NAME:-"$DB_NAME"}}}"
    EXT_USER="${_SPEC_USER:-${EXT_DB_USER:-"liquibase_user"}}"
    EXT_PASS="${_SPEC_PASS:-${EXT_DB_PASS:-"liquibase_pass"}}"
  else
    EXT_HOST="${OVERRIDE_HOST:-${EXT_DB_HOST:-"127.0.0.1"}}"
    EXT_PORT="${EXT_DB_PORT:-3306}"
    EXT_NAME="${OVERRIDE_DB:-${EXT_DB_NAME:-"liquibase_dev"}}"
    EXT_USER="${EXT_DB_USER:-"liquibase_user"}"
    EXT_PASS="${EXT_DB_PASS:-"liquibase_pass"}"
  fi

  # Native mode: bisa pakai localhost langsung (tidak perlu host network trick)
  if [ "$USE_NATIVE" = true ]; then
    DB_URL="jdbc:mysql://${EXT_HOST}:${EXT_PORT}/${EXT_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&allowMultiQueries=true"
  else
    # Docker: jika host adalah localhost/127.0.0.1, gunakan host.docker.internal
    if [[ "$EXT_HOST" == "127.0.0.1" || "$EXT_HOST" == "localhost" ]]; then
      DB_URL="jdbc:mysql://host.docker.internal:${EXT_PORT}/${EXT_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&allowMultiQueries=true"
    else
      DB_URL="jdbc:mysql://${EXT_HOST}:${EXT_PORT}/${EXT_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&allowMultiQueries=true"
    fi
  fi

  DB_USER="$EXT_USER"
  DB_PASS="$EXT_PASS"

  echo "══════════════════════════════════════════"
  echo " Liquibase — $OPERATION  [EXTERNAL MODE]"
  echo " Runner: $RUNNER_LABEL"
  echo " Host : $EXT_HOST:$EXT_PORT"
  echo " DB   : $EXT_NAME"
  echo " User : $EXT_USER"
  echo "══════════════════════════════════════════"

  NETWORK_FLAG="--network=host"
else
  echo "══════════════════════════════════════════"
  echo " Liquibase — $OPERATION"
  echo " Runner: $RUNNER_LABEL"
  echo "══════════════════════════════════════════"

  # Mode Docker internal: pastikan MySQL container running
  if [ "$USE_DOCKER" = true ]; then
    if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
      echo "⚠️  MySQL container '$MYSQL_CONTAINER' tidak berjalan."
      echo "    Jalankan dulu: docker compose up -d mysql"
      exit 1
    fi
  fi

  NETWORK_FLAG="--network $NETWORK"
fi

# ── Jalankan Liquibase ────────────────────────────────────────
# PENTING: urutan argumen Liquibase 4.x:
#   liquibase [GLOBAL OPTIONS] <COMMAND> [COMMAND OPTIONS]
#
# --url / --username / --password  → global options (sebelum command)
# --changelog-file                 → command option  (setelah command)

# ── Cek apakah user menentukan changelog atau defaults custom di argumen ──
HAS_CHANGELOG_ARG=false
HAS_DEFAULTS_ARG=false
for arg in "$@"; do
  if [[ "$arg" == --changelog-file=* || "$arg" == --changelogFile=* ]]; then
    HAS_CHANGELOG_ARG=true
  fi
  if [[ "$arg" == --defaults-file=* || "$arg" == --defaultsFile=* ]]; then
    HAS_DEFAULTS_ARG=true
  fi
done

# Validasi khusus untuk generateChangeLog
if [[ "$OPERATION" == "generateChangeLog" || "$OPERATION" == "generateChangelog" ]]; then
  if [ "$HAS_CHANGELOG_ARG" = false ]; then
    echo "❌ Perintah generateChangeLog memerlukan file tujuan baru."
    echo "   Silakan tentukan file baru untuk menyimpan baseline skema DB, contoh:"
    echo "   ./scripts/lb.sh --external generateChangeLog --changelog-file=changelog/changes/v1.0/000-baseline.sql"
    echo "   (atau gunakan ekstensi .xml jika ingin format XML)"
    exit 1
  fi
fi

# Tentukan parameter changelog yang dilewatkan ke Liquibase
CHANGELOG_PARAM=""
if [ "$HAS_CHANGELOG_ARG" = false ]; then
  CHANGELOG_PARAM="--changelog-file=$CHANGELOG"
fi

# Hindari konflik dengan file default 'liquibase.properties' pada runner native
DEFAULTS_PARAM=""
if [ "$HAS_DEFAULTS_ARG" = false ]; then
  # Buat file kosong local.properties jika belum ada (file ini sudah di-ignore di .gitignore)
  LOCAL_PROPS="$ROOT_DIR/liquibase/liquibase.local.properties"
  if [ ! -f "$LOCAL_PROPS" ]; then
    touch "$LOCAL_PROPS"
  fi
  # Path relatif dari LB_WORKDIR ke liquibase.local.properties
  if [ -n "$DB_NAME" ] && [ -n "$DB_VER" ]; then
    DEFAULTS_PARAM="--defaults-file=../../liquibase.local.properties"
  else
    DEFAULTS_PARAM="--defaults-file=liquibase.local.properties"
  fi
fi

if [ "$USE_DOCKER" = true ]; then
  # ── Runner: Docker ──────────────────────────────────────────
  # Mount seluruh folder DB+Version agar path relatif di XML bisa diakses
  docker run --rm \
    $NETWORK_FLAG \
    -v "$LB_WORKDIR:/liquibase/workdir" \
    "$LIQUIBASE_IMAGE" \
    --url="$DB_URL" \
    --username="$DB_USER" \
    --password="$DB_PASS" \
    --driver=com.mysql.cj.jdbc.Driver \
    "$OPERATION" \
    ${CHANGELOG_PARAM:+ "$CHANGELOG_PARAM"} \
    "$@"
else
  # ── Runner: Native binary ───────────────────────────────────
  # cd ke folder LB_WORKDIR agar path relatif di XML (changelog/ & rollback/) bisa diakses
  cd "$LB_WORKDIR"
  liquibase \
    ${DEFAULTS_PARAM:+ "$DEFAULTS_PARAM"} \
    --url="$DB_URL" \
    --username="$DB_USER" \
    --password="$DB_PASS" \
    --driver=com.mysql.cj.jdbc.Driver \
    "$OPERATION" \
    ${CHANGELOG_PARAM:+ "$CHANGELOG_PARAM"} \
    "$@"
fi
