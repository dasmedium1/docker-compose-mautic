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

MYSQL_DATABASE="${DB_NAME:?DB_NAME is required}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

# Docker volume names (derived from compose project)
MAUTIC_VOLUME="${BRAND_NAME}_mautic"

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
# VALIDATE MAUTIC VOLUME
# -------------------------

echo "🔍 Validating Mautic volume: $MAUTIC_VOLUME"

if ! docker volume inspect "$MAUTIC_VOLUME" >/dev/null 2>&1; then
  echo "❌ Mautic volume not found: $MAUTIC_VOLUME"
  exit 1
fi

echo "✔ Found volume: $MAUTIC_VOLUME"

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
# RETENTION POLICY (keep last 14 archives)
# -------------------------

RETENTION=14
ARCHIVED_COUNT=$(find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
if [ "$ARCHIVED_COUNT" -gt "$RETENTION" ]; then
  TO_PRUNE=$((ARCHIVED_COUNT - RETENTION))
  find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | head -n "$TO_PRUNE" | while IFS= read -r NAME; do
    echo "🗑 Pruning old backup: $ARCHIVE_DIR/$NAME"
    rm -rf "$ARCHIVE_DIR/${NAME:?}"
  done
fi

# -------------------------
# FILESYSTEM BACKUP (VOLUME)
# -------------------------

echo "📁 Backing up Mautic filesystem from Docker volume..."

docker run --rm \
  -v "${MAUTIC_VOLUME}:/volume:ro" \
  -v "${CURRENT_DIR}:/backup" \
  alpine \
  sh -c "cd /volume && tar -czf /backup/filesystem.tar.gz ."

echo "✅ Filesystem backup created: $FS_BACKUP"

# -------------------------
# DATABASE BACKUP (LOGICAL)
# -------------------------

echo "🛢 Backing up database: $MYSQL_DATABASE"

docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$MYSQL_CONTAINER" sh -c "
  mysqldump \
    -u root \
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
