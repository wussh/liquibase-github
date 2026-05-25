#!/usr/bin/env bash
# =============================================================
# migrate.sh — Jalankan Liquibase ke salah satu atau semua DB
#
# Usage:
#   ./migrate.sh users   <command>     → hanya users-db
#   ./migrate.sh orders  <command>     → hanya orders-db
#   ./migrate.sh all     <command>     → keduanya
#
# Command: update | status | validate | updateSQL | history
#          rollback --rollbackCount=1
#
# Contoh:
#   ./migrate.sh users update
#   ./migrate.sh all status
#   ./migrate.sh orders rollback --rollbackCount=1
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="liquibase-mysql:4.27"
NETWORK="simple-multi_app-net"
USER="app_user"
PASS="app_pass"

# ─────────────────────────────────────────────
# Konfigurasi tiap database:
#  TARGET      │  MYSQL CONTAINER  │  JDBC URL
# ─────────────────────────────────────────────
declare -A DB_CONTAINER=( [users]="mysql-users"  [orders]="mysql-orders" )
declare -A DB_URL=(
  [users]="jdbc:mysql://mysql-users:3306/users_db?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
  [orders]="jdbc:mysql://mysql-orders:3306/orders_db?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
)
declare -A DB_FOLDER=(
  [users]="$SCRIPT_DIR/users-db/changelog"
  [orders]="$SCRIPT_DIR/orders-db/changelog"
)
# ─────────────────────────────────────────────

TARGET="${1:-}"
CMD="${2:-update}"
shift 2 || true
EXTRA=("$@")

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <users|orders|all> <command> [args]"
  exit 1
fi

run() {
  local db="$1"

  # Cek container jalan
  if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER[$db]}$"; then
    echo "❌ Container '${DB_CONTAINER[$db]}' tidak jalan!"
    echo "   Jalankan dulu: docker compose up -d"
    return 1
  fi

  echo ""
  echo "┌─────────────────────────────────────────┐"
  echo "│  DB     : $db"
  echo "│  CMD    : $CMD ${EXTRA[*]:-}"
  echo "│  URL    : ${DB_URL[$db]}"
  echo "└─────────────────────────────────────────┘"

  docker run --rm \
    --network "$NETWORK" \
    -v "${DB_FOLDER[$db]}:/liquibase/changelog" \
    "$IMAGE" \
    --url="${DB_URL[$db]}" \
    --username="$USER" \
    --password="$PASS" \
    --driver=com.mysql.cj.jdbc.Driver \
    "$CMD" \
    --changelog-file=changelog/master.xml \
    "${EXTRA[@]+"${EXTRA[@]}"}"

  echo "✅ $db selesai"
}

case "$TARGET" in
  users|orders)
    run "$TARGET"
    ;;
  all)
    run users
    run orders
    echo ""
    echo "🎉 Semua database selesai!"
    ;;
  *)
    echo "❌ Target tidak valid: '$TARGET'"
    echo "   Pilih: users | orders | all"
    exit 1
    ;;
esac
