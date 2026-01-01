#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# CONFIGURATION
# -------------------------

BRAND_NAME="${BRAND_NAME:-default}"
DEPLOY_ROOT="/home/angelantonio/backup/root/mautic"
BACKUP_ROOT="$DEPLOY_ROOT/backups/$BRAND_NAME"

CURRENT_DIR="$BACKUP_ROOT/current"
ARCHIVE_DIR="$BACKUP_ROOT/archive"

MYSQL_DATABASE="${DB_NAME}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

mkdir -p "$CURRENT_DIR" "$ARCHIVE_DIR"

FS_BACKUP="$CURRENT_DIR/filesystem.tar.gz"
DB_BACKUP="$CURRENT_DIR/database.sql.gz"

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
# ARCHIVE PREVIOUS BACKUP
# -------------------------

if [ -f "$FS_BACKUP" ] || [ -f "$DB_BACKUP" ]; then
  TS=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$ARCHIVE_DIR/$TS"
  mv "$CURRENT_DIR"/* "$ARCHIVE_DIR/$TS/" || true
  echo "📦 Previous backup archived to: $ARCHIVE_DIR/$TS"
fi

# -------------------------
# FILESYSTEM BACKUP
# -------------------------

echo "📁 Backing up filesystem..."

cd "$DEPLOY_ROOT"

tar -czf "$FS_BACKUP" \
  mautic \
  cron

echo "✅ Filesystem backup created: $FS_BACKUP"

# -------------------------
# DATABASE BACKUP
# -------------------------

echo "🛢 Backing up database: $MYSQL_DATABASE"

docker exec "$MYSQL_CONTAINER" sh -c "
  mysqldump \
    -u root \
    -p\"$MYSQL_ROOT_PASSWORD\" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    $MYSQL_DATABASE
" | gzip > "$DB_BACKUP"

echo "✅ Database backup created: $DB_BACKUP"

# -------------------------
# COMPLETION
# -------------------------

echo "🎉 Backup completed successfully for brand: $BRAND_NAME"
echo "   Filesystem: $FS_BACKUP"
echo "   Database:   $DB_BACKUP"
