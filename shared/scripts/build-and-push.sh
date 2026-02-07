#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="$1"
ADDON="$(basename "$ADDON_DIR")"

VERSION=$(yq '.version' "$ADDON_DIR/config.yaml")
IMAGE=$(yq '.image' "$ADDON_DIR/config.yaml")

echo "📦 Building $ADDON ($VERSION)"

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg BUILD_FROM=ghcr.io/hassio-addons/base:latest \
  --tag "$IMAGE:$VERSION" \
  --tag "$IMAGE:latest" \
  --push \
  "$ADDON_DIR"

