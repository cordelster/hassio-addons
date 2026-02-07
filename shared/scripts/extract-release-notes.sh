#!/usr/bin/env bash
set -euo pipefail

ADDON_DIR="$1"

VERSION=$(yq '.version' "$ADDON_DIR/config.yaml")
CHANGELOG="$ADDON_DIR/CHANGELOG.md"

if [[ ! -f "$CHANGELOG" ]]; then
echo "❌ Missing CHANGELOG.md"
exit 1
fi

awk "/^## ${VERSION}$/{flag=1;next}/^## /{flag=0}flag" "$CHANGELOG" > /tmp/release-notes.md

if [[ ! -s /tmp/release-notes.md ]]; then
echo "❌ No changelog entry found for version ${VERSION}"
exit 1
fi

echo "✔ Extracted release notes for ${VERSION}"
