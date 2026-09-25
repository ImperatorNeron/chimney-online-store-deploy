#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Restore a pg_dump (custom format) into a Railway Postgres database.
#
# Usage:
#   ./scripts/db-restore.sh "postgresql://postgres:PASS@HOST.proxy.rlwy.net:PORT/railway"
#   ./scripts/db-restore.sh "<DST_URL>" /path/to/specific.dump
#
# If no dump path is given, the NEWEST *.dump in ../dumps (repo-root/dumps) is used.
# The DST url can also be provided via the DST env var instead of arg 1.
#
# What it does:
#   1) enables pg_trgm (required by the app's fuzzy search)
#   2) pg_restore --clean --if-exists --no-owner --no-privileges
#   3) prints a few sanity-check counts
#
# Uses Docker (postgres:17-alpine) if available, else a local pg_restore >= 16.
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"        # chimney-deploy/scripts

PG_IMAGE="postgres:17-alpine"
DUMPS_DIR="$(cd ../.. && pwd)/dumps"       # repo-root/dumps

DST="${1:-${DST:-}}"
if [[ -z "$DST" ]]; then
    echo "ERROR: no destination URL."
    echo "Usage: $0 \"postgresql://postgres:PASS@HOST.proxy.rlwy.net:PORT/railway\" [dump-file]"
    exit 1
fi

DUMP="${2:-}"
if [[ -z "$DUMP" ]]; then
    DUMP="$(ls -1t "$DUMPS_DIR"/*.dump 2>/dev/null | head -1 || true)"
fi
if [[ -z "$DUMP" || ! -f "$DUMP" ]]; then
    echo "ERROR: dump file not found (looked for newest *.dump in $DUMPS_DIR)."
    echo "Pass it explicitly: $0 \"<DST_URL>\" /path/to/file.dump"
    exit 1
fi
DUMP="$(cd "$(dirname "$DUMP")" && pwd)/$(basename "$DUMP")"
DUMP_DIR="$(dirname "$DUMP")"
DUMP_NAME="$(basename "$DUMP")"

echo "==> Destination : ${DST%%@*}@***"
echo "==> Dump file   : $DUMP"
echo

USE_DOCKER=0
if docker ps >/dev/null 2>&1; then
    USE_DOCKER=1
    echo "==> Using Docker ($PG_IMAGE) for pg client tools."
elif command -v pg_restore >/dev/null 2>&1; then
    echo "==> Using local pg_restore: $(pg_restore --version)"
else
    echo "ERROR: neither a running Docker daemon nor a local pg_restore found."
    echo "  - start Docker (sudo systemctl start docker), OR"
    echo "  - install client:  sudo apt-get install -y postgresql-client-16"
    exit 1
fi

run_psql() {
    if [[ "$USE_DOCKER" == "1" ]]; then
        docker run --rm "$PG_IMAGE" psql "$DST" -v ON_ERROR_STOP=1 -c "$1"
    else
        psql "$DST" -v ON_ERROR_STOP=1 -c "$1"
    fi
}

run_restore() {
    if [[ "$USE_DOCKER" == "1" ]]; then
        docker run --rm -v "$DUMP_DIR:/work" "$PG_IMAGE" \
            pg_restore --no-owner --no-privileges --clean --if-exists \
            -d "$DST" "/work/$DUMP_NAME"
    else
        pg_restore --no-owner --no-privileges --clean --if-exists \
            -d "$DST" "$DUMP"
    fi
}

echo "==> [1/3] Enabling pg_trgm extension..."
run_psql "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

echo "==> [2/3] Restoring dump (this may print harmless NOTICEs)..."
if run_restore; then
    echo "    restore finished."
else
    echo "    pg_restore returned non-zero — review the messages above."
    echo "    (First run into an empty DB often warns about missing objects; that's OK."
    echo "     Real problems are ERRORs referencing your tables/data.)"
fi

echo "==> [3/3] Sanity checks..."
run_psql "\dt" || true
run_psql "SELECT count(*) AS unique_products FROM uniqueproducts;" || true
run_psql "SELECT count(*) AS variations FROM productvariations;" || true
run_psql "SELECT similarity('труба','труби') AS pg_trgm_ok;" || true

echo
echo "==> Done."
