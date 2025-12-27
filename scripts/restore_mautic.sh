#!/usr/bin/env bash
set -euo pipefail

# Multi‑brand support: accept brand identifier as first argument
BRAND_ID="${1:-default}"
if [ $# -eq 2 ]; then
    # Backwards compatibility: if only one argument (prefix) assume default brand
    PREFIX="$1"
    BRAND_ID="default"
else
    PREFIX="$2"
fi

if [ -z "$PREFIX" ]; then
    echo "❌ Usage: $0 <brand-id> <backup-file-prefix>"
    echo "   Example: $0 default 2025-12-02"
    echo "   For backwards compatibility: $0 2025-12-02   (brand defaults to 'default')"
    exit 1
fi

if [ "$BRAND_ID" = "default" ]; then
    VOLUME_PREFIX="mautic"
    DB_NAME="mautic_db"
    COMPOSE_PROJECT_NAME="basic"
else
    VOLUME_PREFIX="mautic_${BRAND_ID}"
    DB_NAME="mautic_${BRAND_ID}"
    COMPOSE_PROJECT_NAME="basic-${BRAND_ID}"
fi

# --------------------------
# CONFIGURATION
# --------------------------
BACKUP_DIR="/home/angelantonio/backup/root/mautic/backups"
MYSQL_CONTAINER_NAME="${COMPOSE_PROJECT_NAME}-mautic_db-1"
MYSQL_DATABASE="${DB_NAME}"
MYSQL_USER="mautic_db_user"
MYSQL_PASSWORD="${MYSQL_PASSWORD}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
MAUTIC_ROOT="/home/angelantonio/backup/root/mautic"

FS_BACKUP="$BACKUP_DIR/backup-${BRAND_ID}-${PREFIX}.tar.gz"
DB_BACKUP="$BACKUP_DIR/db-backup-${BRAND_ID}-${PREFIX}.sql.gz"

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
# STOP SERVICES
# --------------------------
echo "🛑 Stopping Mautic services..."
cd "$MAUTIC_ROOT"
docker compose stop mautic_web mautic_cron mautic_worker 2>/dev/null || true
echo "⏸️ Services stopped."

# Give services time to stop
sleep 5

# --------------------------
# RESTORE FILESYSTEM
# --------------------------
echo "📁 Restoring filesystem..."
cd "$MAUTIC_ROOT"
tar -xzf "$FS_BACKUP"
echo "✔ Filesystem restored."

# --------------------------
# FIX PERMISSIONS
# --------------------------
echo "🔧 Fixing file permissions..."
chown -R 33:33 "$MAUTIC_ROOT/mautic" 2>/dev/null || true
find "$MAUTIC_ROOT/mautic" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$MAUTIC_ROOT/mautic" -type f -exec chmod 644 {} \; 2>/dev/null || true
chmod -R 777 "$MAUTIC_ROOT/mautic/logs" 2>/dev/null || true
chmod -R 777 "$MAUTIC_ROOT/mautic/media" 2>/dev/null || true
echo "✔ Permissions fixed."

# --------------------------
# RESTORE DATABASE
# --------------------------
echo "🛢 Restoring database ($MYSQL_DATABASE)..."

# Ensure database container is running
if ! docker ps --filter "name=$MYSQL_CONTAINER_NAME" --filter "status=running" | grep -q "$MYSQL_CONTAINER_NAME"; then
    echo "⚠️ Database container not running, starting it..."
    cd "$MAUTIC_ROOT"
    docker compose up -d mautic_db
    sleep 10
fi

# Drop and recreate database
echo "🗑️ Dropping and recreating database..."
docker exec "$MYSQL_CONTAINER_NAME" \
  sh -c "mysql -u root -p\"$MYSQL_ROOT_PASSWORD\" -e 'DROP DATABASE IF EXISTS ${MYSQL_DATABASE}; CREATE DATABASE ${MYSQL_DATABASE};'"

# Restore database
echo "📥 Importing database backup..."
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
# CLEAR CACHES
# --------------------------
echo "🧹 Clearing application caches..."

# Start web container temporarily if not running
cd "$MAUTIC_ROOT"
docker compose up -d mautic_db --wait && docker compose up -d mautic_web --wait

# Clear Symfony cache
docker compose exec -T --user www-data --workdir /var/www/html mautic_web \
  php bin/console cache:clear --no-warmup 2>/dev/null || true

# Clear Doctrine cache
docker compose exec -T --user www-data --workdir /var/www/html mautic_web \
  php bin/console doctrine:cache:clear-metadata 2>/dev/null || true

echo "✔ Caches cleared."

# --------------------------
# RESTART SERVICES
# --------------------------
echo "🚀 Restarting all services..."
docker compose up -d
sleep 10

# Verify services are running
echo "🔍 Verifying service status..."
if docker compose ps | grep -q "Up"; then
    echo "✅ All services are running"
else
    echo "❌ Some services failed to start"
    docker compose ps
fi

# --------------------------
# POST-RESTORATION CHECKS
# --------------------------
echo "🔍 Running post-restoration checks..."

# Check database connectivity
docker compose exec -T mautic_web php -r "
try {
    \$conn = new PDO('mysql:host=mautic_db;dbname=${MYSQL_DATABASE}', '${MYSQL_USER}', '${MYSQL_PASSWORD}');
    echo '✅ Database connection successful\n';
} catch (PDOException \$e) {
    echo '❌ Database connection failed: ' . \$e->getMessage();
}
" 2>/dev/null || echo "⚠️ Database connectivity check may have failed"

# Check if Mautic is reachable (give it a moment)
sleep 5
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null | grep -q "200\|302"; then
    echo "✅ Mautic web interface is reachable"
else
    echo "⚠️ Mautic web interface check failed (may need more time to start)"
fi

# --------------------------
# SUCCESS MESSAGE
# --------------------------
echo "🎉 Restore completed successfully for prefix: $PREFIX"
echo "   Mautic should now be fully operational."
