#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="$1"

IMAGE=$(yq '.image' "$ADDON_DIR/config.yaml")
VERSION=$(yq '.version' "$ADDON_DIR/config.yaml")

# Convert ghcr.io/user/image -> user/image
IMAGE_PATH="${IMAGE#ghcr.io/}"

MANIFEST_URL="https://ghcr.io/v2/${IMAGE_PATH}/manifests/${VERSION}"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
-H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
"$MANIFEST_URL")

if [[ "$STATUS" == "200" ]]; then
echo "❌ Version already exists in GHCR: ${IMAGE}:${VERSION}"
exit 1
fi

echo "✔ Version is new: ${IMAGE}:${VERSION}"
