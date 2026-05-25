#!/usr/bin/env bash
# =============================================================
# Liquibase Local Helper — jalankan perintah Liquibase via Docker
# Usage:
#   ./scripts/lb.sh update
#   ./scripts/lb.sh status
#   ./scripts/lb.sh validate
#   ./scripts/lb.sh updateSQL
#   ./scripts/lb.sh history
#   ./scripts/lb.sh rollback --rollbackCount=1
#   ./scripts/lb.sh rollback --rollbackToTag=v1.1
#   ./scripts/lb.sh clearCheckSums
#   ./scripts/lb.sh diff
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Custom image yang sudah include MySQL JDBC driver
LIQUIBASE_IMAGE="liquibase-mysql:4.27"
MYSQL_CONTAINER="liquibase-mysql"
NETWORK="liquibase-github_liquibase-net"

# Koneksi — harus sama dengan docker-compose.yml
DB_URL="jdbc:mysql://mysql:3306/liquibase_dev?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
DB_USER="liquibase_user"
DB_PASS="liquibase_pass"
CHANGELOG="changelog/db.changelog-master.xml"

OPERATION="${1:-update}"
shift || true   # sisa argumen diteruskan ke liquibase

echo "══════════════════════════════════════════"
echo " Liquibase — $OPERATION"
echo "══════════════════════════════════════════"

# Pastikan MySQL container sudah running
if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
  echo "⚠️  MySQL container '$MYSQL_CONTAINER' tidak berjalan."
  echo "    Jalankan dulu: docker compose up -d mysql"
  exit 1
fi

# PENTING: urutan argumen Liquibase 4.x:
#   liquibase [GLOBAL OPTIONS] <COMMAND> [COMMAND OPTIONS]
#
# --url / --username / --password  → global options (sebelum command)
# --changelog-file                 → command option  (setelah command)

docker run --rm \
  --network "$NETWORK" \
  -v "$ROOT_DIR/liquibase/changelog:/liquibase/changelog" \
  "$LIQUIBASE_IMAGE" \
  --url="$DB_URL" \
  --username="$DB_USER" \
  --password="$DB_PASS" \
  --driver=com.mysql.cj.jdbc.Driver \
  "$OPERATION" \
  --changelog-file="$CHANGELOG" \
  "$@"
