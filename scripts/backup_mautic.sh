#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# CONFIGURATION
# -------------------------
BRAND_NAME="${BRAND_NAME:-default}"
DB_NAME="${DB_NAME:-mautic_db}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

# Canonical backup directory (per brand)
BACKUP_ROOT="/home/angelantonio/backups/${BRAND_NAME}/current"
mkdir -p "$BACKUP_ROOT"

BACKUP_RETENTION=14  # Number of previous backups to keep (optional rotation)

echo "## Starting backup for brand: $BRAND_NAME"
echo "## Backup directory: $BACKUP_ROOT"

# -------------------------
# DATABASE BACKUP
# -------------------------
echo "## Backing up database: $DB_NAME"

MYSQL_CONTAINER=$(docker compose ps -q mautic_db)
if [ -z "$MYSQL_CONTAINER" ]; then
    echo "❌ ERROR: Database container not running"
    exit 1
fi

docker exec "$MYSQL_CONTAINER" sh -c "
  mysqldump -u root -p\"$MYSQL_ROOT_PASSWORD\" $DB_NAME
" | gzip > "$BACKUP_ROOT/${DB_NAME}.sql.gz"

echo "✅ Database backup completed"

# -------------------------
# VOLUME BACKUP (named volumes)
# -------------------------
VOLUMES=("mautic_config" "mautic_logs" "mautic_media_files" "mautic_media_images" "mautic_cron")

for vol in "${VOLUMES[@]}"; do
    VOL_DIR="$BACKUP_ROOT/$vol"
    mkdir -p "$VOL_DIR"
    echo "## Backing up volume: $vol"
    docker run --rm -v "$vol":/data -v "$VOL_DIR":/backup alpine sh -c "cp -a /data/. /backup/"
done

echo "✅ Volumes backup completed"

# -------------------------
# RETENTION (optional)
# -------------------------
# If you want rotation, you can move the current backup to a .old folder first.
# Example:
# mv "$BACKUP_ROOT" "${BACKUP_ROOT}.prev"

echo "🎉 Backup completed successfully in canonical directory: $BACKUP_ROOT"
