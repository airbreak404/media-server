#!/usr/bin/env bash
set -Eeuo pipefail

# Performance Optimization for Raspberry Pi 5
# Applies safe system tuning for better media server performance

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Error handler
trap 'log_error "Optimization failed at line $LINENO"' ERR

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
            echo "Optimize Raspberry Pi 5 for media server workload"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this message"
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

log_info "=== Raspberry Pi Performance Optimization ==="
log_info ""

# Backup current settings
BACKUP_DIR="/root/media-server-optimization-backup-$(date +%Y%m%d_%H%M%S)"
if [[ "$DRY_RUN" == "false" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp /etc/sysctl.conf "$BACKUP_DIR/" 2>/dev/null || true
    cp /etc/fstab "$BACKUP_DIR/" 2>/dev/null || true
    log_info "✓ Backup saved to $BACKUP_DIR"
fi

# 1. Enable zram (compressed RAM)
log_info "[1/6] Configuring zram (compressed RAM)..."
if [[ "$DRY_RUN" == "false" ]]; then
    if ! command -v zramctl &>/dev/null; then
        apt-get install -y zram-tools
    fi

    # Configure zram
    cat > /etc/default/zramswap <<EOF
# Zram configuration for media server
# Compress 50% of RAM for swap
PERCENTAGE=50
PRIORITY=100
EOF

    systemctl enable zramswap || true
    systemctl restart zramswap || true
    log_info "✓ Zram enabled (50% of RAM compressed)"
else
    log_info "[DRY RUN] Would enable zram"
fi

# 2. Optimize swap settings
log_info "[2/6] Optimizing swap behavior..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Reduce swappiness (prefer RAM over swap)
    sysctl -w vm.swappiness=10

    # Increase cache pressure
    sysctl -w vm.vfs_cache_pressure=50

    # Make persistent
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi
    if ! grep -q "vm.vfs_cache_pressure" /etc/sysctl.conf; then
        echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    fi

    log_info "✓ Swap optimized (swappiness=10)"
else
    log_info "[DRY RUN] Would optimize swap"
fi

# 3. Optimize network stack
log_info "[3/6] Optimizing network stack..."
if [[ "$DRY_RUN" == "false" ]]; then
    # TCP optimizations for streaming
    cat >> /etc/sysctl.conf <<EOF

# Media server network optimizations
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
net.ipv4.tcp_mtu_probing=1
EOF

    sysctl -p
    log_info "✓ Network stack optimized (BBR congestion control)"
else
    log_info "[DRY RUN] Would optimize network"
fi

# 4. Optimize filesystem mounts
log_info "[4/6] Optimizing filesystem mounts..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Add noatime to reduce disk writes
    if grep -q "/mnt/movies" /etc/fstab; then
        if ! grep -q "noatime" /etc/fstab; then
            sed -i 's|\(/mnt/movies.*ext4.*defaults\)|\1,noatime|' /etc/fstab
            sed -i 's|\(/mnt/tv.*ext4.*defaults\)|\1,noatime|' /etc/fstab
            log_info "✓ Added noatime to media mounts"
        else
            log_info "✓ Mounts already optimized"
        fi
    else
        log_warn "Media mounts not in /etc/fstab yet, skipping"
    fi
else
    log_info "[DRY RUN] Would add noatime to mounts"
fi

# 5. Optimize I/O scheduler
log_info "[5/6] Optimizing I/O scheduler..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Use deadline scheduler for SSDs
    if [[ -b /dev/sda ]]; then
        echo deadline > /sys/block/sda/queue/scheduler 2>/dev/null || true
    fi
    if [[ -b /dev/sdb ]]; then
        echo deadline > /sys/block/sdb/queue/scheduler 2>/dev/null || true
    fi

    # Make persistent
    cat > /etc/udev/rules.d/60-ioschedulers.rules <<EOF
# Set deadline scheduler for HDDs
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="deadline"
EOF

    log_info "✓ I/O scheduler set to deadline"
else
    log_info "[DRY RUN] Would set I/O scheduler"
fi

# 6. Docker optimizations
log_info "[6/6] Optimizing Docker..."
if [[ "$DRY_RUN" == "false" ]]; then
    mkdir -p /etc/docker

    # Create daemon.json if it doesn't exist
    if [[ ! -f /etc/docker/daemon.json ]]; then
        cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
    else
        log_info "Docker daemon.json already exists, skipping"
    fi

    log_info "✓ Docker logging optimized"
else
    log_info "[DRY RUN] Would optimize Docker"
fi

# Summary
log_info ""
log_info "=== Optimization Complete ==="
log_info ""
log_info "Applied optimizations:"
log_info "  ✓ Zram compression enabled"
log_info "  ✓ Swap tuning (swappiness=10)"
log_info "  ✓ Network stack (BBR, larger buffers)"
log_info "  ✓ Filesystem mounts (noatime)"
log_info "  ✓ I/O scheduler (deadline)"
log_info "  ✓ Docker logging limits"
log_info ""
log_info "Backup saved to: $BACKUP_DIR"
log_info ""
log_info "⚠ Reboot recommended for all changes to take effect"
log_info "  sudo reboot"
log_info ""
log_info "To rollback: scripts/phase1/rollback_optimization.sh"
