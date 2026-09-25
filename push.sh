#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Push the built image to a registry (Docker Hub by default).
# NOTE: We are NOT pushing yet — this is here for when you're ready.
#
# Usage:
#   IMAGE=youruser/chimney-app TAG=v1 ./push.sh
#
# Requires: docker login  (docker login  for Docker Hub)
# -----------------------------------------------------------------------------
set -euo pipefail

IMAGE="${IMAGE:-chimney-app}"
TAG="${TAG:-local}"

if [ "$IMAGE" = "chimney-app" ]; then
    echo "Refusing to push the default local image name."
    echo "Set IMAGE to your registry namespace, e.g.:"
    echo "  IMAGE=youruser/chimney-app TAG=v1 ./push.sh"
    exit 1
fi

echo "Pushing ${IMAGE}:${TAG} ..."
docker push "${IMAGE}:${TAG}"
