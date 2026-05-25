#!/usr/bin/env bash
# =============================================================
# lb-multi.sh — Liquibase helper untuk multi-DB setup
#
# Usage:
#   ./scripts/lb-multi.sh <service> <command> [extra args]
#
# Services:  users | orders | payments | inventory | all
# Commands:  update | status | validate | updateSQL | history
#            rollback --rollbackCount=N | clearCheckSums
#
# Examples:
#   ./scripts/lb-multi.sh users status
#   ./scripts/lb-multi.sh orders update
#   ./scripts/lb-multi.sh payments rollback --rollbackCount=1
#   ./scripts/lb-multi.sh all status          ← semua sekaligus
#   ./scripts/lb-multi.sh all update          ← semua sekaligus
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LIQUIBASE_IMAGE="liquibase-mysql:4.27"
NETWORK="liquibase-github_lb-net"

# ── Konfigurasi setiap service ──────────────────────────────
# Format: "MYSQL_CONTAINER|JDBC_URL|CHANGELOG_PATH"

declare -A SERVICE_CONFIG=(
  [users]="lb-mysql-main|jdbc:mysql://mysql-main:3306/db_users?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC|$ROOT_DIR/services/users/changelog"
  [orders]="lb-mysql-main|jdbc:mysql://mysql-main:3306/db_orders?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC|$ROOT_DIR/services/orders/changelog"
  [payments]="lb-mysql-svc|jdbc:mysql://mysql-svc:3306/db_payments?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC|$ROOT_DIR/services/payments/changelog"
  [inventory]="lb-mysql-svc|jdbc:mysql://mysql-svc:3306/db_inventory?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC|$ROOT_DIR/services/inventory/changelog"
)

DB_USER="liquibase_user"
DB_PASS="liquibase_pass"
CHANGELOG="changelog/db.changelog-master.xml"

# ── Validasi input ───────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <service> <command> [args]"
  echo "Services: users | orders | payments | inventory | all"
  echo "Commands: update | status | validate | updateSQL | history | rollback | diff"
  exit 1
fi

TARGET_SERVICE="$1"
OPERATION="$2"
shift 2
EXTRA_ARGS=("$@")

# ── Fungsi jalankan migrasi untuk 1 service ──────────────────
run_liquibase() {
  local service="$1"
  local config="${SERVICE_CONFIG[$service]}"

  IFS='|' read -r mysql_container db_url changelog_path <<< "$config"

  echo ""
  echo "╔══════════════════════════════════════════════╗"
  echo "  🗄  Service  : $service"
  echo "  📦  DB URL   : $db_url"
  echo "  ⚙️   Command  : $OPERATION ${EXTRA_ARGS[*]:-}"
  echo "╚══════════════════════════════════════════════╝"

  # Cek MySQL container berjalan
  if ! docker ps --format '{{.Names}}' | grep -q "^${mysql_container}$"; then
    echo "  ⚠️  MySQL container '$mysql_container' tidak berjalan!"
    echo "     Jalankan: docker compose -f docker-compose.multi.yml up -d mysql-main mysql-svc"
    return 1
  fi

  docker run --rm \
    --network "$NETWORK" \
    -v "$changelog_path:/liquibase/changelog" \
    "$LIQUIBASE_IMAGE" \
    --url="$db_url" \
    --username="$DB_USER" \
    --password="$DB_PASS" \
    --driver=com.mysql.cj.jdbc.Driver \
    "$OPERATION" \
    --changelog-file="$CHANGELOG" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"

  echo "  ✅ $service — '$OPERATION' selesai"
}

# ── Eksekusi ─────────────────────────────────────────────────
if [[ "$TARGET_SERVICE" == "all" ]]; then
  echo "🚀 Menjalankan '$OPERATION' untuk SEMUA service..."
  FAILED=()
  for svc in users orders payments inventory; do
    run_liquibase "$svc" || FAILED+=("$svc")
  done

  echo ""
  echo "═══════════════════════════════════════════════"
  if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo " ✅ Semua service berhasil!"
  else
    echo " ❌ Service yang gagal: ${FAILED[*]}"
    exit 1
  fi
  echo "═══════════════════════════════════════════════"

elif [[ -v SERVICE_CONFIG["$TARGET_SERVICE"] ]]; then
  run_liquibase "$TARGET_SERVICE"

else
  echo "❌ Service tidak dikenal: '$TARGET_SERVICE'"
  echo "   Pilihan: users | orders | payments | inventory | all"
  exit 1
fi
