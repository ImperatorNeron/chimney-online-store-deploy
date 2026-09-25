#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# SCENARIO 1 — FULLY LOCAL.
# Builds the image, then starts app + a local Postgres together.
# Uses .env.build (build-time NEXT_PUBLIC_*) and .env.local (runtime).
#
#   ./run-local.sh            # build + up (foreground, logs attached)
#   ./run-local.sh -d         # build + up in the background (detached)
#   ./run-local.sh --no-build # skip the build, just (re)start
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

COMPOSE="docker-compose.local.yml"
ENV_FILE=".env.local"
DETACH=""
DO_BUILD=1

for arg in "$@"; do
    case "$arg" in
        -d|--detach) DETACH="-d" ;;
        --no-build)  DO_BUILD=0 ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE (copy from .env.local.example)"; exit 1; }
[[ -f ".env.build" ]] || { echo "Missing .env.build (copy from .env.build.example)"; exit 1; }

if [[ "$DO_BUILD" == "1" ]]; then
    echo "==> Building image..."
    ./build.sh
fi

echo "==> Starting app + local DB (scenario 1)..."
docker compose -f "$COMPOSE" --env-file "$ENV_FILE" up $DETACH

if [[ -n "$DETACH" ]]; then
    echo "==> Up. App: http://localhost:8080  | logs: docker compose -f $COMPOSE logs -f"
fi
