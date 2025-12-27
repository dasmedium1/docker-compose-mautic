#!/usr/bin/env bash
set -euo pipefail

# Multi‑brand support: accept brand identifier as first argument
BRAND_ID="${1:-default}"
if [ "$BRAND_ID" = "default" ]; then
    VOLUME_PREFIX="mautic"
    DB_NAME="mautic_db"
    COMPOSE_PROJECT_NAME="basic"
else
    VOLUME_PREFIX="mautic_${BRAND_ID}"
    DB_NAME="mautic_${BRAND_ID}"
    COMPOSE_PROJECT_NAME="basic-${BRAND_ID}"
fi

# -------------------------
# CONFIGURATION
# -------------------------

BACKUP_ROOT="/home/angelantonio/backup/root/mautic"
BACKUP_DIR="$BACKUP_ROOT/backups"
BACKUP_NAME="backup-${BRAND_ID}-$(date +%F).tar.gz"
DB_BACKUP_NAME="db-backup-${BRAND_ID}-$(date +%F).sql.gz"
DB_BACKUP_FILE="$BACKUP_DIR/$DB_BACKUP_NAME"

MYSQL_CONTAINER_NAME="${COMPOSE_PROJECT_NAME}-mautic_db-1"
MYSQL_DATABASE="${DB_NAME}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

BACKUP_RETENTION=14  # Number of backups to retain

# -------------------------
# FILESYSTEM BACKUP
# -------------------------

echo "📁 Checking backup source directory: $BACKUP_ROOT"
if [ ! -d "$BACKUP_ROOT" ]; then
  echo "❌ ERROR: Backup source directory does not exist: $BACKUP_ROOT"
  exit 1
fi

DATA_DIRS=(mautic/config mautic/logs mautic/media/files mautic/media/images cron)
HAS_DATA=false

for dir in "${DATA_DIRS[@]}"; do
  FULL_PATH="$BACKUP_ROOT/$dir"
  if [ -d "$FULL_PATH" ] && [ -n "$(ls -A "$FULL_PATH" 2>/dev/null || true)" ]; then
    echo "✔ Found data in: $FULL_PATH"
    HAS_DATA=true
  fi
done

if [ "$HAS_DATA" = false ]; then
  echo "❌ No data found in critical directories — aborting filesystem backup."
  exit 1
fi

mkdir -p "$BACKUP_DIR"
cd "$BACKUP_ROOT"

echo "📦 Creating filesystem backup: $BACKUP_NAME"
tar --gzip -cf "$BACKUP_DIR/$BACKUP_NAME" mautic cron
echo "✅ Filesystem backup created: $BACKUP_DIR/$BACKUP_NAME"

# -------------------------
# DATABASE BACKUP
# -------------------------

echo "🛢 Creating database backup..."

docker exec "$MYSQL_CONTAINER_NAME" sh -c "
  echo '[client]' > /tmp/my.cnf
  echo 'user=root' >> /tmp/my.cnf
  echo 'password=$MYSQL_ROOT_PASSWORD' >> /tmp/my.cnf
  chmod 600 /tmp/my.cnf
  mysqldump --defaults-extra-file=/tmp/my.cnf \
    --single-transaction --quick --lock-tables=false \
    $MYSQL_DATABASE
" | gzip > "$DB_BACKUP_FILE"

docker exec "$MYSQL_CONTAINER_NAME" rm -f /tmp/my.cnf || true

echo "✅ Database backup created: $DB_BACKUP_FILE"

# -------------------------
# RETENTION
# -------------------------

echo "🧹 Applying retention policy (keep last $BACKUP_RETENTION backups)..."
cd "$BACKUP_DIR"

TOTAL_BACKUPS=$(ls -1 backup-*.tar.gz db-backup-*.sql.gz 2>/dev/null | wc -l || true)

if [ "$TOTAL_BACKUPS" -gt "$BACKUP_RETENTION" ]; then
  REMOVE_COUNT=$((TOTAL_BACKUPS - BACKUP_RETENTION))
  echo "Removing $REMOVE_COUNT old backup(s)..."
  ls -1tr backup-*.tar.gz db-backup-*.sql.gz | head -n "$REMOVE_COUNT" | xargs rm -f
  echo "🗑 Old backups removed."
else
  echo "No backups to remove. ($TOTAL_BACKUPS ≤ $BACKUP_RETENTION)"
fi

echo "🎉 Backup + DB dump + retention complete."
