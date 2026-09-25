#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Upload a local media folder to the Railway (S3) bucket, preserving structure.
# Thin wrapper around ../../dumps/upload-to-bucket.py that points it at this
# repo's .env.app-only for S3 credentials (APP_CONFIG__S3__*).
#
# Usage:
#   ./scripts/upload-media.sh <local_dir> [key_prefix]
#
# Examples:
#   # product images: local <slug>/<file> -> bucket keys uploads/<slug>/<file>
#   ./scripts/upload-media.sh ~/Downloads/uploads uploads
#   # category images
#   ./scripts/upload-media.sh ~/Downloads/categories categories
#
# Credentials come from ../.env.app-only by default (S3 keys only). Override the
# env file with:  ENV_FILE=/path/.env ./scripts/upload-media.sh ...
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"        # chimney-deploy/scripts

UPLOADER="$(cd ../.. && pwd)/dumps/upload-to-bucket.py"
ENV_FILE="${ENV_FILE:-$(cd .. && pwd)/.env.app-only}"

if [[ ! -f "$UPLOADER" ]]; then
    echo "ERROR: uploader not found at $UPLOADER"
    exit 1
fi
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <local_dir> [key_prefix]"
    exit 1
fi

python3 "$UPLOADER" "$@" --env-file "$ENV_FILE"
