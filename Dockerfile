# Define the Mautic version as an argument
ARG MAUTIC_VERSION=5.2.3-apache

# Build stage:
FROM mautic/mautic:${MAUTIC_VERSION} AS build

# Install dependencies needed for Composer to run and rebuild assets:
RUN apt-get update && apt-get install -y git curl npm && rm -rf /var/lib/apt/lists/*

# Install Composer globally:
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install any Mautic theme or plugin using Composer:
RUN cd /var/www/html && \
    COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_PROCESS_TIMEOUT=10000  vendor/bin/composer require chimpino/theme-air:^1.0 --no-scripts --no-interaction

# # --- PATCH: Configure trusted proxies and headers ---
# # Create a file that defines trusted proxies and headers for Symfony/Mautic
# RUN echo "<?php \
# \$parameters['trusted_proxies'] = ['10.0.1.0/24']; \
# \$parameters['trusted_headers'] = ['x-forwarded-for', 'x-forwarded-proto', 'x-forwarded-port', 'x-forwarded-host']; \
# " > /var/www/html/config/trusted_proxies.php && \
#     chown www-data:www-data /var/www/html/config/trusted_proxies.php

# # Ensure local.php includes our trusted_proxies.php file before returning $parameters
# RUN sed -i "/return \$parameters;/i if (file_exists(__DIR__ . '/trusted_proxies.php')) { include __DIR__ . '/trusted_proxies.php'; }" \
#     /var/www/html/config/local.php 

# Production stage:
FROM mautic/mautic:${MAUTIC_VERSION}

# Copy the built assets and the Mautic installation from the build stage:
COPY --from=build --chown=www-data:www-data /var/www/html /var/www/html
