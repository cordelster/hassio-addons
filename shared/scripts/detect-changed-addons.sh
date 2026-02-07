#!/usr/bin/env bash
set -euo pipefail

BASE_REF="${1:-origin/main}"

git diff --name-only "$BASE_REF"...HEAD \
  | awk -F/ '/^addons\// {print $2}' \
  | sort -u

