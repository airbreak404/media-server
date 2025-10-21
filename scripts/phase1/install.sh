#!/usr/bin/env bash
set -Eeuo pipefail

# Phase 1 Installation: Foundation Services
# Adds: Bazarr, Caddy (HTTPS), Homer (dashboard), Performance optimization

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Error handler
trap 'log_error "Phase 1 installation failed at line $LINENO. Run: make rollback-phase-1"' ERR

# Flags
DRY_RUN=false
SKIP_OPTIMIZATION=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --skip-optimization) SKIP_OPTIMIZATION=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Install Phase 1: Foundation Services"
            echo ""
            echo "Options:"
            echo "  --dry-run             Show what would be done"
            echo "  --skip-optimization   Skip performance tuning"
            echo "  --help                Show this message"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Check prerequisites
if [[ ! -f .env ]]; then
    log_error ".env file not found. Run bootstrap first."
    exit 1
fi

# Load environment
source .env

log_info "=== Phase 1: Foundation Services Installation ==="
log_info ""
log_info "This will add:"
log_info "  • Bazarr (automatic subtitles)"
log_info "  • Caddy (HTTPS reverse proxy for LAN)"
log_info "  • Homer (beautiful dashboard)"
log_info "  • Performance optimizations"
log_info ""

if [[ "$DRY_RUN" == "false" ]]; then
    read -p "Continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
fi

# Step 1: Backup current state
log_step "[1/7] Creating backup..."
BACKUP_DIR="./backups/phase1-pre-install-$(date +%Y%m%d_%H%M%S)"
if [[ "$DRY_RUN" == "false" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -r config/ "$BACKUP_DIR/" 2>/dev/null || true
    cp compose/docker-compose.yml "$BACKUP_DIR/" 2>/dev/null || true
    cp .env "$BACKUP_DIR/" 2>/dev/null || true
    log_info "✓ Backup saved to $BACKUP_DIR"
else
    log_info "[DRY RUN] Would create backup"
fi

# Step 2: Create config directories
log_step "[2/7] Creating configuration directories..."
DIRS=(
    "config/bazarr"
    "config/caddy"
    "config/homer"
)

for dir in "${DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            mkdir -p "$dir"
            chown -R "${PUID}:${PGID}" "$dir" 2>/dev/null || true
            log_info "✓ Created $dir"
        else
            log_info "[DRY RUN] Would create $dir"
        fi
    else
        log_info "✓ $dir already exists"
    fi
done

# Step 3: Generate Caddyfile
log_step "[3/7] Generating Caddyfile..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Simple Caddyfile for LAN access with self-signed certs
    cat > config/caddy/Caddyfile <<EOF
# Caddy reverse proxy for media server LAN access
{
    auto_https disable_redirects
    admin off
}

# Jellyfin
:443 {
    tls internal
    reverse_proxy /jellyfin/* jellyfin:8096
    handle_path /jellyfin* {
        reverse_proxy jellyfin:8096
    }
}

# Individual service endpoints
http://pi.local:8443, https://pi.local:8443 {
    tls internal
    redir / /dashboard
    reverse_proxy /dashboard* homer:8080
}

http://jellyfin.local, https://jellyfin.local {
    tls internal
    reverse_proxy jellyfin:8096
}

http://requests.local, https://requests.local {
    tls internal
    reverse_proxy jellyseerr:5055
}

http://sonarr.local, https://sonarr.local {
    tls internal
    reverse_proxy sonarr:8989
}

http://radarr.local, https://radarr.local {
    tls internal
    reverse_proxy radarr:7878
}

http://prowlarr.local, https://prowlarr.local {
    tls internal
    reverse_proxy prowlarr:9696
}

http://bazarr.local, https://bazarr.local {
    tls internal
    reverse_proxy bazarr:6767
}

http://rdt.local, https://rdt.local {
    tls internal
    reverse_proxy rdtclient:6500
}
EOF
    log_info "✓ Caddyfile generated"
else
    log_info "[DRY RUN] Would generate Caddyfile"
fi

# Step 4: Generate Homer config
log_step "[4/7] Generating Homer dashboard config..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Use template and substitute variables
    cat > config/homer/config.yml <<EOF
title: "Media Server"
subtitle: "Raspberry Pi 5 - Automated Media Center"

header: true
footer: false
theme: auto

message:
  style: "is-info"
  title: "Welcome!"
  content: "Your media server is running. Access services below."

services:
  - name: "Media"
    icon: "fas fa-video"
    items:
      - name: "Jellyfin"
        subtitle: "Streaming"
        url: "https://tv.${CF_DOMAIN}"
        target: "_blank"
      - name: "Jellyseerr"
        subtitle: "Requests"
        url: "https://requests.${CF_DOMAIN}"
        target: "_blank"

  - name: "Management"
    icon: "fas fa-film"
    items:
      - name: "Sonarr"
        subtitle: "TV Shows"
        url: "https://sonarr.${CF_DOMAIN}"
        target: "_blank"
      - name: "Radarr"
        subtitle: "Movies"
        url: "https://radarr.${CF_DOMAIN}"
        target: "_blank"
      - name: "Prowlarr"
        subtitle: "Indexers"
        url: "https://prowlarr.${CF_DOMAIN}"
        target: "_blank"
      - name: "Bazarr"
        subtitle: "Subtitles"
        url: "http://\$(hostname -I | awk '{print \$1}'):6767"
        target: "_blank"
EOF
    log_info "✓ Homer config generated"
else
    log_info "[DRY RUN] Would generate Homer config"
fi

# Step 5: Start Phase 1 services
log_step "[5/7] Starting Phase 1 services..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Start services using both compose files
    docker compose -f compose/docker-compose.yml -f compose/docker-compose.phase1.yml up -d

    # Wait for services to start
    log_info "Waiting for services to initialize..."
    sleep 10

    log_info "✓ Services started"
else
    log_info "[DRY RUN] Would start: Bazarr, Caddy, Homer"
fi

# Step 6: Performance optimization
if [[ "$SKIP_OPTIMIZATION" == "false" ]]; then
    log_step "[6/7] Running performance optimization..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sudo bash scripts/phase1/optimize_performance.sh
    else
        log_info "[DRY RUN] Would run performance optimization"
    fi
else
    log_info "[6/7] Skipping performance optimization (--skip-optimization)"
fi

# Step 7: Verify installation
log_step "[7/7] Verifying installation..."
if [[ "$DRY_RUN" == "false" ]]; then
    bash scripts/phase1/verify.sh
else
    log_info "[DRY RUN] Would run verification"
fi

# Summary
log_info ""
log_info "=== Phase 1 Installation Complete! ==="
log_info ""
log_info "New Services:"
log_info "  ✓ Bazarr    - Automatic subtitles"
log_info "  ✓ Caddy     - HTTPS reverse proxy"
log_info "  ✓ Homer     - Dashboard"
log_info ""
log_info "Access URLs:"
LOCAL_IP=$(hostname -I | awk '{print $1}')
log_info "  Dashboard:  http://${LOCAL_IP}:8080"
log_info "  Bazarr:     http://${LOCAL_IP}:6767"
log_info "  Via Caddy:  https://pi.local:8443"
log_info ""
log_info "Next steps:"
log_info "  1. Configure Bazarr to connect to Sonarr/Radarr"
log_info "  2. Proceed to Phase 2: make phase-2"
log_info ""
log_info "To rollback: make rollback-phase-1"
