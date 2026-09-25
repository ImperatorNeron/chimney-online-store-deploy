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
