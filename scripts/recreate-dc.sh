#!/usr/bin/env bash
set -euo pipefail

: "${BRAND_NAME:?BRAND_NAME must be set}"

echo "🔄 Recreating containers for brand: ${BRAND_NAME}"

docker compose \
  --project-name "${BRAND_NAME}" \
  pull

docker compose \
  --project-name "${BRAND_NAME}" \
  up -d \
  --force-recreate \
  --remove-orphans

echo "✅ Containers recreated successfully for brand: ${BRAND_NAME}"
