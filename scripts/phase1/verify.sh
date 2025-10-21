#!/usr/bin/env bash
set -Eeuo pipefail

# Phase 1 Verification Script
# Checks that all Phase 1 services are running correctly

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

PASS_COUNT=0
FAIL_COUNT=0

check_pass() {
    ((PASS_COUNT++))
    echo -e "${GREEN}✓${NC} $*"
}

check_fail() {
    ((FAIL_COUNT++))
    echo -e "${RED}✗${NC} $*"
}

log_info "=== Phase 1 Verification ==="
log_info ""

# Check containers
log_info "Checking containers..."
CONTAINERS=("bazarr" "caddy" "homer")
for container in "${CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        STATUS=$(docker inspect --format='{{.State.Status}}' "$container")
        if [[ "$STATUS" == "running" ]]; then
            check_pass "$container is running"
        else
            check_fail "$container is $STATUS"
        fi
    else
        check_fail "$container not found"
    fi
done

# Check endpoints
log_info ""
log_info "Checking HTTP endpoints..."

if curl -sf --max-time 5 http://localhost:6767 &>/dev/null; then
    check_pass "Bazarr responding on :6767"
else
    check_fail "Bazarr not responding"
fi

if curl -sf --max-time 5 http://localhost:8080 &>/dev/null; then
    check_pass "Homer responding on :8080"
else
    check_fail "Homer not responding"
fi

if curl -sfk --max-time 5 https://localhost:443 &>/dev/null; then
    check_pass "Caddy responding on :443"
else
    check_fail "Caddy not responding"
fi

# Summary
log_info ""
log_info "=== Verification Summary ==="
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"

if [[ $FAIL_COUNT -eq 0 ]]; then
    log_info ""
    log_info "✓ Phase 1 verification passed!"
    exit 0
else
    log_error ""
    log_error "Phase 1 verification failed"
    log_error "Check logs: docker compose logs"
    exit 1
fi
