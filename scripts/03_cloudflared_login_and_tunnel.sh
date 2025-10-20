#!/usr/bin/env bash
set -Eeuo pipefail

# Configure Cloudflare Tunnel for media server
# Handles tunnel creation, credential storage, and config generation

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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Load environment
if [[ -f .env ]]; then
    source .env
else
    log_error ".env file not found. Copy .env.sample to .env and configure."
    exit 1
fi

# Configuration
CLOUDFLARED_DIR="${HOME}/cloudflared"
CF_TUNNEL_NAME="${CF_TUNNEL_NAME:-media-tunnel}"
CF_DOMAIN="${CF_DOMAIN:-tylerhoward.org}"

log_info "=== Cloudflare Tunnel Setup ==="
log_info "Tunnel name: $CF_TUNNEL_NAME"
log_info "Domain: $CF_DOMAIN"
log_info "Config directory: $CLOUDFLARED_DIR"
log_info ""

# Check if Docker is available
if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed. Run ./scripts/02_install_docker.sh first."
    exit 1
fi

# Create cloudflared directory
if [[ ! -d "$CLOUDFLARED_DIR" ]]; then
    log_info "[1/5] Creating cloudflared directory..."
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$CLOUDFLARED_DIR"
        log_info "✓ Created $CLOUDFLARED_DIR"
    else
        log_info "[DRY RUN] Would create $CLOUDFLARED_DIR"
    fi
else
    log_info "[1/5] Cloudflared directory already exists: $CLOUDFLARED_DIR"
fi

# Check if tunnel already exists
if ls "$CLOUDFLARED_DIR"/*.json &>/dev/null; then
    log_warn "Tunnel credentials already exist in $CLOUDFLARED_DIR"
    CRED_FILE=$(ls "$CLOUDFLARED_DIR"/*.json | head -n1)
    TUNNEL_ID=$(basename "$CRED_FILE" .json)

    log_info "Found existing tunnel ID: $TUNNEL_ID"
    log_warn "Using existing tunnel. To create a new tunnel, delete credentials from $CLOUDFLARED_DIR"

    # Update .env with tunnel ID
    if ! grep -q "^CF_TUNNEL_ID=$TUNNEL_ID" .env; then
        log_info "Updating .env with tunnel ID..."
        if [[ "$DRY_RUN" == "false" ]]; then
            sed -i "s|^CF_TUNNEL_ID=.*|CF_TUNNEL_ID=$TUNNEL_ID|" .env
            sed -i "s|^CF_TUNNEL_CREDENTIALS=.*|CF_TUNNEL_CREDENTIALS=/etc/cloudflared/${TUNNEL_ID}.json|" .env
        fi
    fi
else
    log_info "[2/5] Authenticating with Cloudflare..."
    log_info "A browser window will open for authentication."
    log_warn "⚠ You must complete authentication in the browser to continue."
    log_info ""

    if [[ "$DRY_RUN" == "false" ]]; then
        docker run --rm -v "$CLOUDFLARED_DIR:/etc/cloudflared" cloudflare/cloudflared:latest tunnel login
        log_info "✓ Authentication complete"
    else
        log_info "[DRY RUN] Would run: docker run cloudflared tunnel login"
    fi

    log_info "[3/5] Creating tunnel '$CF_TUNNEL_NAME'..."
    if [[ "$DRY_RUN" == "false" ]]; then
        docker run --rm -v "$CLOUDFLARED_DIR:/etc/cloudflared" \
            cloudflare/cloudflared:latest tunnel create "$CF_TUNNEL_NAME"

        # Find the tunnel credentials file
        CRED_FILE=$(ls "$CLOUDFLARED_DIR"/*.json | head -n1)
        if [[ -z "$CRED_FILE" ]]; then
            log_error "Tunnel credentials not found after creation"
            exit 1
        fi

        TUNNEL_ID=$(basename "$CRED_FILE" .json)
        log_info "✓ Tunnel created with ID: $TUNNEL_ID"

        # Update .env file
        log_info "Updating .env file with tunnel information..."
        sed -i "s|^CF_TUNNEL_ID=.*|CF_TUNNEL_ID=$TUNNEL_ID|" .env
        sed -i "s|^CF_TUNNEL_CREDENTIALS=.*|CF_TUNNEL_CREDENTIALS=/etc/cloudflared/${TUNNEL_ID}.json|" .env
        log_info "✓ .env file updated"
    else
        log_info "[DRY RUN] Would create tunnel: $CF_TUNNEL_NAME"
    fi
fi

log_info "[4/5] Generating cloudflared config..."
if [[ "$DRY_RUN" == "false" ]]; then
    # The config.yml is already templated, but we need to create a version with actual values
    # for cloudflared to use (it doesn't support env var expansion)

    # Read from .env
    source .env

    CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"

    cat > "$CONFIG_FILE" <<EOF
tunnel: ${CF_TUNNEL_ID}
credentials-file: /etc/cloudflared/${CF_TUNNEL_ID}.json

ingress:
  - hostname: ${JELLYFIN_HOST}
    service: http://jellyfin:8096
  - hostname: ${JELLYSEERR_HOST}
    service: http://jellyseerr:5055
  - hostname: ${SONARR_HOST}
    service: http://sonarr:8989
  - hostname: ${RADARR_HOST}
    service: http://radarr:7878
  - hostname: ${PROWLARR_HOST}
    service: http://prowlarr:9696
  - hostname: ${RDT_HOST}
    service: http://rdtclient:6500
  - service: http_status:404
EOF

    log_info "✓ Config written to $CONFIG_FILE"
else
    log_info "[DRY RUN] Would generate config file"
fi

log_info "[5/5] DNS Configuration Required"
log_info ""
log_warn "⚠ IMPORTANT: You must add DNS records in Cloudflare"
log_info ""
log_info "Add the following CNAME records in your Cloudflare dashboard:"
log_info "  Domain: $CF_DOMAIN"
log_info "  Target: ${TUNNEL_ID}.cfargotunnel.com"
log_info ""
log_info "Required CNAME records:"
log_info "  tv       -> ${TUNNEL_ID}.cfargotunnel.com"
log_info "  requests -> ${TUNNEL_ID}.cfargotunnel.com"
log_info "  sonarr   -> ${TUNNEL_ID}.cfargotunnel.com"
log_info "  radarr   -> ${TUNNEL_ID}.cfargotunnel.com"
log_info "  prowlarr -> ${TUNNEL_ID}.cfargotunnel.com"
log_info "  rdt      -> ${TUNNEL_ID}.cfargotunnel.com"
log_info ""
log_info "See ./scripts/04_generate_dns_records.md for detailed instructions"
log_info ""

log_info "✓ Cloudflare Tunnel setup complete!"
log_info ""
log_info "Configuration saved to: $CLOUDFLARED_DIR"
log_info "Tunnel ID: ${TUNNEL_ID:-<pending>}"
log_info ""
log_info "Next step: Add DNS records, then run ./scripts/05_compose_up.sh"
