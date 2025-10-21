#!/usr/bin/env bash
set -Eeuo pipefail

# Phase 1 Rollback Script
# Removes Phase 1 services and restores to Phase 0 state

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

log_info "=== Phase 1 Rollback ==="
log_info ""
log_warn "This will remove:"
log_warn "  • Bazarr"
log_warn "  • Caddy"
log_warn "  • Homer"
log_warn "  • Performance optimizations"
log_warn ""
log_warn "Phase 0 services will remain unchanged"
log_warn ""

read -p "Continue with rollback? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Rollback cancelled"
    exit 0
fi

log_info "[1/3] Stopping and removing Phase 1 services..."
docker compose -f compose/docker-compose.phase1.yml down
docker volume rm caddy_data caddy_config 2>/dev/null || true
log_info "✓ Phase 1 services removed"

log_info "[2/3] Removing Phase 1 configs..."
rm -rf config/bazarr config/caddy config/homer
log_info "✓ Configs removed"

log_info "[3/3] Reverting to Phase 0..."
docker compose -f compose/docker-compose.yml up -d
log_info "✓ Phase 0 services restarted"

log_info ""
log_info "✓ Rollback complete!"
log_info "System restored to Phase 0 state"
log_info ""
log_info "Note: Performance optimizations remain. To revert those:"
log_info "  Restore from backup in /root/media-server-optimization-backup-*"
