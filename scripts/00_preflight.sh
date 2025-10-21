#!/usr/bin/env bash
set -Eeuo pipefail

# Preflight checks for media server deployment
# Verifies OS, architecture, disk visibility, network, and mount points

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging helpers
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Error handler
trap 'log_error "Preflight check failed at line $LINENO"' ERR

# Flags
DRY_RUN=false
FIX=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --fix) FIX=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be checked without making changes"
            echo "  --fix        Attempt to fix minor issues automatically"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

check_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    log_info "✓ $*"
}

check_warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    log_warn "⚠ $*"
}

check_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log_error "✗ $*"
}

log_info "=== Media Server Preflight Checks ==="
log_info "Target: Raspberry Pi 5 with Raspberry Pi OS Lite 64-bit"
log_info ""

# Check 1: OS Detection
log_info "[1/10] Checking OS and architecture..."
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "$ID" == "debian" ]] || [[ "$ID" == "raspbian" ]]; then
        check_pass "OS: $PRETTY_NAME"
    else
        check_warn "OS: $PRETTY_NAME (expected Raspberry Pi OS/Debian)"
    fi
else
    check_fail "Cannot detect OS (missing /etc/os-release)"
fi

# Check 2: Architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    check_pass "Architecture: $ARCH (ARM64)"
else
    check_fail "Architecture: $ARCH (expected ARM64/aarch64)"
fi

# Check 3: Kernel version
KERNEL=$(uname -r)
check_pass "Kernel: $KERNEL"

# Check 4: Root/sudo access
log_info "[2/10] Checking privileges..."
if [[ $EUID -eq 0 ]]; then
    check_pass "Running as root"
elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
    check_pass "Sudo access available"
else
    check_fail "No root or sudo access (required for disk operations)"
fi

# Check 5: Required commands
log_info "[3/10] Checking required commands..."
REQUIRED_CMDS=(lsblk blkid mount mkfs.ext4 parted)
for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        check_pass "Command available: $cmd"
    else
        check_fail "Missing required command: $cmd"
    fi
done

# Check 6: Disk detection
log_info "[4/10] Checking for USB drives..."
EXPECTED_DRIVES=(sda sdb)
for drive in "${EXPECTED_DRIVES[@]}"; do
    if [[ -b "/dev/$drive" ]]; then
        SIZE=$(lsblk -b -d -n -o SIZE "/dev/$drive" 2>/dev/null | awk '{print int($1/1024/1024/1024)" GB"}')
        check_pass "Drive detected: /dev/$drive ($SIZE)"

        # Check if drive is already mounted
        if mount | grep -q "^/dev/$drive"; then
            MOUNT_POINT=$(mount | grep "^/dev/$drive" | awk '{print $3}')
            check_warn "Drive /dev/$drive already mounted at $MOUNT_POINT"
        fi
    else
        check_fail "Expected drive not found: /dev/$drive"
    fi
done

# Check 7: Mount points
log_info "[5/10] Checking mount points..."
MOUNT_POINTS=("/mnt/movies" "/mnt/tv")
for mp in "${MOUNT_POINTS[@]}"; do
    if mountpoint -q "$mp" 2>/dev/null; then
        DEVICE=$(findmnt -n -o SOURCE "$mp")
        check_warn "Mount point $mp already in use (mounted from $DEVICE)"
    elif [[ -d "$mp" ]]; then
        check_warn "Mount point $mp exists but not mounted"
    else
        check_pass "Mount point $mp ready to be created"
    fi
done

# Check 8: Network connectivity
log_info "[6/10] Checking network connectivity..."
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    check_pass "Internet connectivity (IPv4)"
else
    check_fail "No internet connectivity (required for Docker installation)"
fi

if ping -c 1 -W 2 cloudflare.com &>/dev/null; then
    check_pass "DNS resolution working"
else
    check_warn "DNS resolution issues detected"
fi

# Check 9: Available disk space
log_info "[7/10] Checking system disk space..."
ROOT_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
check_pass "Available space on /: $ROOT_AVAIL"

# Check 10: Memory
log_info "[8/10] Checking system memory..."
TOTAL_MEM=$(free -h | awk 'NR==2 {print $2}')
AVAIL_MEM=$(free -h | awk 'NR==2 {print $7}')
check_pass "Total memory: $TOTAL_MEM (Available: $AVAIL_MEM)"

# Check 11: Docker
log_info "[9/10] Checking Docker installation..."
if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    check_pass "Docker installed: $DOCKER_VERSION"

    if docker compose version &>/dev/null; then
        COMPOSE_VERSION=$(docker compose version --short)
        check_pass "Docker Compose installed: $COMPOSE_VERSION"
    else
        check_warn "Docker Compose not installed (will be installed by 02_install_docker.sh)"
    fi
else
    check_warn "Docker not installed (will be installed by 02_install_docker.sh)"
fi

# Check 12: .env file
log_info "[10/10] Checking configuration..."
if [[ -f .env ]]; then
    check_pass ".env file exists"

    # Check for required variables
    REQUIRED_VARS=(CF_TUNNEL_ID CF_TUNNEL_NAME CF_DOMAIN)
    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^$var=" .env && ! grep -q "^$var=<REPLACE" .env; then
            check_pass ".env has $var configured"
        else
            check_warn ".env missing or needs $var to be set"
        fi
    done
else
    check_warn ".env file not found (copy from .env.sample and configure)"
fi

# Summary
log_info ""
log_info "=== Preflight Summary ==="
log_info "Passed: $PASS_COUNT"
log_info "Warnings: $WARN_COUNT"
log_info "Failed: $FAIL_COUNT"

if [[ $FAIL_COUNT -gt 0 ]]; then
    log_error "Preflight checks failed. Please resolve the issues above before proceeding."
    exit 1
elif [[ $WARN_COUNT -gt 0 ]]; then
    log_warn "Preflight checks completed with warnings. Review before proceeding."
    exit 0
else
    log_info "✓ All preflight checks passed! System ready for deployment."
    log_info ""
    log_info "Next steps:"
    log_info "  1. Copy .env.sample to .env and configure your settings"
    log_info "  2. Run: sudo ./scripts/01_format_and_mount_drives.sh --format"
    log_info "  3. Run: sudo ./scripts/02_install_docker.sh"
    exit 0
fi
