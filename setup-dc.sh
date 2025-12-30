#!/bin/bash
set -e

cd /home/angelantonio/backup/root/mautic

echo "## setup-dc.sh starting"

# ----------------------------------------
# Resolve COMPOSE_PROJECT_NAME safely
# ----------------------------------------
if [ -z "${COMPOSE_PROJECT_NAME:-}" ] && [ -f .env ]; then
    _line=$(grep -E '^COMPOSE_PROJECT_NAME=' .env | head -1 || true)
    if [ -n "$_line" ]; then
        COMPOSE_PROJECT_NAME="${_line#*=}"
        COMPOSE_PROJECT_NAME=$(echo "$COMPOSE_PROJECT_NAME" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
        export COMPOSE_PROJECT_NAME
        echo "## Using COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME"
    fi
fi

# ----------------------------------------
# Ensure required network exists
# ----------------------------------------
if ! docker network inspect mysql_private >/dev/null 2>&1; then
    echo "## Creating mysql_private network"
    docker network create -d overlay --attachable mysql_private
fi

# ----------------------------------------
# Start required services
# ----------------------------------------
echo "## Starting database"
docker compose up -d mautic_db --wait

echo "## Starting mautic_web"
docker compose up -d mautic_web --wait

# ----------------------------------------
# Wait for mautic_web container (Compose-safe)
# ----------------------------------------
echo "## Waiting for mautic_web service container"

MAX_ATTEMPTS=30
ATTEMPT=0

while true; do
    WEB_CONTAINER_ID=$(docker compose ps -q mautic_web || true)

    if [ -n "$WEB_CONTAINER_ID" ]; then
        if docker inspect -f '{{.State.Running}}' "$WEB_CONTAINER_ID" 2>/dev/null | grep -q true; then
            echo "## mautic_web is running ($WEB_CONTAINER_ID)"
            break
        fi
    fi

    ATTEMPT=$((ATTEMPT+1))
    if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
        echo "### ERROR: mautic_web did not start in time"
        docker compose ps
        docker compose logs --tail=50 mautic_web
        exit 1
    fi

    echo "### Waiting for mautic_web... ($ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2
done

# ----------------------------------------
# Check if Mautic is installed
# ----------------------------------------
echo "## Checking if Mautic is installed"

if docker compose exec -T mautic_web test -f /var/www/html/config/local.php && \
   docker compose exec -T mautic_web grep -q "site_url" /var/www/html/config/local.php; then
    echo "## Mautic already installed"
else
    # ----------------------------------------
    # Stop worker to avoid known issue
    # ----------------------------------------
    WORKER_CONTAINER_ID=$(docker compose ps -q mautic_worker || true)
    if [ -n "$WORKER_CONTAINER_ID" ]; then
        echo "## Stopping mautic_worker to avoid known install issue"
        docker stop "$WORKER_CONTAINER_ID"
    fi

    echo "## Installing Mautic"
    docker compose exec -T -u www-data -w /var/www/html mautic_web \
        php ./bin/console mautic:install --force \
        --admin_email {{EMAIL_ADDRESS}} \
        --admin_password {{MAUTIC_PASSWORD}} \
        https://{{DOMAIN_NAME}}
fi

# ----------------------------------------
# Start all containers
# ----------------------------------------
echo "## Ensuring all services are running"
docker compose up -d

# ----------------------------------------
# Post-install configuration
# ----------------------------------------
DOMAIN="{{DOMAIN_NAME}}"

if [[ "$DOMAIN" == *"DOMAIN_NAME"* || -z "$DOMAIN" ]]; then
    echo "## DOMAIN not set — skipping post-install configuration"
    exit 0
fi

echo "## Updating site_url and trusted proxies"

docker compose exec -T mautic_web sed -i \
    "s|'site_url' => '.*',|'site_url' => 'https://$DOMAIN',|g" \
    /var/www/html/config/local.php

# ----------------------------------------
# Detect Traefik network/subnet
# ----------------------------------------
TRAEFIK_CONTAINER=$(docker ps --filter "name=traefik" --format "{{.Names}}" | head -n1)

if [ -z "$TRAEFIK_CONTAINER" ]; then
    echo "## Traefik not detected, using fallback subnet"
    TRAEFIK_SUBNET="10.0.1.0/24"
else
    TRAEFIK_NETWORK=$(docker inspect "$TRAEFIK_CONTAINER" \
        --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -n1)
    TRAEFIK_SUBNET=$(docker network inspect "$TRAEFIK_NETWORK" \
        -f '{{(index .IPAM.Config 0).Subnet}}')
fi

docker compose exec -T mautic_web bash -c "cat >> /var/www/html/config/local.php" <<EOF
\$parameters['trusted_proxies'] = ['$TRAEFIK_SUBNET'];
\$parameters['trusted_headers'] = [
    'forwarded' => 'FORWARDED',
    'x-forwarded-for' => 'X_FORWARDED_FOR',
    'x-forwarded-host' => 'X_FORWARDED_HOST',
    'x-forwarded-proto' => 'X_FORWARDED_PROTO',
    'x-forwarded-port' => 'X_FORWARDED_PORT'
];
EOF

echo "## Clearing cache"
docker compose exec -T --user www-data --workdir /var/www/html mautic_web \
    php bin/console cache:clear

echo "## setup-dc.sh completed successfully"
