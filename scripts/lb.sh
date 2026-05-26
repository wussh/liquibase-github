#!/usr/bin/env bash
# =============================================================
# Liquibase Local Helper — jalankan perintah Liquibase via Docker
#
# MODE DEFAULT (Docker internal):
#   ./scripts/lb.sh update
#   ./scripts/lb.sh status
#   ./scripts/lb.sh validate
#   ./scripts/lb.sh updateSQL
#   ./scripts/lb.sh history
#   ./scripts/lb.sh rollback --rollbackCount=1
#   ./scripts/lb.sh rollback --rollbackToTag=v1.1
#   ./scripts/lb.sh clearCheckSums
#   ./scripts/lb.sh diff
#   ./scripts/lb.sh generateChangeLog
#   ./scripts/lb.sh changelogSync
#
# MODE EXTERNAL DB (existing database):
#   ./scripts/lb.sh --external update
#   ./scripts/lb.sh --external generateChangeLog
#   ./scripts/lb.sh --external status
#
#   Override koneksi via env var:
#     EXT_DB_HOST=192.168.1.100 \
#     EXT_DB_PORT=3306 \
#     EXT_DB_NAME=myapp_db \
#     EXT_DB_USER=admin \
#     EXT_DB_PASS=secret \
#     ./scripts/lb.sh --external update
#
#   Atau via flag langsung:
#     ./scripts/lb.sh --external --host=192.168.1.100 --db=myapp_db update
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Image & Network ──────────────────────────────────────────
LIQUIBASE_IMAGE="liquibase-mysql:4.27"
MYSQL_CONTAINER="liquibase-mysql"
NETWORK="liquibase-github_liquibase-net"

# ── Default koneksi (Docker internal) ───────────────────────
DB_URL="jdbc:mysql://mysql:3306/liquibase_dev?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
DB_USER="liquibase_user"
DB_PASS="liquibase_pass"
CHANGELOG="changelog/db.changelog-master.xml"

# ── Parse flags ──────────────────────────────────────────────
EXTERNAL_MODE=false
OVERRIDE_HOST=""
OVERRIDE_DB=""

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
    *)
      ARGS+=("$arg")
      ;;
  esac
done

# Reset positional params tanpa flag custom
set -- "${ARGS[@]+"${ARGS[@]}"}"

OPERATION="${1:-update}"
shift || true   # sisa argumen diteruskan ke liquibase

# ── Mode External DB ─────────────────────────────────────────
if [ "$EXTERNAL_MODE" = true ]; then
  # Ambil dari env var, dengan fallback ke nilai default
  EXT_HOST="${OVERRIDE_HOST:-${EXT_DB_HOST:-"127.0.0.1"}}"
  EXT_PORT="${EXT_DB_PORT:-3306}"
  EXT_NAME="${OVERRIDE_DB:-${EXT_DB_NAME:-"liquibase_dev"}}"
  EXT_USER="${EXT_DB_USER:-"liquibase_user"}"
  EXT_PASS="${EXT_DB_PASS:-"liquibase_pass"}"

  DB_URL="jdbc:mysql://${EXT_HOST}:${EXT_PORT}/${EXT_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
  DB_USER="$EXT_USER"
  DB_PASS="$EXT_PASS"

  echo "══════════════════════════════════════════"
  echo " Liquibase — $OPERATION  [EXTERNAL MODE]"
  echo " Host : $EXT_HOST:$EXT_PORT"
  echo " DB   : $EXT_NAME"
  echo " User : $EXT_USER"
  echo "══════════════════════════════════════════"

  # External mode: gunakan host network supaya bisa reach host/LAN DB
  NETWORK_FLAG="--network=host"
else
  echo "══════════════════════════════════════════"
  echo " Liquibase — $OPERATION"
  echo "══════════════════════════════════════════"

  # Pastikan MySQL container sudah running
  if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
    echo "⚠️  MySQL container '$MYSQL_CONTAINER' tidak berjalan."
    echo "    Jalankan dulu: docker compose up -d mysql"
    exit 1
  fi

  NETWORK_FLAG="--network $NETWORK"
fi

# ── Jalankan Liquibase ────────────────────────────────────────
# PENTING: urutan argumen Liquibase 4.x:
#   liquibase [GLOBAL OPTIONS] <COMMAND> [COMMAND OPTIONS]
#
# --url / --username / --password  → global options (sebelum command)
# --changelog-file                 → command option  (setelah command)

docker run --rm \
  $NETWORK_FLAG \
  -v "$ROOT_DIR/liquibase/changelog:/liquibase/changelog" \
  "$LIQUIBASE_IMAGE" \
  --url="$DB_URL" \
  --username="$DB_USER" \
  --password="$DB_PASS" \
  --driver=com.mysql.cj.jdbc.Driver \
  "$OPERATION" \
  --changelog-file="$CHANGELOG" \
  "$@"
