#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# CONFIGURATION
# -------------------------

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME is required}"
DEPLOY_ROOT="${DEPLOY_DIR:?DEPLOY_DIR is required}"
BACKUP_ROOT="$DEPLOY_ROOT/backups"

CURRENT_DIR="$BACKUP_ROOT/current"
ARCHIVE_DIR="$BACKUP_ROOT/archive"

MYSQL_DATABASE="${DB_NAME:?DB_NAME is required}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"

# Persistent Mautic volumes to back up (keys defined in docker-compose.yml)
MAUTIC_DATA_VOLUMES=(mautic_config mautic_media_files mautic_media_images)

mkdir -p "$CURRENT_DIR" "$ARCHIVE_DIR"

DB_BACKUP="$CURRENT_DIR/database.sql.gz"

# -------------------------
# LOCATE MYSQL CONTAINER
# -------------------------

echo "🔍 Locating MySQL container for project: $COMPOSE_PROJECT_NAME"

MYSQL_CONTAINER=$(docker ps \
  --filter "label=com.docker.compose.service=mautic_db" \
  --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" \
  --format '{{.Names}}')

if [ -z "$MYSQL_CONTAINER" ]; then
  echo "⚠ No running MySQL container for project '$COMPOSE_PROJECT_NAME'; nothing to back up. Skipping."
  exit 0
fi

echo "✔ Found MySQL container: $MYSQL_CONTAINER"

# -------------------------
# ARCHIVE PREVIOUS BACKUP
# -------------------------

if [ -n "$(find "$CURRENT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
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
# FILESYSTEM BACKUP (PER-VOLUME)
# -------------------------

for vol in "${MAUTIC_DATA_VOLUMES[@]}"; do
  V="${COMPOSE_PROJECT_NAME}_${vol}"
  if docker volume inspect "$V" >/dev/null 2>&1; then
    echo "📁 Backing up Mautic volume: $V"
    docker run --rm \
      -v "${V}:/volume:ro" \
      -v "${CURRENT_DIR}:/backup" \
      alpine \
      sh -c "cd /volume && tar -czf /backup/${vol}.tar.gz ."
    echo "✅ Volume backup created: ${vol}.tar.gz"
  else
    echo "⚠ Volume '$V' not found; skipping."
  fi
done

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

echo "🎉 Backup completed successfully for project: $COMPOSE_PROJECT_NAME"
echo "   Filesystem volumes: ${MAUTIC_DATA_VOLUMES[*]}"
echo "   Database:           $DB_BACKUP"
