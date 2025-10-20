#!/usr/bin/env bash
set -Eeuo pipefail

# Format and mount USB drives for media storage
# Creates ext4 filesystems and adds persistent mounts to /etc/fstab

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
FORMAT=false
VERBOSE=false

# Configuration
DRIVE_MOVIES="/dev/sda"
DRIVE_TV="/dev/sdb"
MOUNT_MOVIES="/mnt/movies"
MOUNT_TV="/mnt/tv"
DOWNLOADS_DIR="/mnt/movies/downloads"
PUID=1000
PGID=1000

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --format) FORMAT=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --format     Format drives (DESTRUCTIVE - erases all data)"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this help message"
            echo ""
            echo "Warning: --format will ERASE ALL DATA on $DRIVE_MOVIES and $DRIVE_TV"
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

log_info "=== Disk Setup for Media Server ==="
log_info "Movies drive: $DRIVE_MOVIES -> $MOUNT_MOVIES"
log_info "TV drive: $DRIVE_TV -> $MOUNT_TV"
log_info "Downloads: $DOWNLOADS_DIR"
log_info ""

if [[ "$FORMAT" == "true" ]]; then
    log_warn "⚠ WARNING: Format mode enabled - this will ERASE ALL DATA on the drives!"
    log_warn "Drives to be formatted: $DRIVE_MOVIES, $DRIVE_TV"
    log_warn "Press Ctrl+C within 10 seconds to cancel..."
    sleep 10
    log_info "Proceeding with format..."
fi

# Function to check if drive exists
check_drive() {
    local drive=$1
    if [[ ! -b "$drive" ]]; then
        log_error "Drive not found: $drive"
        return 1
    fi
    log_info "✓ Drive detected: $drive"
    lsblk "$drive"
}

# Function to format drive
format_drive() {
    local drive=$1
    local label=$2

    log_info "Formatting $drive with label '$label'..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would partition and format $drive"
        return 0
    fi

    # Unmount if already mounted
    if mount | grep -q "^${drive}"; then
        log_info "Unmounting ${drive}..."
        umount "${drive}"* 2>/dev/null || true
    fi

    # Create single partition
    log_info "Creating partition table on $drive..."
    parted -s "$drive" mklabel gpt
    parted -s "$drive" mkpart primary ext4 0% 100%

    # Wait for partition device
    sleep 2
    local partition="${drive}1"

    if [[ ! -b "$partition" ]]; then
        log_error "Partition $partition not created"
        return 1
    fi

    # Format as ext4
    log_info "Creating ext4 filesystem on $partition..."
    mkfs.ext4 -F -L "$label" "$partition"

    log_info "✓ Formatted $partition as ext4 with label '$label'"
}

# Function to mount drive
mount_drive() {
    local drive=$1
    local mount_point=$2

    local partition="${drive}1"

    # Get PARTUUID
    local partuuid
    partuuid=$(blkid -s PARTUUID -o value "$partition")

    if [[ -z "$partuuid" ]]; then
        log_error "Could not get PARTUUID for $partition"
        return 1
    fi

    log_info "PARTUUID for $partition: $partuuid"

    # Create mount point
    if [[ ! -d "$mount_point" ]]; then
        log_info "Creating mount point: $mount_point"
        if [[ "$DRY_RUN" == "false" ]]; then
            mkdir -p "$mount_point"
        fi
    fi

    # Mount the drive
    if mountpoint -q "$mount_point"; then
        log_warn "$mount_point already mounted, skipping mount"
    else
        log_info "Mounting $partition to $mount_point..."
        if [[ "$DRY_RUN" == "false" ]]; then
            mount "$partition" "$mount_point"
        fi
    fi

    # Set ownership and permissions
    log_info "Setting ownership (${PUID}:${PGID}) and permissions (775) on $mount_point..."
    if [[ "$DRY_RUN" == "false" ]]; then
        chown "${PUID}:${PGID}" "$mount_point"
        chmod 775 "$mount_point"
    fi

    # Add to fstab if not already present
    local fstab_entry="PARTUUID=$partuuid $mount_point ext4 defaults,nofail 0 2"

    if grep -q "$partuuid" /etc/fstab; then
        log_warn "Entry for PARTUUID=$partuuid already in /etc/fstab, skipping"
    else
        log_info "Adding entry to /etc/fstab..."
        if [[ "$DRY_RUN" == "false" ]]; then
            echo "$fstab_entry" >> /etc/fstab
            log_info "✓ Added to /etc/fstab: $fstab_entry"
        else
            log_info "[DRY RUN] Would add: $fstab_entry"
        fi
    fi
}

# Main execution
log_info "[1/4] Checking drives..."
check_drive "$DRIVE_MOVIES"
check_drive "$DRIVE_TV"

if [[ "$FORMAT" == "true" ]]; then
    log_info "[2/4] Formatting drives..."
    format_drive "$DRIVE_MOVIES" "movies"
    format_drive "$DRIVE_TV" "tv"
else
    log_info "[2/4] Skipping format (use --format to format drives)"

    # Check if partitions exist
    if [[ ! -b "${DRIVE_MOVIES}1" ]]; then
        log_error "${DRIVE_MOVIES}1 not found. Run with --format to create partitions."
        exit 1
    fi
    if [[ ! -b "${DRIVE_TV}1" ]]; then
        log_error "${DRIVE_TV}1 not found. Run with --format to create partitions."
        exit 1
    fi
fi

log_info "[3/4] Mounting drives..."
mount_drive "$DRIVE_MOVIES" "$MOUNT_MOVIES"
mount_drive "$DRIVE_TV" "$MOUNT_TV"

log_info "[4/4] Creating downloads directory..."
if [[ ! -d "$DOWNLOADS_DIR" ]]; then
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$DOWNLOADS_DIR"
        chown "${PUID}:${PGID}" "$DOWNLOADS_DIR"
        chmod 775 "$DOWNLOADS_DIR"
        log_info "✓ Created $DOWNLOADS_DIR"
    else
        log_info "[DRY RUN] Would create $DOWNLOADS_DIR"
    fi
else
    log_info "✓ Downloads directory already exists: $DOWNLOADS_DIR"
fi

# Verify mounts
log_info ""
log_info "=== Mount Verification ==="
if [[ "$DRY_RUN" == "false" ]]; then
    mount -a
    findmnt "$MOUNT_MOVIES" "$MOUNT_TV"

    log_info ""
    log_info "✓ Drive setup complete!"
    log_info ""
    log_info "Mount summary:"
    df -h "$MOUNT_MOVIES" "$MOUNT_TV"
else
    log_info "[DRY RUN] Would run: mount -a"
    log_info "[DRY RUN] Complete"
fi

log_info ""
log_info "Next step: Run ./scripts/02_install_docker.sh"
