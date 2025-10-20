#!/usr/bin/env bash
set -Eeuo pipefail

# Health checks for media server deployment
# Verifies mounts, containers, and service endpoints

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging helpers
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_check() { echo -e "${BLUE}[CHECK]${NC} $*"; }

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    ((PASS_COUNT++))
    echo -e "${GREEN}✓ PASS${NC} $*"
}

check_fail() {
    ((FAIL_COUNT++))
    echo -e "${RED}✗ FAIL${NC} $*"
}

check_warn() {
    ((WARN_COUNT++))
    echo -e "${YELLOW}⚠ WARN${NC} $*"
}

# Flags
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
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
    log_warn ".env file not found, using defaults"
fi

MOVIES_MOUNT="${MOVIES_MOUNT:-/mnt/movies}"
TV_MOUNT="${TV_MOUNT:-/mnt/tv}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-/mnt/movies/downloads}"

log_info "=== Media Server Health Checks ==="
log_info ""

# Check 1: Mount points
log_check "[1/4] Checking mount points..."
if mountpoint -q "$MOVIES_MOUNT" 2>/dev/null; then
    MOVIES_SIZE=$(df -h "$MOVIES_MOUNT" | awk 'NR==2 {print $2}')
    MOVIES_USED=$(df -h "$MOVIES_MOUNT" | awk 'NR==2 {print $3}')
    MOVIES_AVAIL=$(df -h "$MOVIES_MOUNT" | awk 'NR==2 {print $4}')
    check_pass "Movies mount: $MOVIES_MOUNT ($MOVIES_USED / $MOVIES_SIZE used, $MOVIES_AVAIL available)"
else
    check_fail "Movies mount not found: $MOVIES_MOUNT"
fi

if mountpoint -q "$TV_MOUNT" 2>/dev/null; then
    TV_SIZE=$(df -h "$TV_MOUNT" | awk 'NR==2 {print $2}')
    TV_USED=$(df -h "$TV_MOUNT" | awk 'NR==2 {print $3}')
    TV_AVAIL=$(df -h "$TV_MOUNT" | awk 'NR==2 {print $4}')
    check_pass "TV mount: $TV_MOUNT ($TV_USED / $TV_SIZE used, $TV_AVAIL available)"
else
    check_fail "TV mount not found: $TV_MOUNT"
fi

if [[ -d "$DOWNLOADS_DIR" ]]; then
    check_pass "Downloads directory exists: $DOWNLOADS_DIR"
else
    check_fail "Downloads directory not found: $DOWNLOADS_DIR"
fi

# Check 2: Docker containers
log_info ""
log_check "[2/4] Checking Docker containers..."

COMPOSE_FILE="compose/docker-compose.yml"
EXPECTED_CONTAINERS=("jellyfin" "jellyseerr" "sonarr" "radarr" "prowlarr" "rdtclient" "watchtower" "cloudflared")

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        STATUS=$(docker inspect --format='{{.State.Status}}' "$container")
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")

        if [[ "$STATUS" == "running" ]]; then
            if [[ "$HEALTH" == "healthy" ]] || [[ "$HEALTH" == "none" ]]; then
                UPTIME=$(docker inspect --format='{{.State.StartedAt}}' "$container" | xargs -I {} date -d {} +%s)
                NOW=$(date +%s)
                SECONDS=$((NOW - UPTIME))
                if [[ $SECONDS -gt 86400 ]]; then
                    UPTIME_STR="$((SECONDS / 86400))d"
                elif [[ $SECONDS -gt 3600 ]]; then
                    UPTIME_STR="$((SECONDS / 3600))h"
                else
                    UPTIME_STR="$((SECONDS / 60))m"
                fi
                check_pass "Container '$container' running (uptime: $UPTIME_STR)"
            elif [[ "$HEALTH" == "starting" ]]; then
                check_warn "Container '$container' starting (health check pending)"
            else
                check_fail "Container '$container' unhealthy (status: $HEALTH)"
            fi
        else
            check_fail "Container '$container' not running (status: $STATUS)"
        fi
    else
        check_fail "Container '$container' not found"
    fi
done

# Check 3: Service endpoints
log_info ""
log_check "[3/4] Checking service HTTP endpoints..."

