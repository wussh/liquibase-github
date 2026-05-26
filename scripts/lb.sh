#!/usr/bin/env bash
# =============================================================
# Liquibase Local Helper — Docker (utama) atau native binary (fallback)
#
# STRUKTUR FOLDER yang DIDUKUNG (auto-detect):
#
#   Opsi A — Versi di level atas, changelog/ di dalam versi:
#     liquibase/{DB}/{VER}/changelog/changes/0001-*.sql
#     liquibase/{DB}/{VER}/rollback/0001-rollback.sql
#     liquibase/{DB}/{VER}/changelog/db.changelog-master.xml
#
#   Opsi B — Versi di level atas, changes/ langsung (TANPA changelog/):
#     liquibase/{DB}/{VER}/changes/0001-*.sql
#     liquibase/{DB}/{VER}/rollback/0001-rollback.sql
#     liquibase/{DB}/{VER}/db.changelog-master.xml
#
# GENERATE MASTER XML (tidak perlu koneksi DB):
#   ./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master
#
# MODE EXTERNAL DB:
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 update
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 status
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 rollback-count --count=1
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 rollback --tag=TAG
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 tag --tag=TAG
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 history
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 validate
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 updateSQL
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 clearCheckSums
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 changelogSync
#   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 dropAll
#
#   Override koneksi:
#     ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 --host=1.2.3.4 update
#     EXT_DB_HOST=1.2.3.4 ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 update
#
# RUNNER (auto-detect, bisa di-override):
#   ./scripts/lb.sh --runner=docker  --external --db-name=db1 --ver=v.1.0 update
#   ./scripts/lb.sh --runner=native  --external --db-name=db1 --ver=v.1.0 update
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
  set -o allexport
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +o allexport
fi

# ── Default koneksi (Docker internal) ───────────────────────
DB_URL="jdbc:mysql://mysql:3306/liquibase_dev?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
DB_USER="liquibase_user"
DB_PASS="liquibase_pass"

# ── Parse flags ──────────────────────────────────────────────
EXTERNAL_MODE=false
OVERRIDE_HOST=""
OVERRIDE_DB=""
RUNNER_OVERRIDE=""
DB_NAME=""
DB_VER=""

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --external)   EXTERNAL_MODE=true ;;
    --host=*)     OVERRIDE_HOST="${arg#--host=}" ;;
    --db=*)       OVERRIDE_DB="${arg#--db=}" ;;
    --db-name=*)  DB_NAME="${arg#--db-name=}" ;;
    --ver=*)      DB_VER="${arg#--ver=}" ;;
    --runner=*)   RUNNER_OVERRIDE="${arg#--runner=}" ;;
    *)            ARGS+=("$arg") ;;
  esac
done

set -- "${ARGS[@]+"${ARGS[@]}"}"

OPERATION="${1:-update}"
shift || true

# ── Resolusi path & auto-detect struktur folder ──────────────
#
#  STRUCT_MODE="opsiA"   → {DB}/{VER}/changelog/changes/  + {DB}/{VER}/rollback/
#  STRUCT_MODE="opsiB"   → {DB}/{VER}/changes/            + {DB}/{VER}/rollback/
#  STRUCT_MODE="default" → liquibase/ (tanpa --db-name)
#
STRUCT_MODE="default"
LB_WORKDIR="$ROOT_DIR/liquibase"
CHANGELOG="db.changelog-master.xml"

