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
#   ./scripts/lb.sh rollback --rollbackToTag=v1.1
#   ./scripts/lb.sh clearCheckSums
#   ./scripts/lb.sh diff
#   ./scripts/lb.sh generateChangeLog
#   ./scripts/lb.sh changelogSync
#   ./scripts/lb.sh dropAll
#
# MODE EXTERNAL DB (existing database):
#   ./scripts/lb.sh --external update
#   ./scripts/lb.sh --external status
#   ./scripts/lb.sh --external validate
#   ./scripts/lb.sh --external updateSQL
#   ./scripts/lb.sh --external history
#   ./scripts/lb.sh --external rollback-count --count=1
#   ./scripts/lb.sh --external rollback --rollbackToTag=v1.1
#   ./scripts/lb.sh --external clearCheckSums
#   ./scripts/lb.sh --external diff
#   ./scripts/lb.sh --external generateChangeLog
#   ./scripts/lb.sh --external changelogSync
#   ./scripts/lb.sh --external dropAll
#
#   Override koneksi via .env atau env var:
#     EXT_DB_HOST=192.168.1.100 \
#     EXT_DB_NAME=myapp_db \
#     ./scripts/lb.sh --external update
#
#   Atau via flag langsung:
#     ./scripts/lb.sh --external --host=192.168.1.100 --db=myapp_db update
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
  EXT_HOST="${OVERRIDE_HOST:-${EXT_DB_HOST:-"127.0.0.1"}}"
  EXT_PORT="${EXT_DB_PORT:-3306}"
  EXT_NAME="${OVERRIDE_DB:-${EXT_DB_NAME:-"liquibase_dev"}}"
  EXT_USER="${EXT_DB_USER:-"liquibase_user"}"
  EXT_PASS="${EXT_DB_PASS:-"liquibase_pass"}"

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
  DEFAULTS_PARAM="--defaults-file=liquibase.local.properties"
fi

if [ "$USE_DOCKER" = true ]; then
  # ── Runner: Docker ──────────────────────────────────────────
  docker run --rm \
    $NETWORK_FLAG \
    -v "$ROOT_DIR/liquibase/changelog:/liquibase/changelog" \
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
  cd "$ROOT_DIR/liquibase"
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
