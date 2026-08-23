#!/usr/bin/env bash
set -euo pipefail

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:?}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?}"
NEW_DB_PASSWORD="${NEW_DB_PASSWORD:?}"
MYSQL_USER="${MYSQL_USER:?}"

MYSQL_CONTAINER=$(docker ps \
  --filter "label=com.docker.compose.service=mautic_db" \
  --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" \
  --format '{{.Names}}')

docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" mysql \
  -u root \
  -e "
    ALTER USER '$MYSQL_USER'@'%' IDENTIFIED BY '$NEW_DB_PASSWORD';
    FLUSH PRIVILEGES;
  "
