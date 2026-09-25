#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# SCENARIO 3 — CLEAN PRODUCTION BUILD (no app is started locally).
# Builds the production image and OPTIONALLY pushes it to your registry.
# The image is then deployed by your host (Koyeb/Railway/etc.), where you set
# the RUNTIME env vars (see the README "Deploy to Railway" section for the full list).
#
# Build-time NEXT_PUBLIC_* come from .env.build — set NEXT_PUBLIC_SITE_URL there
# to your REAL public domain before releasing (else canonical/OG use localhost).
#
#   IMAGE=youruser/chimney-app TAG=v1 ./release.sh          # build only
#   IMAGE=youruser/chimney-app TAG=v1 ./release.sh --push   # build + push
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PUSH=0
for arg in "$@"; do
    case "$arg" in
        --push) PUSH=1 ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

IMAGE="${IMAGE:-chimney-app}"
TAG="${TAG:-local}"

[[ -f ".env.build" ]] || { echo "Missing .env.build (copy from .env.build.example)"; exit 1; }

# Friendly warning: prod images should not ship localhost as the public URL.
if grep -q "NEXT_PUBLIC_SITE_URL=http://localhost" .env.build; then
    echo "WARNING: .env.build still has NEXT_PUBLIC_SITE_URL=http://localhost —"
    echo "         set it to your real public domain for a production release."
fi

echo "==> Building production image ${IMAGE}:${TAG} (scenario 3, no app started)..."
IMAGE="$IMAGE" TAG="$TAG" ./build.sh

if [[ "$PUSH" == "1" ]]; then
    echo "==> Pushing ${IMAGE}:${TAG}..."
    IMAGE="$IMAGE" TAG="$TAG" ./push.sh
else
    echo "==> Built. To push:  IMAGE=$IMAGE TAG=$TAG ./release.sh --push"
fi
