#!/bin/sh
# -----------------------------------------------------------------------------
# Backend startup for the combined prod-like image.
# Runs Alembic migrations (idempotent) then serves via gunicorn/uvicorn workers,
# mirroring chimney-online-store-backend/entrypoint.sh prod branch.
#
# All output goes to stdout/stderr (collected by supervisord -> container logs).
# -----------------------------------------------------------------------------
set -e

HOST="${BACKEND_HOST:-127.0.0.1}"
PORT="${BACKEND_PORT:-8000}"
WEB_CONCURRENCY="${WEB_CONCURRENCY:-2}"

# --- JWT certificates ---
# Keys are NOT baked into the image. On Railway, provide them as base64 env
# vars (JWT_PRIVATE_KEY_B64 / JWT_PUBLIC_KEY_B64) and we write them to the paths
# the backend expects. Locally (compose) they are mounted as files, so if the
# env vars are absent we just skip this and use the mounted files.
CERT_DIR="/app/backend/app/certificates"
if [ -n "${JWT_PRIVATE_KEY_B64:-}" ]; then
    echo "[backend] Writing JWT keys from env..."
    mkdir -p "$CERT_DIR"
    printf '%s' "$JWT_PRIVATE_KEY_B64" | base64 -d > "$CERT_DIR/private.pem"
    printf '%s' "$JWT_PUBLIC_KEY_B64"  | base64 -d > "$CERT_DIR/public.pem"
    chmod 600 "$CERT_DIR/private.pem"
fi

if [ "${RUN_MIGRATIONS:-1}" = "1" ]; then
    echo "[backend] Running Alembic migrations..."
    alembic upgrade head
fi

echo "[backend] Starting gunicorn on ${HOST}:${PORT} (workers=${WEB_CONCURRENCY})"
exec gunicorn \
    -w "$WEB_CONCURRENCY" \
    -k uvicorn.workers.UvicornWorker \
    --bind "$HOST:$PORT" \
    --access-logfile - \
    --error-logfile - \
    "app.main:create_app()"