if [ -n "$DB_NAME" ]; then
  if [ -z "$DB_VER" ]; then
    echo "❌ Flag --ver wajib digunakan bersama --db-name."
    echo "   Contoh: --db-name=db1 --ver=v.1.0"
    exit 1
  fi

  VER_DIR="$ROOT_DIR/liquibase/$DB_NAME/$DB_VER"
  if [ ! -d "$VER_DIR" ]; then
    echo "❌ Folder tidak ditemukan: $VER_DIR"
    echo "   Pastikan folder liquibase/$DB_NAME/$DB_VER/ sudah ada."
    exit 1
  fi

  if [ -d "$VER_DIR/changelog" ]; then
    # Opsi A: ada sub-folder changelog/
    STRUCT_MODE="opsiA"
    LB_WORKDIR="$VER_DIR"
    CHANGELOG="changelog/db.changelog-master.xml"
    CHANGES_REL="changelog/changes"
    ROLLBACK_REL="rollback"
  elif [ -d "$VER_DIR/changes" ]; then
    # Opsi B: changes/ langsung di dalam versi (TANPA changelog/)
    STRUCT_MODE="opsiB"
    LB_WORKDIR="$VER_DIR"
    CHANGELOG="db.changelog-master.xml"
    CHANGES_REL="changes"
    ROLLBACK_REL="rollback"
  else
    echo "❌ Tidak dapat mendeteksi struktur folder di: $VER_DIR"
    echo "   Pastikan ada folder 'changelog/changes/' (Opsi A)"
    echo "   atau folder 'changes/' (Opsi B) di dalamnya."
    exit 1
  fi
fi

