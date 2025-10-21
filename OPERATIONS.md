# Media Server Operations Guide

Comprehensive guide for operating and maintaining your automated Jellyfin media server.

## Table of Contents

- [Initial Setup](#initial-setup)
- [Daily Operations](#daily-operations)
- [Configuration](#configuration)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Backup and Restore](#backup-and-restore)
- [Updates](#updates)
- [Security](#security)

---

## Initial Setup

### Prerequisites

- Raspberry Pi 5 (16 GB RAM recommended)
- Raspberry Pi OS Lite 64-bit installed
- 256 GB USB SSD for OS (boot drive)
- Two 8 TB USB HDDs for media storage
- Internet connection
- Cloudflare account with domain

### Quick Start (First Time Setup)

1. **Clone/extract this repository:**
   ```bash
   cd /home/pi
   # Extract the media-server bundle here
   cd media-server
   ```

2. **Configure environment:**
   ```bash
   cp .env.sample .env
   nano .env  # Edit with your settings
   ```

3. **Run bootstrap (interactive):**
   ```bash
   make bootstrap
   ```
   This will:
   - Run preflight checks
   - Format and mount drives (⚠ DESTRUCTIVE)
   - Install Docker
   - Install Tailscale for SSH access (optional, controlled by `.env`)
   - Configure Cloudflare Tunnel
   - Start all services
   - Run health checks

4. **Add DNS records** in Cloudflare dashboard (see `scripts/04_generate_dns_records.md`)

5. **Complete initial configuration:**
   - Access Jellyfin at `https://tv.yourdomain.org`
   - Set admin passwords in all *Arr apps
   - Run API configuration: `python3 scripts/06_configure_apps_via_api.py`

### Manual Step-by-Step Setup

If you prefer manual control:

```bash
# 1. Preflight checks
sudo bash scripts/00_preflight.sh

# 2. Format and mount drives (⚠ DESTRUCTIVE)
sudo bash scripts/01_format_and_mount_drives.sh --format

# 3. Install Docker
sudo bash scripts/02_install_docker.sh

# 3b. Install Tailscale (optional, for SSH access)
sudo bash scripts/02b_install_tailscale.sh

# 4. Configure Cloudflare Tunnel
bash scripts/03_cloudflared_login_and_tunnel.sh

# 5. Add DNS records (see scripts/04_generate_dns_records.md)

# 6. Start services
bash scripts/05_compose_up.sh

# 7. Verify deployment
bash scripts/07_health_checks.sh
```

---

## Daily Operations

### Using Make Commands

```bash
# Start all services
make up

# Stop all services
make down

# Restart all services
make restart

# Restart specific service
make restart SVC=jellyfin

# View logs (all services)
make logs

# View logs (specific service)
make logs SVC=sonarr

# Check status
make status

# Run health checks
make health

# Quick verification
make verify
```

### Using Docker Compose Directly

```bash
# Navigate to project directory
cd /home/pi/media-server

# Start services
docker compose -f compose/docker-compose.yml up -d

# Stop services
docker compose -f compose/docker-compose.yml down

# View logs
docker compose -f compose/docker-compose.yml logs -f [service]

# Restart a service
docker compose -f compose/docker-compose.yml restart [service]

# Pull latest images
docker compose -f compose/docker-compose.yml pull
```

### Service URLs

**Public Access (via Cloudflare Tunnel):**
- Jellyfin: `https://tv.yourdomain.org`
- Jellyseerr: `https://requests.yourdomain.org`
- Sonarr: `https://sonarr.yourdomain.org`
- Radarr: `https://radarr.yourdomain.org`
- Prowlarr: `https://prowlarr.yourdomain.org`
- RdtClient: `https://rdt.yourdomain.org`

**Local Access (LAN only):**
- Jellyfin: `http://[PI_IP]:8096`
- Jellyseerr: `http://[PI_IP]:5055`
- RdtClient: `http://[PI_IP]:6500`

**Tailscale Access (if installed):**
- SSH: `ssh pi@[TAILSCALE_IP]` or `ssh pi@[HOSTNAME]`
- Services: `http://[TAILSCALE_IP]:8096` (works but redundant, use Cloudflare instead)
- Note: Use `tailscale ip -4` to get your Tailscale IP

---

## Configuration

### Post-Deployment Configuration

#### 1. Jellyfin Setup

1. Access Jellyfin at `https://tv.yourdomain.org`
2. Complete initial wizard:
   - Create admin account
   - Add media libraries:
     - Movies: `/media/movies`
     - TV Shows: `/media/tv`
   - Enable hardware acceleration (VAAPI)
3. Configure users and permissions

#### 2. Sonarr Configuration

1. Access Sonarr at `https://sonarr.yourdomain.org`
2. Set admin password: Settings → General → Security
3. Get API key: Settings → General → Security → API Key
4. Add to `.env` as `SONARR_API_KEY`
5. Run API configuration script (or manual setup):
   ```bash
   python3 scripts/06_configure_apps_via_api.py --app sonarr
   ```
6. Manual configuration (if not using script):
   - Add download client: Settings → Download Clients → Add → qBittorrent
     - Host: `rdtclient`
     - Port: `6500`
     - Category: `sonarr`
   - Add root folder: `/tv`
   - Add remote path mapping:
     - Host: `rdtclient`
     - Remote Path: `/data/downloads`
     - Local Path: `/data/downloads`

#### 3. Radarr Configuration

Same as Sonarr, but:
- Category: `radarr`
- Root folder: `/movies`
- API key: `RADARR_API_KEY`

#### 4. Prowlarr Configuration

1. Access Prowlarr at `https://prowlarr.yourdomain.org`
2. Set admin password
3. Get API key
4. Add indexers: Indexers → Add Indexer
5. Sync to apps: Settings → Apps → Add Application
   - Add Sonarr:
     - Sync Level: Full Sync
     - Prowlarr Server: `http://prowlarr:9696`
     - Sonarr Server: `http://sonarr:8989`
     - API Key: (from Sonarr)
   - Add Radarr (same process)

#### 5. Jellyseerr Configuration

1. Access Jellyseerr at `https://requests.yourdomain.org`
2. Sign in with Jellyfin account
3. Connect to services:
   - Jellyfin: `http://jellyfin:8096`
   - Sonarr: `http://sonarr:8989`
   - Radarr: `http://radarr:7878`

#### 6. RdtClient Configuration

1. Access RdtClient at `https://rdt.yourdomain.org`
2. Add Real-Debrid API key
3. Configure download settings:
   - Download path: `/data/downloads`
   - Categories: `sonarr`, `radarr`

---

## Monitoring

### Health Checks

```bash
# Comprehensive health check
make health

# Quick verification
make verify

# Check mounts only
bash verify/check_mounts.sh

# Check containers only
bash verify/check_containers.sh

# Check HTTP endpoints
bash verify/curl_checks.sh
```

### Container Logs

```bash
# All logs
docker compose -f compose/docker-compose.yml logs -f

# Specific service
docker compose -f compose/docker-compose.yml logs -f jellyfin

# Last 100 lines
docker compose -f compose/docker-compose.yml logs --tail=100 sonarr

# Since 1 hour ago
docker compose -f compose/docker-compose.yml logs --since=1h
```

### System Resources

```bash
# Disk usage
df -h /mnt/movies /mnt/tv

# Container resource usage
docker stats

# System memory
free -h

# System temperature (Raspberry Pi)
vcgencmd measure_temp
```

---

## Troubleshooting

### Common Issues

#### Services Not Starting

**Symptom:** Container exits immediately or won't start

**Solutions:**
1. Check logs:
   ```bash
   docker logs [container-name]
   ```
2. Verify mounts are available:
   ```bash
   bash verify/check_mounts.sh
   ```
3. Check permissions:
   ```bash
   ls -la /mnt/movies /mnt/tv
   ```
4. Restart service:
   ```bash
   make restart SVC=[service-name]
   ```

#### Cloudflare Tunnel Not Working

**Symptom:** Services not accessible via public URLs

**Solutions:**
1. Check tunnel status:
   ```bash
   docker logs cloudflared
   ```
2. Verify DNS records in Cloudflare dashboard
3. Ensure tunnel ID matches in `.env` and `~/cloudflared/config.yml`
4. Restart tunnel:
   ```bash
   make restart SVC=cloudflared
   ```

#### Download Client Connection Failed

**Symptom:** Sonarr/Radarr can't connect to RdtClient

**Solutions:**
1. Verify RdtClient is running:
   ```bash
   curl http://localhost:6500
   ```
2. Check network connectivity:
   ```bash
   docker network inspect media-net
   ```
3. Verify download client configuration in *Arr apps
4. Check RdtClient API key is configured

#### Jellyfin Transcoding Issues

**Symptom:** Video playback stutters or fails

**Solutions:**
1. Check hardware acceleration is enabled
2. Verify `/dev/dri` is mounted:
   ```bash
   docker exec jellyfin ls -la /dev/dri
   ```
3. Check Jellyfin logs for transcoding errors
4. Reduce video quality in client

#### Disk Full

**Symptom:** Services fail, downloads stop

**Solutions:**
1. Check disk usage:
   ```bash
   df -h /mnt/movies /mnt/tv
   ```
2. Clean up completed downloads in RdtClient
3. Remove old media files
4. Check Jellyfin cache: `config/jellyfin/cache`

### Emergency Recovery

#### Restart All Services

```bash
make down
sleep 5
make up
make health
```

#### Restore from Backup

```bash
# Stop services
make down

# Extract backup
tar -xzf backups/media-server-backup-YYYYMMDD_HHMMSS.tar.gz

# Restore cloudflared credentials
cp -r cloudflared-credentials/* ~/cloudflared/

# Start services
make up
```

#### Rollback After Bad Update

```bash
# Stop services
make down

# Use specific image version
# Edit compose/docker-compose.yml and pin versions:
# image: lscr.io/linuxserver/jellyfin:10.8.13

# Start with old images
make up
```

---

## Backup and Restore

### Creating Backups

```bash
# Standard backup
make backup

# Manual backup with custom location
bash scripts/90_backup.sh --backup-dir /path/to/backups
```

**Backup includes:**
- `.env` configuration
- `compose/docker-compose.yml`
- `config/` directories (all app configs)
- Cloudflare Tunnel credentials
- Backup metadata

**Backup excludes:**
- Media files (too large, backup separately)
- Docker images
- Temporary files

### Restore Procedure

1. **Stop services:**
   ```bash
   make down
   ```

2. **Extract backup:**
   ```bash
   tar -xzf backups/media-server-backup-YYYYMMDD_HHMMSS.tar.gz
   ```

3. **Restore files:**
   ```bash
   # Restore cloudflared credentials
   cp -r cloudflared-credentials/* ~/cloudflared/

   # Config and .env are already restored by extraction
   ```

4. **Start services:**
   ```bash
   make up
   ```

5. **Verify:**
   ```bash
   make health
   ```

### Backup Schedule

**Recommended:**
- Configuration backups: Daily (automated via cron)
- Media files: Weekly (external backup solution)

**Setup automatic backups:**
```bash
# Add to crontab
crontab -e

# Add line (daily at 3 AM):
0 3 * * * cd /home/pi/media-server && bash scripts/90_backup.sh
```

---

## Updates

### Update Docker Images

```bash
# Using Make
make update

# Manual
docker compose -f compose/docker-compose.yml pull
docker compose -f compose/docker-compose.yml up -d
```

### Update Individual Service

```bash
# Pull specific image
docker compose -f compose/docker-compose.yml pull jellyfin

# Restart service
make restart SVC=jellyfin
```

### Disable Watchtower Auto-Updates

If you prefer manual updates:

1. Edit `compose/docker-compose.yml`
2. Comment out or remove the `watchtower` service
3. Restart: `make down && make up`

### OS Updates

```bash
# Update Raspberry Pi OS
sudo apt update
sudo apt upgrade -y

# Reboot if kernel updated
sudo reboot
```

---

## Security

### Best Practices

1. **Secure Admin Interfaces:**
   - Set strong passwords in all *Arr apps
   - Consider enabling Cloudflare Access for admin subdomains
   - Keep Jellyfin and Jellyseerr open for users, protect others

2. **API Keys:**
   - Never commit `.env` to version control
   - Rotate API keys periodically
   - Use different keys for each service

3. **Network Security:**
   - Cloudflare Tunnel eliminates port forwarding
   - No direct exposure of Raspberry Pi to internet
   - All traffic encrypted via Cloudflare

4. **System Security:**
   ```bash
   # Enable firewall
   sudo apt install ufw
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow ssh
   sudo ufw enable

   # Keep system updated
   sudo apt update && sudo apt upgrade -y
   ```

5. **Docker Security:**
   - Services run as non-root (PUID/PGID 1000)
   - Limited container capabilities
   - Isolated network (media-net)

6. **Tailscale SSH Access (Optional):**
   - Provides secure SSH access from anywhere
   - No port forwarding required
   - End-to-end encrypted
   - See `docs/TAILSCALE_SETUP.md` for detailed setup

### Tailscale Integration

If you enabled Tailscale during bootstrap (or install separately with `make install-tailscale`):

**Access SSH from anywhere:**
```bash
# Find your Tailscale IP
tailscale ip -4

# SSH via Tailscale
ssh pi@100.x.x.x
```

**Important Notes:**
- Tailscale is configured with `--accept-dns=false` to avoid conflicts
- Services remain accessible via Cloudflare Tunnel (no change)
- Use Tailscale for SSH/admin access, Cloudflare for public services
- See `docs/TAILSCALE_SETUP.md` for troubleshooting

**Quick Install (if skipped during bootstrap):**
```bash
make install-tailscale
```

### Enabling Cloudflare Access

For admin interfaces (optional but recommended):

1. Go to Cloudflare Zero Trust dashboard
2. Create Access application for each subdomain:
   - sonarr.yourdomain.org
   - radarr.yourdomain.org
   - prowlarr.yourdomain.org
3. Set access policies (email authentication, etc.)
4. Leave Jellyfin and Jellyseerr open for users

### Monitoring Access

Check Cloudflare analytics for:
- Request patterns
- Geographic distribution
- Threat detection
- Performance metrics

---

## Maintenance Checklist

### Daily
- [ ] Check service status: `make status`
- [ ] Review critical errors in logs

### Weekly
- [ ] Run health checks: `make health`
- [ ] Check disk usage
- [ ] Review Watchtower update logs
- [ ] Verify backups are completing

### Monthly
- [ ] Update OS: `sudo apt update && sudo apt upgrade`
- [ ] Review and clean old backups
- [ ] Check for security updates
- [ ] Verify all services are optimized
- [ ] Test restore procedure (quarterly)

### Quarterly
- [ ] Review and update configurations
- [ ] Check for new service versions
- [ ] Review Cloudflare security settings
- [ ] Audit user access

---

## Quick Reference

### One-Line Commands

```bash
# Full bootstrap (first time)
make bootstrap

# Start everything
make up

# Stop everything
make down

# Check if healthy
make health

# View all logs
make logs

# Backup configs
make backup

# Update all images
make update
```

### Important Paths

- Project root: `/home/pi/media-server/`
- Media: `/mnt/movies`, `/mnt/tv`
- Downloads: `/mnt/movies/downloads`
- Configs: `./config/[service]`
- Cloudflared: `~/cloudflared/`
- Backups: `./backups/`

### Support

For issues:
1. Check logs: `make logs SVC=[service]`
2. Run health check: `make health`
3. Review this operations guide
4. Check service-specific documentation

---

**System designed for:** Raspberry Pi 5 with Raspberry Pi OS Lite 64-bit
**Last updated:** 2025-10-20
**Version:** 1.0
