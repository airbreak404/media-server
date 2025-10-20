#!/usr/bin/env bash
set -Eeuo pipefail

# Install Docker Engine and Docker Compose v2
# Configures Docker for ARM64/aarch64 architecture

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

# Check for root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_info "=== Docker Installation for Media Server ==="
log_info ""

# Check if Docker is already installed
if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version)
    log_warn "Docker is already installed: $DOCKER_VERSION"

    if docker compose version &>/dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        log_warn "Docker Compose is already installed: $COMPOSE_VERSION"
        log_info "Skipping installation. If you want to reinstall, remove Docker first."
        exit 0
    fi
fi

log_info "[1/6] Removing old Docker versions (if any)..."
if [[ "$DRY_RUN" == "false" ]]; then
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    log_info "✓ Old versions removed"
else
    log_info "[DRY RUN] Would remove old Docker packages"
fi

log_info "[2/6] Installing prerequisites..."
if [[ "$DRY_RUN" == "false" ]]; then
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    log_info "✓ Prerequisites installed"
else
    log_info "[DRY RUN] Would install: ca-certificates curl gnupg lsb-release"
fi

log_info "[3/6] Adding Docker's official GPG key..."
if [[ "$DRY_RUN" == "false" ]]; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    log_info "✓ GPG key added"
else
    log_info "[DRY RUN] Would add Docker GPG key"
fi

log_info "[4/6] Setting up Docker repository..."
if [[ "$DRY_RUN" == "false" ]]; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    log_info "✓ Repository configured"
else
    log_info "[DRY RUN] Would configure Docker repository"
fi

log_info "[5/6] Installing Docker Engine and Docker Compose..."
if [[ "$DRY_RUN" == "false" ]]; then
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    log_info "✓ Docker installed"
else
    log_info "[DRY RUN] Would install Docker and Compose"
fi

log_info "[6/6] Configuring Docker..."

# Add current user to docker group
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER=$(logname 2>/dev/null || echo "")
fi

if [[ -n "$REAL_USER" ]] && [[ "$REAL_USER" != "root" ]]; then
    log_info "Adding user '$REAL_USER' to docker group..."
    if [[ "$DRY_RUN" == "false" ]]; then
        usermod -aG docker "$REAL_USER"
        log_info "✓ User '$REAL_USER' added to docker group"
        log_warn "⚠ You will need to log out and back in for group membership to take effect"
    else
        log_info "[DRY RUN] Would add user '$REAL_USER' to docker group"
    fi
fi

# Enable and start Docker service
if [[ "$DRY_RUN" == "false" ]]; then
    systemctl enable docker
    systemctl start docker
    log_info "✓ Docker service enabled and started"
else
    log_info "[DRY RUN] Would enable and start Docker service"
fi

# Verify installation
log_info ""
log_info "=== Verification ==="
if [[ "$DRY_RUN" == "false" ]]; then
    DOCKER_VERSION=$(docker --version)
    COMPOSE_VERSION=$(docker compose version)

    log_info "✓ Docker version: $DOCKER_VERSION"
    log_info "✓ Compose version: $COMPOSE_VERSION"

    # Test Docker with hello-world
    log_info "Running hello-world test..."
    if docker run --rm hello-world &>/dev/null; then
        log_info "✓ Docker is working correctly!"
    else
        log_error "Docker test failed"
        exit 1
    fi
else
    log_info "[DRY RUN] Would verify Docker installation"
fi

log_info ""
log_info "✓ Docker installation complete!"
log_info ""

if [[ -n "${REAL_USER:-}" ]] && [[ "$REAL_USER" != "root" ]]; then
    log_warn "IMPORTANT: Log out and back in (or run 'newgrp docker') before running Docker commands as $REAL_USER"
fi

log_info ""
log_info "Next step: Run ./scripts/03_cloudflared_login_and_tunnel.sh"
