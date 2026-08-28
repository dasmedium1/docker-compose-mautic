#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# CONFIGURATION
# -------------------------

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME is required}"
DEPLOY_ROOT="${DEPLOY_DIR:?DEPLOY_DIR is required}"
BACKUP_ROOT="$DEPLOY_ROOT/backups/current"

MYSQL_DATABASE="${DB_NAME:?DB_NAME is required}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

DB_BACKUP="$BACKUP_ROOT/database.sql.gz"

# Persistent Mautic volumes to restore (keys defined in docker-compose.yml)
MAUTIC_DATA_VOLUMES=(mautic_config mautic_media_files mautic_media_images)

# -------------------------
# VALIDATION
# -------------------------

if [ ! -f "$DB_BACKUP" ]; then
  echo "❌ Database backup not found: $DB_BACKUP"
  exit 1
fi

for vol in "${MAUTIC_DATA_VOLUMES[@]}"; do
  TARBALL="$BACKUP_ROOT/${vol}.tar.gz"
  if [ ! -f "$TARBALL" ]; then
    echo "❌ Filesystem backup not found: $TARBALL"
    exit 1
  fi
done

echo "✔ Backup files validated"

# -------------------------
# LOCATE MYSQL CONTAINER
# -------------------------

echo "🔍 Locating MySQL container for project: $COMPOSE_PROJECT_NAME"

MYSQL_CONTAINER=$(docker ps \
  --filter "label=com.docker.compose.service=mautic_db" \
  --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" \
  --format '{{.Names}}')

if [ -z "$MYSQL_CONTAINER" ]; then
  echo "❌ Could not find MySQL container for project: $COMPOSE_PROJECT_NAME"
  exit 1
fi

echo "✔ Found MySQL container: $MYSQL_CONTAINER"

# -------------------------
# FILESYSTEM RESTORE (PER-VOLUME)
# -------------------------

for vol in "${MAUTIC_DATA_VOLUMES[@]}"; do
  V="${COMPOSE_PROJECT_NAME}_${vol}"
  echo "📁 Restoring Mautic volume: $V"

  # Ensure the volume exists (create it if the stack has not been started yet)
  docker volume inspect "$V" >/dev/null 2>&1 || docker volume create "$V"

  # Clear volume first to avoid residue
  docker run --rm \
    -v "${V}:/volume" \
    alpine \
    sh -c "rm -rf /volume/*"

  # Restore from backup
  docker run --rm \
    -v "${V}:/volume" \
    -v "${BACKUP_ROOT}:/backup:ro" \
    alpine \
    sh -c "cd /volume && tar -xzf /backup/${vol}.tar.gz"

  echo "✅ Filesystem restored into volume: $V"
done

# -------------------------
# DATABASE RESTORE
# -------------------------

echo "🛢 Restoring database: $MYSQL_DATABASE"

echo "🗑 Dropping and recreating database..."

docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" sh -c "
  mysql -u root -e '
    DROP DATABASE IF EXISTS \`${MYSQL_DATABASE}\`;
    CREATE DATABASE \`${MYSQL_DATABASE}\`;
  '
"

echo "📥 Importing database dump..."

gunzip < "$DB_BACKUP" | docker exec -i -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" sh -c "
  mysql -u root \"$MYSQL_DATABASE\"
"

echo "✅ Database restored"

# -------------------------
# COMPLETION
# -------------------------

echo "🎉 Restore completed successfully for project: $COMPOSE_PROJECT_NAME"
echo "   Filesystem volumes: ${MAUTIC_DATA_VOLUMES[*]}"
echo "   Database:           $MYSQL_DATABASE"
