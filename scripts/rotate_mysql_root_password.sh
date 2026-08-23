#!/usr/bin/env bash
set -euo pipefail

BRAND_NAME="${BRAND_NAME:?}"
OLD_ROOT_PASSWORD="${OLD_ROOT_PASSWORD:?}"
NEW_ROOT_PASSWORD="${NEW_ROOT_PASSWORD:?}"

MYSQL_CONTAINER=$(docker ps \
  --filter "label=com.docker.compose.service=mautic_db" \
  --filter "label=com.docker.compose.project=$BRAND_NAME" \
  --format '{{.Names}}')

if [ -z "$MYSQL_CONTAINER" ]; then
  echo "❌ MySQL container not found"
  exit 1
fi

docker exec -e MYSQL_PWD="$OLD_ROOT_PASSWORD" "$MYSQL_CONTAINER" mysql \
  -u root \
  -e "
    ALTER USER 'root'@'%' IDENTIFIED BY '$NEW_ROOT_PASSWORD';
    FLUSH PRIVILEGES;
  "