# Helper function to check endpoint
check_endpoint() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}

    if curl -sf -o /dev/null -w "%{http_code}" --max-time 5 "$url" | grep -q "$expected_code"; then
        check_pass "Service '$name' responding at $url"
        return 0
    else
        check_fail "Service '$name' not responding at $url"
        return 1
    fi
}

# Check services (local endpoints)
check_endpoint "Jellyfin" "http://localhost:8096/health" "200"
check_endpoint "Jellyseerr" "http://localhost:5055/api/v1/status" "200"

# For *Arr apps, just check if port is open (they may require API keys)
if curl -sf --max-time 5 http://localhost:8989 &>/dev/null; then
    check_pass "Service 'Sonarr' responding at http://localhost:8989"
else
    check_fail "Service 'Sonarr' not responding at http://localhost:8989"
fi

if curl -sf --max-time 5 http://localhost:7878 &>/dev/null; then
    check_pass "Service 'Radarr' responding at http://localhost:7878"
else
    check_fail "Service 'Radarr' not responding at http://localhost:7878"
fi

if curl -sf --max-time 5 http://localhost:9696 &>/dev/null; then
    check_pass "Service 'Prowlarr' responding at http://localhost:9696"
else
    check_fail "Service 'Prowlarr' not responding at http://localhost:9696"
fi

if curl -sf --max-time 5 http://localhost:6500 &>/dev/null; then
    check_pass "Service 'RdtClient' responding at http://localhost:6500"
else
    check_fail "Service 'RdtClient' not responding at http://localhost:6500"
fi

# Check 4: Cloudflare Tunnel
log_info ""
log_check "[4/5] Checking Cloudflare Tunnel..."

if docker ps --format '{{.Names}}' | grep -q "^cloudflared$"; then
    # Check logs for tunnel status
    if docker logs cloudflared 2>&1 | tail -20 | grep -q "Registered tunnel connection"; then
        check_pass "Cloudflare Tunnel connected"
    elif docker logs cloudflared 2>&1 | tail -20 | grep -qi "error"; then
        LAST_ERROR=$(docker logs cloudflared 2>&1 | tail -20 | grep -i error | tail -1)
        check_warn "Cloudflare Tunnel may have errors: $LAST_ERROR"
    else
        check_warn "Cloudflare Tunnel status unknown (check logs)"
    fi
else
    check_fail "Cloudflare Tunnel container not running"
fi

# Check 5: Tailscale (optional)
log_info ""
log_check "[5/5] Checking Tailscale (optional)..."

if command -v tailscale &>/dev/null; then
    if tailscale status &>/dev/null 2>&1; then
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
        check_pass "Tailscale connected ($TS_IP)"

        # Verify safe configuration
        if grep -q "100.100.100.100" /etc/resolv.conf 2>/dev/null; then
            check_warn "Tailscale DNS enabled (may conflict with Docker)"
        fi

        DEFAULT_ROUTE=$(ip route show | grep default | head -n1)
        if echo "$DEFAULT_ROUTE" | grep -q "tailscale0"; then
            check_warn "Default route via Tailscale (may break Cloudflare Tunnel)"
        fi
    else
        check_warn "Tailscale installed but not connected"
    fi
else
    log_info "Tailscale not installed (optional)"
fi

# Summary
log_info ""
log_info "=== Health Check Summary ==="
echo -e "${GREEN}Passed:  $PASS_COUNT${NC}"
echo -e "${YELLOW}Warnings: $WARN_COUNT${NC}"
echo -e "${RED}Failed:   $FAIL_COUNT${NC}"

log_info ""

if [[ $FAIL_COUNT -eq 0 ]] && [[ $WARN_COUNT -eq 0 ]]; then
    log_info "✓ All health checks passed! System is healthy."
    exit 0
elif [[ $FAIL_COUNT -eq 0 ]]; then
    log_warn "Health checks passed with warnings. Review above."
    exit 0
else
    log_error "Health checks failed. Please review the issues above."
    log_info ""
    log_info "Common troubleshooting steps:"
    log_info "  - Check container logs: docker logs <container-name>"
    log_info "  - Restart services: docker compose -f compose/docker-compose.yml restart"
    log_info "  - Verify mounts: findmnt $MOVIES_MOUNT $TV_MOUNT"
    log_info "  - Check network: docker network inspect media-net"
    exit 1
fi
