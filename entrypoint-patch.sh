#!/bin/bash
set -e

# Wait for local.php to be created by Mautic installation
while [ ! -f /var/www/html/config/local.php ]; do
    echo "Waiting for local.php to be created..."
    sleep 5
done

# Create trusted_proxies configuration
cat <<EOF > /var/www/html/config/trusted_proxies.php
<?php
\$parameters['trusted_proxies'] = ['10.0.1.0/24'];
\$parameters['trusted_headers'] = [
    'x-forwarded-for',
    'x-forwarded-proto',
    'x-forwarded-port',
    'x-forwarded-host'
];
EOF

# Ensure proper ownership
chown www-data:www-data /var/www/html/config/trusted_proxies.php

# Include in local.php
if ! grep -q "trusted_proxies.php" /var/www/html/config/local.php; then
    sed -i "/return \$parameters;/i if (file_exists(__DIR__ . '/trusted_proxies.php')) { include __DIR__ . '/trusted_proxies.php'; }" \
    /var/www/html/config/local.php
fi

# Continue to original entrypoint
exec /entrypoint.sh "$@"
