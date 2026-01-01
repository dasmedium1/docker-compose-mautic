#!/usr/bin/env bash
set -euo pipefail

BRAND_NAME="${BRAND_NAME:?}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?}"
NEW_DB_PASSWORD="${NEW_DB_PASSWORD:?}"
MYSQL_DATABASE="${MYSQL_DATABASE:?}"
MYSQL_USER="${MYSQL_USER:?}"

MYSQL_CONTAINER=$(docker ps \
  --filter "label=com.docker.compose.service=mautic_db" \
  --filter "label=com.docker.compose.project=$BRAND_NAME" \
  --format '{{.Names}}')

docker exec "$MYSQL_CONTAINER" mysql \
  -u root -p"$MYSQL_ROOT_PASSWORD" \
  -e "
    ALTER USER '$MYSQL_USER'@'%' IDENTIFIED BY '$NEW_DB_PASSWORD';
    FLUSH PRIVILEGES;
  "
