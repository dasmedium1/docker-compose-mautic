#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# CONFIGURATION
# -------------------------

BRAND_NAME="${BRAND_NAME:-default}"
DEPLOY_ROOT="/home/angelantonio/backup/root/mautic"
BACKUP_ROOT="$DEPLOY_ROOT/backups/$BRAND_NAME/current"

MYSQL_DATABASE="${DB_NAME}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

FS_BACKUP="$BACKUP_ROOT/filesystem.tar.gz"
DB_BACKUP="$BACKUP_ROOT/database.sql.gz"

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
# FILESYSTEM RESTORE
# -------------------------

echo "📁 Restoring filesystem..."

cd "$DEPLOY_ROOT"

# Preserve existing files in case of partial failure
RESTORE_TMP="$(mktemp -d)"

tar -xzf "$FS_BACKUP" -C "$RESTORE_TMP"

rsync -a --delete "$RESTORE_TMP/mautic/" mautic/
rsync -a --delete "$RESTORE_TMP/cron/" cron/

rm -rf "$RESTORE_TMP"

echo "✅ Filesystem restored"

# -------------------------
# DATABASE RESTORE
# -------------------------

echo "🛢 Restoring database: $MYSQL_DATABASE"

docker exec -i "$MYSQL_CONTAINER" sh -c "
  mysql \
    -u root \
    -p\"$MYSQL_ROOT_PASSWORD\" \
    $MYSQL_DATABASE
" < <(gunzip -c "$DB_BACKUP")

echo "✅ Database restored"

# -------------------------
# COMPLETION
# -------------------------

echo "🎉 Restore completed successfully for brand: $BRAND_NAME"
