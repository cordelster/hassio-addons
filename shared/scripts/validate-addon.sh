#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="$1"

if [[ ! -f "$ADDON_DIR/config.yaml" ]]; then
  echo "Missing config.yaml in $ADDON_DIR"
  exit 1
fi

if [[ ! -f "$ADDON_DIR/Dockerfile" ]]; then
  echo "Missing Dockerfile in $ADDON_DIR"
  exit 1
fi

if [[ ! -f "$ADDON_DIR/run.sh" ]]; then
  echo "Missing run.sh in $ADDON_DIR"
  exit 1
fi

if ! grep -q '^version:' "$ADDON_DIR/config.yaml"; then
  echo "Missing version in config.yaml"
  exit 1
fi

echo "✔ Validated $(basename "$ADDON_DIR")"

./shared/scripts/check-version.sh addons/${{ matrix.addon }}
