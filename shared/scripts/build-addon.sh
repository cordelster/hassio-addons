#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="$1"
ADDON_NAME="$(basename "$ADDON_DIR")"

docker build \
  --build-arg BUILD_FROM=ghcr.io/hassio-addons/base:latest \
  -t "test/${ADDON_NAME}:ci" \
  "$ADDON_DIR"
