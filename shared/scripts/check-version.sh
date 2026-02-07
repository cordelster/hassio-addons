#!/usr/bin/env bash
set -euo pipefail

CONFIG="$1/config.yaml"

VERSION=$(yq '.version' "$CONFIG")

REGEX='^HA\.[0-9]+\.[0-9]+\.[0-9]+-$slug\.[0-9]+\.[0-9]+\.[0-9]+$'

if [[ ! "$VERSION" =~ $REGEX ]]; then
  echo "❌ Invalid version format: $VERSION"
  echo "Expected: HA.X.Y.Z-$slug.A.B.C"
  exit 1
fi

echo "✔ Version format OK: $VERSION"

