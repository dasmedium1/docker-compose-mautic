#!/usr/bin/env bash
set -euo pipefail

# --------------------------
# CONFIGURATION
# --------------------------
BACKUP_DIR="/home/angelantonio/backup/root/mautic/backups"
MYSQL_CONTAINER_NAME="basic-mautic_db-1"
MYSQL_DATABASE="mautic_db"
MYSQL_USER="mautic_db_user"
MYSQL_PASSWORD="${MYSQL_PASSWORD}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"

# --------------------------
# VALIDATE INPUT ARGUMENT
# --------------------------
if [ $# -ne 1 ]; then
  echo "❌ Usage: $0 <backup-file-prefix>"
  echo "   Example: $0 2025-12-02"
  exit 1
fi

PREFIX="$1"
FS_BACKUP="$BACKUP_DIR/backup-$PREFIX.tar.gz"
DB_BACKUP="$BACKUP_DIR/db-backup-$PREFIX.sql.gz"

echo "🔍 Looking for backups:"
echo "📦 Filesystem: $FS_BACKUP"
echo "🛢 Database:    $DB_BACKUP"

if [ ! -f "$FS_BACKUP" ]; then
  echo "❌ Filesystem backup not found: $FS_BACKUP"
  exit 1
fi

if [ ! -f "$DB_BACKUP" ]; then
  echo "❌ Database backup not found: $DB_BACKUP"
  exit 1
fi

# --------------------------
# RESTORE FILESYSTEM
# --------------------------
echo "📁 Restoring filesystem..."
cd /home/angelantonio/backup/root/mautic
tar -xzf "$FS_BACKUP"
echo "✔ Filesystem restored."

# --------------------------
# RESTORE DATABASE
# --------------------------
echo "🛢 Restoring database ($MYSQL_DATABASE)..."

docker exec "$MYSQL_CONTAINER_NAME" \
  sh -c "mysql -u root -p\"$MYSQL_ROOT_PASSWORD\" -e 'DROP DATABASE IF EXISTS ${MYSQL_DATABASE}; CREATE DATABASE ${MYSQL_DATABASE};'"

gunzip < "$DB_BACKUP" | docker exec -i "$MYSQL_CONTAINER_NAME" \
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"

echo "✔ Database restored."

# --------------------------
# RE-APPLY PRIVILEGES
# --------------------------
echo "🔐 Reapplying database user privileges..."

docker exec "$MYSQL_CONTAINER_NAME" \
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
    GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
    FLUSH PRIVILEGES;
  "

echo "🔑 Database privileges restored for user: $MYSQL_USER"

# --------------------------
# SUCCESS MESSAGE
# --------------------------
echo "🎉 Restore completed successfully for prefix: $PREFIX"
echo "   Mautic should now be fully operational."