# ── Perintah generate-master: tidak butuh koneksi DB ─────────
if [ "$OPERATION" = "generate-master" ]; then
  if [ "$STRUCT_MODE" = "default" ]; then
    echo "❌ generate-master memerlukan --db-name dan --ver."
    echo "   Contoh: ./scripts/lb.sh --db-name=db1 --ver=v.1.0 generate-master"
    exit 1
  fi

  CHANGES_DIR="$LB_WORKDIR/$CHANGES_REL"
  ROLLBACK_DIR="$LB_WORKDIR/$ROLLBACK_REL"
  MASTER_XML="$LB_WORKDIR/$CHANGELOG"
  GIT_AUTHOR=$(git config user.name 2>/dev/null || echo "developer")

  if [ ! -d "$CHANGES_DIR" ]; then
    echo "❌ Folder tidak ditemukan: $CHANGES_DIR"
    exit 1
  fi

  echo "═══════════════════════════════════════════════"
  echo " generate-master"
  echo " DB     : $DB_NAME"
  echo " Ver    : $DB_VER"
  echo " Mode   : $STRUCT_MODE"
  echo " Src    : $CHANGES_DIR"
  echo " Out    : $MASTER_XML"
  echo "═══════════════════════════════════════════════"

  # Kumpulkan file .sql secara terurut
  SQL_FILES=()
  while IFS= read -r -d '' f; do
    SQL_FILES+=("$(basename "$f")")
  done < <(find "$CHANGES_DIR" -maxdepth 1 -name "*.sql" -print0 | sort -z)

  if [ ${#SQL_FILES[@]} -eq 0 ]; then
    echo "⚠️  Tidak ada file .sql di: $CHANGES_DIR"
    exit 1
  fi

  mkdir -p "$(dirname "$MASTER_XML")"
  cat > "$MASTER_XML" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.9.xsd">

    <!--
        File ini di-generate OTOMATIS.
        db-name : $DB_NAME
        ver     : $DB_VER
        perintah: scripts/lb.sh [db-name] [ver] generate-master

        JANGAN diedit manual - perubahan akan tertimpa.

        Cara menambah changeset baru:
          1. Buat file SQL di : $CHANGES_REL/000X-nama.sql
          2. Buat rollback di : $ROLLBACK_REL/000X-rollback.sql
          3. Jalankan generate-master lagi
    -->
EOF

  COUNT=0
  WARN_COUNT=0

  for SQL_FILE in "${SQL_FILES[@]}"; do
    PREFIX=$(echo "$SQL_FILE" | grep -oE '^[0-9]+')
    CHANGESET_ID="${DB_VER}-${SQL_FILE%.sql}"

    ROLLBACK_FILE=""
    if [ -d "$ROLLBACK_DIR" ]; then
      ROLLBACK_FILE=$(find "$ROLLBACK_DIR" -maxdepth 1 -name "${PREFIX}-rollback.sql" 2>/dev/null | head -1)
    fi

    {
      echo ""
      echo "    <!-- ═══ ${CHANGESET_ID} ═══ -->"
      echo "    <changeSet id=\"${CHANGESET_ID}\" author=\"${GIT_AUTHOR}\">"
      echo "        <sqlFile path=\"${CHANGES_REL}/${SQL_FILE}\""
      echo "                 relativeToChangelogFile=\"true\""
      echo "                 splitStatements=\"true\""
      echo "                 endDelimiter=\";\"/>"

      if [ -n "$ROLLBACK_FILE" ]; then
        ROLLBACK_BASENAME=$(basename "$ROLLBACK_FILE")
        echo "        <rollback>"
        echo "            <sqlFile path=\"${ROLLBACK_REL}/${ROLLBACK_BASENAME}\""
        echo "                     relativeToChangelogFile=\"true\""
        echo "                     splitStatements=\"true\""
        echo "                     endDelimiter=\";\"/>"
        echo "        </rollback>"
      else
        echo "        <!-- ⚠️  ${ROLLBACK_REL}/${PREFIX}-rollback.sql tidak ditemukan — empty rollback -->"
        echo "        <rollback/>"
        WARN_COUNT=$((WARN_COUNT + 1))
      fi

      echo "    </changeSet>"
    } >> "$MASTER_XML"

    if [ -n "$ROLLBACK_FILE" ]; then
      echo "  ✅ $SQL_FILE  →  $(basename "$ROLLBACK_FILE")"
    else
      echo "  ⚠️  $SQL_FILE  →  ${ROLLBACK_REL}/${PREFIX}-rollback.sql (TIDAK DITEMUKAN)"
    fi

    COUNT=$((COUNT + 1))
  done

  echo "" >> "$MASTER_XML"
  echo "</databaseChangeLog>" >> "$MASTER_XML"

  echo ""
  echo "══════════════════════════════════"
  echo " ✅ Selesai! $CHANGELOG berhasil di-generate."
  echo "    Total changeset : $COUNT"
  [ "$WARN_COUNT" -gt 0 ] && \
    echo "    ⚠️  Missing rollback : $WARN_COUNT file"
  echo "══════════════════════════════════"
  exit 0
fi

# ── Deteksi runner ───────────────────────────────────────────
USE_DOCKER=false
USE_NATIVE=false

if [ "$RUNNER_OVERRIDE" = "docker" ]; then
  command -v docker &>/dev/null || { echo "❌ Docker tidak ditemukan."; exit 1; }
  USE_DOCKER=true
elif [ "$RUNNER_OVERRIDE" = "native" ]; then
  command -v liquibase &>/dev/null || { echo "❌ Binary 'liquibase' tidak ditemukan."; exit 1; }
  USE_NATIVE=true
else
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    USE_DOCKER=true
  elif command -v liquibase &>/dev/null; then
    USE_NATIVE=true
  else
    echo "❌ Tidak ditemukan runner yang tersedia."
    echo "   1. Install Docker   : https://docs.docker.com/get-docker/"
    echo "   2. Install Liquibase: https://docs.liquibase.com/start/install/home.html"
    exit 1
  fi
fi

RUNNER_LABEL="Docker"
[ "$USE_NATIVE" = true ] && RUNNER_LABEL="Native ($(command -v liquibase))"

# ── Mode External DB ─────────────────────────────────────────
if [ "$EXTERNAL_MODE" = true ]; then
  if [ -n "$DB_NAME" ]; then
    DB_KEY=$(echo "$DB_NAME" | tr '[:lower:]' '[:upper:]' | tr -cs 'A-Z0-9' '_')
    _SPEC_HOST=$(eval echo "\${DB_${DB_KEY}_HOST:-}")
    _SPEC_PORT=$(eval echo "\${DB_${DB_KEY}_PORT:-}")
    _SPEC_NAME=$(eval echo "\${DB_${DB_KEY}_NAME:-}")
    _SPEC_USER=$(eval echo "\${DB_${DB_KEY}_USER:-}")
    _SPEC_PASS=$(eval echo "\${DB_${DB_KEY}_PASS:-}")
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

  if [ "$USE_NATIVE" = true ]; then
    DB_URL="jdbc:mysql://${EXT_HOST}:${EXT_PORT}/${EXT_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&allowMultiQueries=true"
  elif [[ "$EXT_HOST" == "127.0.0.1" || "$EXT_HOST" == "localhost" ]]; then
    DB_URL="jdbc:mysql://host.docker.internal:${EXT_PORT}/${EXT_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&allowMultiQueries=true"
  else
    DB_URL="jdbc:mysql://${EXT_HOST}:${EXT_PORT}/${EXT_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&allowMultiQueries=true"
  fi

  DB_USER="$EXT_USER"
  DB_PASS="$EXT_PASS"

  echo "══════════════════════════════════════════"
  echo " Liquibase — $OPERATION  [EXTERNAL MODE]"
  echo " Runner : $RUNNER_LABEL"
  echo " Mode   : $STRUCT_MODE"
  echo " Host   : $EXT_HOST:$EXT_PORT"
  echo " DB     : $EXT_NAME"
  echo " User   : $EXT_USER"
  echo "══════════════════════════════════════════"

  NETWORK_FLAG="--network=host"
else
  echo "══════════════════════════════════════════"
  echo " Liquibase — $OPERATION"
  echo " Runner : $RUNNER_LABEL"
  echo "══════════════════════════════════════════"

  if [ "$USE_DOCKER" = true ]; then
    if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
      echo "⚠️  MySQL container '$MYSQL_CONTAINER' tidak berjalan."
      echo "    Jalankan dulu: docker compose up -d mysql"
      exit 1
    fi
  fi

  NETWORK_FLAG="--network $NETWORK"
fi

# ── Cek argumen dari user ────────────────────────────────────
HAS_CHANGELOG_ARG=false
HAS_DEFAULTS_ARG=false
for arg in "$@"; do
  [[ "$arg" == --changelog-file=* || "$arg" == --changelogFile=* ]] && HAS_CHANGELOG_ARG=true
  [[ "$arg" == --defaults-file=* || "$arg" == --defaultsFile=* ]]   && HAS_DEFAULTS_ARG=true
done

if [[ "$OPERATION" == "generateChangeLog" || "$OPERATION" == "generateChangelog" ]]; then
  if [ "$HAS_CHANGELOG_ARG" = false ]; then
    echo "❌ Perintah generateChangeLog memerlukan file tujuan baru."
    echo "   Contoh:"
    echo "   ./scripts/lb.sh --external --db-name=db1 --ver=v.1.0 generateChangeLog \\"
    echo "     --changelog-file=changes/000-baseline.sql"
    exit 1
  fi
fi

CHANGELOG_PARAM=""
[ "$HAS_CHANGELOG_ARG" = false ] && CHANGELOG_PARAM="--changelog-file=$CHANGELOG"

# ── Hitung path ke liquibase.local.properties ────────────────
DEFAULTS_PARAM=""
if [ "$HAS_DEFAULTS_ARG" = false ]; then
  LOCAL_PROPS="$ROOT_DIR/liquibase/liquibase.local.properties"
  [ ! -f "$LOCAL_PROPS" ] && touch "$LOCAL_PROPS"

  # LB_WORKDIR depth relative to liquibase/:
  #   opsiA / opsiB: liquibase/{DB}/{VER}/  → 2 levels up
  #   default      : liquibase/              → same level
  case "$STRUCT_MODE" in
    opsiA|opsiB) DEFAULTS_PARAM="--defaults-file=../../liquibase.local.properties" ;;
    default)     DEFAULTS_PARAM="--defaults-file=liquibase.local.properties" ;;
  esac
fi

# ── Jalankan Liquibase ────────────────────────────────────────
if [ "$USE_DOCKER" = true ]; then
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
