#!/usr/bin/env bash
set -euo pipefail

# --------------------------
# CONFIGURATION
# --------------------------
BRAND_NAME="${BRAND_NAME:-default}"
DB_NAME="${DB_NAME:-mautic_db}"
MYSQL_USER="mautic_db_user"
MYSQL_PASSWORD="${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

# Canonical backup path
BACKUP_ROOT="/home/angelantonio/backups/${BRAND_NAME}/current"
echo "## Restoring brand: $BRAND_NAME"
echo "## Backup directory: $BACKUP_ROOT"

# --------------------------
# VALIDATE BACKUPS EXIST
# --------------------------
DB_BACKUP="$BACKUP_ROOT/${DB_NAME}.sql.gz"

if [ ! -f "$DB_BACKUP" ]; then
    echo "❌ Database backup not found: $DB_BACKUP"
    exit 1
fi

# --------------------------
# STOP SERVICES
# --------------------------
echo "🛑 Stopping Mautic services..."
docker compose stop mautic_web mautic_cron mautic_worker 2>/dev/null || true
sleep 5

# --------------------------
# RESTORE VOLUMES (named volumes)
# --------------------------
VOLUMES=("mautic_config" "mautic_logs" "mautic_media_files" "mautic_media_images" "mautic_cron")

for vol in "${VOLUMES[@]}"; do
    VOL_BACKUP="$BACKUP_ROOT/$vol"
    if [ -d "$VOL_BACKUP" ]; then
        echo "📁 Restoring volume: $vol"
        docker run --rm -v "$vol":/data -v "$VOL_BACKUP":/backup alpine sh -c "rm -rf /data/* && cp -a /backup/. /data/"
    else
        echo "⚠️ Backup for volume not found: $VOL_BACKUP"
    fi
done

# --------------------------
# RESTORE DATABASE
# --------------------------
echo "🛢 Restoring database ($DB_NAME)..."

MYSQL_CONTAINER=$(docker compose ps -q mautic_db)
if [ -z "$MYSQL_CONTAINER" ]; then
    echo "⚠️ Database container not running, starting it..."
    docker compose up -d mautic_db
    sleep 10
fi

docker exec "$MYSQL_CONTAINER" sh -c "
    mysql -u root -p\"$MYSQL_ROOT_PASSWORD\" -e 'DROP DATABASE IF EXISTS ${DB_NAME}; CREATE DATABASE ${DB_NAME};'
"

gunzip < "$DB_BACKUP" | docker exec -i "$MYSQL_CONTAINER" \
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$DB_NAME"

docker exec "$MYSQL_CONTAINER" mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
    GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${MYSQL_USER}'@'%';
    FLUSH PRIVILEGES;
"

echo "✅ Database restored"

# --------------------------
# CLEAR CACHES
# --------------------------
docker compose up -d mautic_web --wait
docker compose exec -T --user www-data --workdir /var/www/html mautic_web \
    php bin/console cache:clear --no-warmup 2>/dev/null || true
docker compose exec -T --user www-data --workdir /var/www/html mautic_web \
    php bin/console doctrine:cache:clear-metadata 2>/dev/null || true

# --------------------------
# RESTART SERVICES
# --------------------------
echo "🚀 Restarting all services..."
docker compose up -d
sleep 10

# --------------------------
# POST-RESTORATION CHECKS
# --------------------------
if docker compose ps | grep -q "Up"; then
    echo "✅ All services are running"
else
    echo "❌ Some services failed to start"
    docker compose ps
fi

# Database connectivity check
docker compose exec -T mautic_web php -r "
try {
    \$conn = new PDO('mysql:host=mautic_db;dbname=${DB_NAME}', '${MYSQL_USER}', '${MYSQL_PASSWORD}');
    echo '✅ Database connection successful\n';
} catch (PDOException \$e) {
    echo '❌ Database connection failed: ' . \$e->getMessage();
}
" 2>/dev/null || echo "⚠️ Database connectivity check may have failed"

# Web interface check
sleep 5
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null | grep -q "200\|302"; then
    echo "✅ Mautic web interface is reachable"
else
    echo "⚠️ Mautic web interface check failed"
fi

echo "🎉 Restore completed successfully for brand: $BRAND_NAME"
