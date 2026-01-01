#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# CONFIGURATION
# -------------------------

BRAND_NAME="${BRAND_NAME:-default}"

DEPLOY_ROOT="/home/angelantonio/backup/root/mautic"
BACKUP_ROOT="$DEPLOY_ROOT/backups/$BRAND_NAME/current"

MYSQL_DATABASE="${DB_NAME:?DB_NAME is required}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

FS_BACKUP="$BACKUP_ROOT/filesystem.tar.gz"
DB_BACKUP="$BACKUP_ROOT/database.sql.gz"

# Docker volume name (derived from compose project)
MAUTIC_VOLUME="${BRAND_NAME}_mautic"

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

echo "🔍 Locating MySQL container for brand: $BRAND_NAME"

MYSQL_CONTAINER=$(docker ps \
  --filter "label=com.docker.compose.service=mautic_db" \
  --filter "label=com.docker.compose.project=$BRAND_NAME" \
  --format '{{.Names}}')

if [ -z "$MYSQL_CONTAINER" ]; then
  echo "❌ Could not find MySQL container for brand: $BRAND_NAME"
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

docker exec "$MYSQL_CONTAINER" sh -c "
  mysql -u root -p\"$MYSQL_ROOT_PASSWORD\" -e '
    DROP DATABASE IF EXISTS \`${MYSQL_DATABASE}\`;
    CREATE DATABASE \`${MYSQL_DATABASE}\`;
  '
"

echo "📥 Importing database dump..."

gunzip < "$DB_BACKUP" | docker exec -i "$MYSQL_CONTAINER" sh -c "
  mysql -u root -p\"$MYSQL_ROOT_PASSWORD\" \"$MYSQL_DATABASE\"
"

echo "✅ Database restored"

# -------------------------
# COMPLETION
# -------------------------

echo "🎉 Restore completed successfully for brand: $BRAND_NAME"
echo "   Filesystem volume: $MAUTIC_VOLUME"
echo "   Database:          $MYSQL_DATABASE"
