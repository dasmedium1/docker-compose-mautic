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

FS_BACKUP="$BACKUP_ROOT/filesystem.tar.gz"
DB_BACKUP="$BACKUP_ROOT/database.sql.gz"

# Docker volume name (derived from the compose project)
MAUTIC_VOLUME="${COMPOSE_PROJECT_NAME}_mautic"

# -------------------------
# VALIDATION
# -------------------------

if [ ! -f "$FS_BACKUP" ]; then
  echo "❌ Filesystem backup not found: $FS_BACKUP"
  exit 1
fi

if [ ! -f "$DB_BACKUP" ]; then
  echo "❌ Database backup not found: $DB_BACKUP"
  exit 1
fi

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
# VALIDATE MAUTIC VOLUME
# -------------------------

echo "🔍 Validating Mautic volume: $MAUTIC_VOLUME"

if ! docker volume inspect "$MAUTIC_VOLUME" >/dev/null 2>&1; then
  echo "❌ Mautic volume not found: $MAUTIC_VOLUME"
  exit 1
fi

echo "✔ Found volume: $MAUTIC_VOLUME"

# -------------------------
# FILESYSTEM RESTORE (VOLUME)
# -------------------------

echo "📁 Restoring Mautic filesystem into Docker volume..."

# Clear volume first to avoid residue
docker run --rm \
  -v "${MAUTIC_VOLUME}:/volume" \
  alpine \
  sh -c "rm -rf /volume/*"

# Restore from backup
docker run --rm \
  -v "${MAUTIC_VOLUME}:/volume" \
  -v "${BACKUP_ROOT}:/backup:ro" \
  alpine \
  sh -c "cd /volume && tar -xzf /backup/filesystem.tar.gz"

echo "✅ Filesystem restored into volume"

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
echo "   Filesystem volume: $MAUTIC_VOLUME"
echo "   Database:          $MYSQL_DATABASE"
