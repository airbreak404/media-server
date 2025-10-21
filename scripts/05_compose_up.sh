#!/usr/bin/env bash
set -Eeuo pipefail

# Bring up Docker Compose stack for media server
# Creates necessary directories and starts all services

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging helpers
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Error handler
trap 'log_error "Script failed at line $LINENO"' ERR

# Flags
DRY_RUN=false
VERBOSE=false
PULL=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --no-pull) PULL=false; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --no-pull    Skip pulling latest images"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Check for .env file
if [[ ! -f .env ]]; then
    log_error ".env file not found. Copy .env.sample to .env and configure."
    exit 1
fi

# Load environment
source .env

log_info "=== Media Server Compose Stack ==="
log_info ""

# Check if Docker is available
if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed. Run ./scripts/02_install_docker.sh first."
    exit 1
fi

# Check if compose file exists
COMPOSE_FILE="compose/docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_error "Compose file not found: $COMPOSE_FILE"
    exit 1
fi

log_info "[1/5] Verifying mount points..."
REQUIRED_MOUNTS=("${MOVIES_MOUNT}" "${TV_MOUNT}")
for mount_point in "${REQUIRED_MOUNTS[@]}"; do
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_info "✓ Mounted: $mount_point"
    else
        log_error "Mount point not available: $mount_point"
        log_error "Run ./scripts/01_format_and_mount_drives.sh first"
        exit 1
    fi
done

if [[ ! -d "${DOWNLOADS_DIR}" ]]; then
    log_error "Downloads directory not found: ${DOWNLOADS_DIR}"
    exit 1
fi
log_info "✓ Downloads directory: ${DOWNLOADS_DIR}"

log_info "[2/5] Creating config directories..."
CONFIG_DIRS=(
    "config/jellyfin"
    "config/jellyseerr"
    "config/sonarr"
    "config/radarr"
    "config/prowlarr"
    "config/rdtclient/db"
)

for dir in "${CONFIG_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            mkdir -p "$dir"
            # Set ownership to PUID:PGID
            chown -R "${PUID}:${PGID}" "$dir"
            log_info "✓ Created: $dir"
        else
            log_info "[DRY RUN] Would create: $dir"
        fi
    else
        log_info "✓ Exists: $dir"
    fi
done

log_info "[3/5] Verifying Cloudflare Tunnel configuration..."
CLOUDFLARED_DIR="${HOME}/cloudflared"
if [[ ! -d "$CLOUDFLARED_DIR" ]] || ! ls "$CLOUDFLARED_DIR"/*.json &>/dev/null; then
    log_warn "Cloudflare Tunnel not configured. Run ./scripts/03_cloudflared_login_and_tunnel.sh"
    log_warn "Continuing without cloudflared..."
else
    log_info "✓ Cloudflare Tunnel configured"
    if [[ -f "$CLOUDFLARED_DIR/config.yml" ]]; then
        log_info "✓ Tunnel config found"
    else
        log_warn "Tunnel config missing, may need to rerun 03_cloudflared_login_and_tunnel.sh"
    fi
fi

if [[ "$PULL" == "true" ]]; then
    log_info "[4/5] Pulling latest images..."
    if [[ "$DRY_RUN" == "false" ]]; then
        docker compose -f "$COMPOSE_FILE" pull
        log_info "✓ Images pulled"
    else
        log_info "[DRY RUN] Would pull images"
    fi
else
    log_info "[4/5] Skipping image pull (--no-pull specified)"
fi

log_info "[5/5] Starting services..."
if [[ "$DRY_RUN" == "false" ]]; then
    docker compose -f "$COMPOSE_FILE" up -d

    log_info "✓ Services started"
    log_info ""

    # Wait a moment for containers to initialize
    log_info "Waiting for containers to initialize..."
    sleep 5

    # Show status
    log_info ""
    log_info "=== Container Status ==="
    docker compose -f "$COMPOSE_FILE" ps

    log_info ""
    log_info "=== Service URLs ==="
    log_info ""

    if [[ -n "${CF_TUNNEL_ID:-}" ]] && [[ "${CF_TUNNEL_ID}" != *"REPLACE"* ]]; then
        log_info "Public URLs (via Cloudflare Tunnel):"
        log_info "  Jellyfin:   https://${JELLYFIN_HOST}"
        log_info "  Jellyseerr: https://${JELLYSEERR_HOST}"
        log_info "  Sonarr:     https://${SONARR_HOST}"
        log_info "  Radarr:     https://${RADARR_HOST}"
        log_info "  Prowlarr:   https://${PROWLARR_HOST}"
        log_info "  RdtClient:  https://${RDT_HOST}"
    else
        log_warn "Cloudflare Tunnel not configured - services not publicly accessible"
    fi

    log_info ""
    log_info "Local URLs (LAN access):"
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    log_info "  Jellyfin:   http://${LOCAL_IP}:8096"
    log_info "  Jellyseerr: http://${LOCAL_IP}:5055"
    log_info "  RdtClient:  http://${LOCAL_IP}:6500"
    log_info ""
    log_info "Note: Sonarr, Radarr, and Prowlarr are only accessible via Cloudflare Tunnel"
    log_info "      (no local ports exposed for security)"

else
    log_info "[DRY RUN] Would start services with: docker compose -f $COMPOSE_FILE up -d"
fi

log_info ""
log_info "✓ Compose stack deployment complete!"
log_info ""
log_info "Next steps:"
log_info "  1. Run health checks: ./scripts/07_health_checks.sh"
log_info "  2. Configure applications: ./scripts/06_configure_apps_via_api.py"
log_info "  3. Access services via the URLs above"
log_info ""
log_info "Useful commands:"
log_info "  View logs:     docker compose -f $COMPOSE_FILE logs -f [service]"
log_info "  Restart:       docker compose -f $COMPOSE_FILE restart [service]"
log_info "  Stop all:      docker compose -f $COMPOSE_FILE down"
log_info "  Update images: docker compose -f $COMPOSE_FILE pull && docker compose -f $COMPOSE_FILE up -d"
