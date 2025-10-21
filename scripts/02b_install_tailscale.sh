#!/usr/bin/env bash
set -Eeuo pipefail

# Install and configure Tailscale for secure SSH access
# Configured with safe flags to avoid conflicts with Cloudflare Tunnel

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
SKIP_AUTH=false
ENABLE_SSH=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --skip-auth) SKIP_AUTH=true; shift ;;
        --no-ssh) ENABLE_SSH=false; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Install and configure Tailscale for secure SSH access"
            echo ""
            echo "Options:"
            echo "  --dry-run     Show what would be done without making changes"
            echo "  --skip-auth   Skip Tailscale authentication (for automation)"
            echo "  --no-ssh      Don't enable Tailscale SSH"
            echo "  --verbose     Show detailed output"
            echo "  --help        Show this help message"
            echo ""
            echo "Note: This configures Tailscale with safe flags:"
            echo "  - DNS disabled (won't interfere with Docker/Cloudflare)"
            echo "  - Routes disabled (won't change default gateway)"
            echo "  - Exit node disabled (won't route other devices' traffic)"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

log_info "=== Tailscale Installation for Media Server ==="
log_info ""

# Load environment if available
if [[ -f .env ]]; then
    source .env 2>/dev/null || true
fi

# Check if already installed
if command -v tailscale &>/dev/null; then
    TAILSCALE_VERSION=$(tailscale version | head -n1)
    log_warn "Tailscale is already installed: $TAILSCALE_VERSION"

    if tailscale status &>/dev/null 2>&1; then
        log_info "Tailscale is running and connected"
        CURRENT_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
        log_info "Current Tailscale IP: $CURRENT_IP"

        log_info ""
        log_info "To reconfigure with safe settings, run:"
        log_info "  sudo tailscale down"
        log_info "  sudo tailscale up --accept-routes=false --advertise-exit-node=false --accept-dns=false --ssh"
        exit 0
    else
        log_warn "Tailscale is installed but not running"
    fi
fi

log_info "[1/5] Capturing network baseline..."
if [[ "$DRY_RUN" == "false" ]]; then
    mkdir -p baseline
    ip route show > baseline/routes-before-tailscale.txt 2>/dev/null || true
    cat /etc/resolv.conf > baseline/dns-before-tailscale.txt 2>/dev/null || true
    log_info "✓ Baseline saved to baseline/"
else
    log_info "[DRY RUN] Would save network baseline"
fi

log_info "[2/5] Installing Tailscale..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Download and run official installer
    curl -fsSL https://tailscale.com/install.sh | sh
    log_info "✓ Tailscale installed"
else
    log_info "[DRY RUN] Would install Tailscale"
fi

log_info "[3/5] Configuring Tailscale with safe settings..."
log_warn "⚠ IMPORTANT: Using safe flags to prevent conflicts:"
log_info "  --accept-dns=false          (Won't override Docker/Cloudflare DNS)"
log_info "  --accept-routes=false       (Won't change default gateway)"
log_info "  --advertise-exit-node=false (Won't route other devices)"
if [[ "$ENABLE_SSH" == "true" ]]; then
    log_info "  --ssh                       (Enable Tailscale SSH)"
fi

if [[ "$DRY_RUN" == "false" ]]; then
    # Build the tailscale up command
    TS_CMD="sudo tailscale up --accept-routes=false --advertise-exit-node=false --accept-dns=false"
    if [[ "$ENABLE_SSH" == "true" ]]; then
        TS_CMD="$TS_CMD --ssh"
    fi

    if [[ "$SKIP_AUTH" == "true" ]]; then
        log_warn "Skipping authentication (--skip-auth specified)"
        log_warn "You'll need to manually run: $TS_CMD"
    else
        log_info "Starting Tailscale (will require authentication)..."
        log_info ""
        log_warn "⚠ A browser will open for authentication"
        log_info "Please complete authentication in the browser"
        log_info ""

        eval $TS_CMD

        log_info "✓ Tailscale configured and authenticated"
    fi
else
    log_info "[DRY RUN] Would configure Tailscale with safe flags"
fi

log_info "[4/5] Verifying configuration..."
if [[ "$DRY_RUN" == "false" ]] && tailscale status &>/dev/null 2>&1; then
    # Get Tailscale IP
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
    log_info "✓ Tailscale IP: $TS_IP"

    # Check default route didn't change
    DEFAULT_ROUTE=$(ip route show | grep default | head -n1)
    if echo "$DEFAULT_ROUTE" | grep -q "tailscale0"; then
        log_error "⚠ WARNING: Default route was changed to Tailscale!"
        log_error "This will break Cloudflare Tunnel. Reconfiguring..."
        sudo tailscale down
        sudo tailscale up --accept-routes=false --advertise-exit-node=false --accept-dns=false $([ "$ENABLE_SSH" == "true" ] && echo "--ssh" || echo "")
    else
        log_info "✓ Default route preserved: $DEFAULT_ROUTE"
    fi

    # Check DNS didn't change
    if grep -q "100.100.100.100" /etc/resolv.conf; then
        log_error "⚠ WARNING: DNS was overridden by Tailscale!"
        log_error "This will break Docker DNS resolution. Reconfiguring..."
        sudo tailscale down
        sudo tailscale up --accept-routes=false --advertise-exit-node=false --accept-dns=false $([ "$ENABLE_SSH" == "true" ] && echo "--ssh" || echo "")
    else
        log_info "✓ DNS configuration preserved"
    fi
else
    log_info "[DRY RUN] Would verify configuration"
fi

log_info "[5/5] Enabling Tailscale service..."
if [[ "$DRY_RUN" == "false" ]]; then
    sudo systemctl enable tailscaled
    sudo systemctl start tailscaled
    log_info "✓ Tailscale service enabled"
else
    log_info "[DRY RUN] Would enable Tailscale service"
fi

# Summary
log_info ""
log_info "=== Tailscale Installation Complete ==="

if [[ "$DRY_RUN" == "false" ]] && tailscale status &>/dev/null 2>&1; then
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
    TS_HOSTNAME=$(hostname)

    log_info ""
    log_info "✓ Tailscale is configured and running"
    log_info ""
    log_info "Access this server via Tailscale:"
    log_info "  SSH: ssh $(whoami)@$TS_IP"
    log_info "  Or:  ssh $(whoami)@$TS_HOSTNAME"
    log_info ""
    log_info "Services are still accessible via Cloudflare Tunnel (unchanged):"
    if [[ -n "${JELLYFIN_HOST:-}" ]]; then
        log_info "  Jellyfin: https://${JELLYFIN_HOST}"
    fi
    log_info ""
    log_info "Verify both are working:"
    log_info "  make health"
    log_info "  bash verify/check_network.sh"
else
    log_info "[DRY RUN] Installation would be complete"
fi

log_info ""
log_info "Next step: Verify Cloudflare Tunnel still works"
log_info "  docker logs cloudflared | tail -20"
log_info "  Should see: 'Registered tunnel connection'"
