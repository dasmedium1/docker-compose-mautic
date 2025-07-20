#!/bin/bash
set -e

# Get the traefik_web network subnet
SUBNET=$(docker network inspect traefik_web -f '{{ (index .IPAM.Config 0).Subnet }}')

echo "Applying trusted proxies: $SUBNET"

# Create trusted_proxies.php configuration
cat <<EOF > /var/www/html/config/trusted_proxies.php
<?php
\$parameters['trusted_proxies'] = ['$SUBNET'];
\$parameters['trusted_headers'] = [
    'x-forwarded-for',
    'x-forwarded-proto',
    'x-forwarded-port',
    'x-forwarded-host'
];
EOF

# Ensure proper ownership
chown www-data:www-data /var/www/html/config/trusted_proxies.php

# Include in local.php if not already present
if ! grep -q "trusted_proxies.php" /var/www/html/config/local.php; then
    sed -i "/return \$parameters;/i if (file_exists(__DIR__ . '/trusted_proxies.php')) { include __DIR__ . '/trusted_proxies.php'; }" /var/www/html/config/local.php
fi

# Continue to original entrypoint
exec /entrypoint.sh "$@"
