#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# SCENARIO 2 — APP LOCAL, EXTERNAL (prod) DB + bucket.
# Builds the image, then starts ONLY the app. No local DB is started — the app
# talks to the DB/bucket configured in .env.app-only.
# Uses .env.build (build-time NEXT_PUBLIC_*) and .env.app-only (runtime).
#
#   ./run-app-only.sh            # build + up (foreground)
#   ./run-app-only.sh -d         # build + up detached
#   ./run-app-only.sh --no-build # skip build, just (re)start
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

COMPOSE="docker-compose.app-only.yml"
ENV_FILE=".env.app-only"
DETACH=""
DO_BUILD=1

for arg in "$@"; do
    case "$arg" in
        -d|--detach) DETACH="-d" ;;
        --no-build)  DO_BUILD=0 ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE (copy from .env.app-only.example)"; exit 1; }
[[ -f ".env.build" ]] || { echo "Missing .env.build (copy from .env.build.example)"; exit 1; }

if [[ "$DO_BUILD" == "1" ]]; then
    echo "==> Building image..."
    ./build.sh
fi

echo "==> Starting app only (scenario 2, external DB/bucket)..."
docker compose -f "$COMPOSE" --env-file "$ENV_FILE" up $DETACH

if [[ -n "$DETACH" ]]; then
    echo "==> Up. App: http://localhost:8080  | logs: docker compose -f $COMPOSE logs -f"
fi
