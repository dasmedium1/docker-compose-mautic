# Mautic Deployment Requirements Checklist

## Phase 1: Docker Compose Configuration
- [x] Remove port mapping from mautic_web
- [x] Add Traefik labels to mautic_web service  
- [x] Connect to external traefik_web network
- [x] Update db network to use mysql-private
- [x] Remove default network configuration

## Phase 2: Setup Script Simplification
- [x] Remove all Nginx/Certbot related code
- [x] Update DNS/IP checks to use Linode IP
- [x] Change Mautic install URL to use HTTPS domain
- [x] Remove volume symlink creation
- [x] Simplify to just Docker operations

## Phase 3: GitHub Actions Workflow
- [x] Remove all DigitalOcean specific steps
- [x] Simplify to require only:
  - SSH_PRIVATE_KEY
  - MAUTIC_PASSWORD  
  - LINODE_IP
- [x] Remove VPS provisioning steps
- [x] Keep Docker deployment logic
- [x] Simplify domain verification

## Phase 4: Documentation Updates
- [ ] Update README.md:
  - [ ] Change DigitalOcean references to Linode
  - [ ] Remove VPS creation instructions
  - [ ] Add Traefik prerequisites section
  - [ ] Update monitoring/debugging instructions
  - [ ] Update architecture diagram description

## Cleanup Tasks
- [ ] Remove nginx-virtual-host-template
- [ ] Remove setup-vps.sh

## Future Enhancements
- [ ] Redis for caching/sessions
- [ ] Load balancer setup
- [ ] MySQL read replica
- [ ] Multiple Mautic instances support
