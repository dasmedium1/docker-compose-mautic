#!/usr/bin/env bash
set -euo pipefail
cd "${DEPLOY_DIR:?DEPLOY_DIR is required}"

echo "🔄 Recreating containers for project: ${COMPOSE_PROJECT_NAME:-<from .env>}"

docker compose up -d --force-recreate

echo "✅ Containers recreated successfully"
