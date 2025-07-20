#!/bin/bash
cd /home/angelantonio/backup/root/mautic

# Check/create required networks
if ! docker network inspect mysql_private >/dev/null 2>&1; then
    echo "Creating mysql_private network..."
    docker network create mysql_private
fi

docker compose build
docker compose up -d mautic_db --wait && docker compose up -d mautic_web --wait

echo "## Wait for basic-mautic_web-1 container to be fully running"
while ! docker exec basic-mautic_web-1 sh -c 'echo "Container is running"'; do
    echo "### Waiting for basic-mautic_web-1 to be fully running..."
    sleep 2
done

echo "## Check if Mautic is installed"
if docker compose exec -T mautic_web test -f /var/www/html/config/local.php && \
   docker compose exec -T mautic_web grep -q "site_url" /var/www/html/config/local.php; then
    echo "## Mautic is installed already."
else
    # Stop worker container to avoid known Mautic issue
    if docker ps --filter "name=basic-mautic_worker-1" --filter "status=running" -q | grep -q .; then
        echo "Stopping basic-mautic_worker-1 to avoid https://github.com/mautic/docker-mautic/issues/270"
        docker stop basic-mautic_worker-1
        echo "## Ensure the worker is stopped before installing Mautic"
        while docker ps -q --filter name=basic-mautic_worker-1 | grep -q .; do
            echo "### Waiting for basic-mautic_worker-1 to stop..."
            sleep 2
        done
    else
        echo "Container basic-mautic_worker-1 does not exist or is not running."
    fi
    echo "## Installing Mautic..."
    docker compose exec -T -u www-data -w /var/www/html mautic_web \
        php ./bin/console mautic:install --force \
        --admin_email {{EMAIL_ADDRESS}} \
        --admin_password {{MAUTIC_PASSWORD}} \
        https://{{DOMAIN_NAME}}
fi

echo "## Starting all the containers"
docker compose up -d

DOMAIN="{{DOMAIN_NAME}}"
if [[ "$DOMAIN" == *"DOMAIN_NAME"* ]]; then
    echo "The DOMAIN variable is not set yet."
    exit 0
fi

echo "## Check if Mautic is installed"
if docker compose exec -T mautic_web test -f /var/www/html/config/local.php && \
   docker compose exec -T mautic_web grep -q "site_url" /var/www/html/config/local.php; then
    echo "## Mautic is installed already."
    
    # Replace the site_url value with the domain
    echo "## Updating site_url in Mautic configuration..."
    docker compose exec -T mautic_web sed -i "s|'site_url' => '.*',|'site_url' => 'https://$DOMAIN',|g" /var/www/html/config/local.php

    # Auto-detect Traefik network and subnet
    echo "## Detecting Traefik network..."
    TRAEFIK_CONTAINER=$(docker ps --filter "name=traefik" --format "{{.Names}}" | head -n1)

    if [[ -z "$TRAEFIK_CONTAINER" ]]; then
        echo "ERROR: Could not find a running Traefik container. Falling back to 10.0.1.0/24."
        TRAEFIK_SUBNET="10.0.1.0/24"
    else
        TRAEFIK_NETWORK=$(docker inspect "$TRAEFIK_CONTAINER" \
            --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -n1)
        TRAEFIK_SUBNET=$(docker network inspect "$TRAEFIK_NETWORK" -f '{{(index .IPAM.Config 0).Subnet}}')
        echo "## Detected Traefik container: $TRAEFIK_CONTAINER"
        echo "## Detected Traefik network: $TRAEFIK_NETWORK"
        echo "## Detected Traefik subnet: $TRAEFIK_SUBNET"
    fi

    # Add trusted proxies configuration
    echo "## Adding trusted proxies configuration..."
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

    # Clear Symfony cache
    echo "## Clearing Symfony cache..."
    docker compose exec -T mautic_web php bin/console cache:clear
fi

echo "## Script execution completed"
