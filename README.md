# Mautic Deployment with Docker Compose and Traefik

This repository provides automated deployment and management of Mautic (Marketing Automation Platform) using Docker Compose, with Traefik as a reverse proxy for SSL termination and routing.

## Overview

This setup is inspired by the original work of John Linhart (escopecz) who created a comprehensive Mautic deployment system for DigitalOcean droplets. This repository adapts and extends that work with a focus on:
- Using Traefik instead of Nginx for SSL and reverse proxy
- Simplified deployment to existing infrastructure (Linode VPS)
- Automated backup and restore workflows
- GitHub Actions for CI/CD automation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Actions                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  • Backup Workflow (scheduled)                      │    │
│  │  • Deploy Workflow (on push/manual)                 │    │
│  │  • Restore Workflow (manual)                        │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────────────┬──────────────────────────────┘
                               │ SSH
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     Linode VPS                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                    Traefik                           │    │
│  │  • SSL termination (Let's Encrypt)                  │    │
│  │  • Reverse proxy                                    │    │
│  └─────────────────────────────────────────────────────┘    │
│                              │                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Docker Compose Stack                   │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌───────┐  │    │
│  │  │ Mautic  │  │ Mautic  │  │ Mautic  │  │ MySQL │  │    │
│  │  │  Web    │  │  Cron   │  │ Worker  │  │  8.0  │  │    │
│  │  └─────────┘  └─────────┘  └─────────┘  └───────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Infrastructure Requirements
1. **Linode VPS** (or any Linux server with Docker installed)
2. **Traefik** already running on the VPS with:
   - `traefik_web` network created
   - Let's Encrypt certificate resolver configured
3. **Domain name** pointing to your VPS IP address

### GitHub Repository Configuration

#### Secrets (required):
- `SSH_PRIVATE_KEY`: Private SSH key for accessing the VPS
- `MAUTIC_PASSWORD`: Admin password for Mautic installation
- `MYSQL_PASSWORD`: Password for Mautic database user
- `MYSQL_ROOT_PASSWORD`: Root password for MySQL

#### Variables (required):
- `LINODE_IP`: IP address of your Linode VPS
- `DOMAIN`: Domain name for your Mautic instance (e.g., `mautic.example.com`)
- `EMAIL`: Email address for Mautic admin user and SSL certificates
- `DB_NAME`: Mautic database name (e.g., `mautic`)
- `MYSQL_USER`: Mautic database user
- `COMPOSE_PROJECT_NAME`: Unique Compose project name for this site (e.g., `sitea`)
- `DEPLOY_DIR`: Absolute deploy directory on the VPS (e.g., `/home/angelantonio/backup/root/sitea`)

#### Optional Variables:
- `ENABLE_BACKUP`: Set to `false` to skip backup before deployment (default: enabled)
- `MAUTIC_VERSION`: Mautic version (default: `6.0.5-apache`)

> **One repo = one website.** To deploy a second site onto the same VPS, fork this repo and set a different `COMPOSE_PROJECT_NAME` and `DEPLOY_DIR`. Secrets and variables live at the **repository** level (no GitHub environments).

## Quick Start

1. **Clone and configure the repository:**
   ```bash
   git clone <your-repo-url>
   cd mautic-docker-traefik
   ```

2. **Configure GitHub Secrets and Variables:**
   - Go to your repository Settings → Secrets and variables → Actions
   - Add all required secrets and variables listed above

3. **Run the deployment workflow:**
   - Go to Actions → Deploy Mautic App
   - Click "Run workflow"
   - The workflow will:
     - Backup existing Mautic (if any)
     - Deploy the Docker Compose stack
     - Install/configure Mautic
     - Configure Traefik routing

## Workflows

### 1. Deploy Workflow (`deploy.yml`)
- **Trigger:** Push to `master` branch or manual dispatch
- **Actions:**
  - Backup existing installation (optional)
  - Deploy Docker Compose stack
  - Install/configure Mautic
  - Set up Traefik routing with SSL
  - Configure trusted proxies for Traefik network

### 2. Backup Workflow (`backup.yml`)
- **Trigger:** Manual dispatch
- **Actions:**
  - Create filesystem backup (tar.gz of Mautic files)
  - Create database backup (MySQL dump)
  - Apply retention policy (keeps last 14 backups)
  - Store backups in `$DEPLOY_DIR/backups/`

### 3. Restore Workflow (`restore.yml`)
- **Trigger:** Manual dispatch
- **Actions:**
  - Restore filesystem from backup (`$DEPLOY_DIR/backups/current/filesystem.tar.gz`)
  - Restore database from dump (`$DEPLOY_DIR/backups/current/database.sql.gz`)
  - Restart services

## File Structure

```
├── docker-compose.yml          # Docker Compose configuration
├── setup-dc.sh                 # Setup script for initial deployment
├── .env                        # Environment variables template
├── .mautic_env                 # Mautic-specific environment variables
├── scripts/
│   ├── backup_mautic.sh        # Backup script
│   ├── restore_mautic.sh       # Restore script
│   └── rotate_*_password.sh    # Password rotation scripts
├── .github/workflows/
│   ├── deploy.yml              # Deployment workflow
│   ├── backup.yml              # Backup workflow
│   ├── restore.yml             # Restore workflow
│   ├── rotate-secrets.yml      # Secret rotation workflow
│   └── ci.yml                  # Lint/syntax checks (shellcheck + compose config)
└── .github/actions/
    └── run-remote-script       # Composite action (SCP + SSH run)
```

## Key Features

### Traefik Integration
- Automatic SSL certificates via Let's Encrypt
- HTTP to HTTPS redirect
- Custom headers for proper proxy handling
- Network isolation with `traefik_web` and `mysql_private` networks

### Automated Backups
- Filesystem and database backups
- Retention policy (14 backups)
- Consistent naming with date prefixes
- Safe backup validation before proceeding

### Disaster Recovery
- One-command restore from any backup
- Database drop/recreate with proper privileges
- Permission fixing for restored files
- Cache clearing and service validation

### Security
- MySQL with separate user accounts
- File permissions following Mautic best practices
- Trusted proxy configuration for Traefik
- Environment variables for sensitive data

## Maintenance

### Accessing Containers
```bash
# SSH into your VPS
ssh root@your-vps-ip

# Navigate to the deploy directory
cd /path/to/your/deploy-dir

# View running containers
docker compose ps

# View logs
docker compose logs mautic_web
docker compose logs mautic_db

# Execute commands in containers
docker compose exec -u www-data mautic_web php bin/console cache:clear
```

### Manual Backup
```bash
cd /path/to/your/deploy-dir
COMPOSE_PROJECT_NAME=sitea DEPLOY_DIR=/path/to/your/deploy-dir DB_NAME=your_db_name MYSQL_ROOT_PASSWORD=your_password bash scripts/backup_mautic.sh
```

### Manual Restore
```bash
cd /path/to/your/deploy-dir
COMPOSE_PROJECT_NAME=sitea DEPLOY_DIR=/path/to/your/deploy-dir DB_NAME=your_db_name MYSQL_ROOT_PASSWORD=your_password bash scripts/restore_mautic.sh
```

Restore reads from `$DEPLOY_DIR/backups/current/` only (no date/prefix argument).

## Troubleshooting

### Common Issues

1. **Traefik network not found:**
   ```bash
   docker network create -d overlay --attachable traefik_web
   ```

2. **Permission errors after restore:**
   ```bash
   chown -R 33:33 /home/angelantonio/backup/root/mautic/mautic
   ```

3. **Database connection issues:**
   - Check if MySQL container is running: `docker compose ps mautic_db`
   - Verify credentials in `.env` file

4. **Traefik not routing to Mautic:**
   - Check Traefik logs: `docker logs traefik_container_name`
   - Verify domain DNS points to VPS IP
   - Check Traefik labels in `docker-compose.yml`

### Monitoring
```bash
# Check resource usage
docker compose stats

# Check service health
docker compose ps

# View application logs
tail -f /home/angelantonio/backup/root/mautic/mautic/logs/*.log
```

## Differences from Original escopecz Repository

This repository differs from the original DigitalOcean-focused setup by:

1. **Traefik instead of Nginx:** Uses Traefik for SSL and reverse proxy
2. **No VPS provisioning:** Assumes existing infrastructure
3. **Simplified setup:** Removed DigitalOcean API dependencies
4. **Backup/restore focus:** Added comprehensive backup and restore workflows
5. **Network isolation:** Uses separate networks for web and database traffic
6. **GitHub Actions only:** All automation through GitHub workflows

## Future Enhancements

- [ ] Redis integration for caching and sessions
- [x] Multiple Mautic instances support (via per-site repo forks on one VPS)
- [ ] Database read replicas
- [ ] Enhanced monitoring with Prometheus/Grafana
- [ ] Automated testing before deployment
- [ ] Blue/green deployment strategy

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by the original work of John Linhart (escopecz)
- Based on the official Mautic Docker images: https://github.com/mautic/docker-mautic
- Uses Traefik for reverse proxy and SSL management
````
