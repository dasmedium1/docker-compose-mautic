#!/usr/bin/env bash
set -euo pipefail
cd /home/angelantonio/backup/root/mautic
: "${BRAND_NAME:?BRAND_NAME must be set}"

echo "🔄 Recreating containers for brand: ${BRAND_NAME}"

docker compose \
  --project-name "${BRAND_NAME}" \
  pull

docker compose \
  --project-name "${BRAND_NAME}" \
  up -d 

echo "✅ Containers recreated successfully for brand: ${BRAND_NAME}"
