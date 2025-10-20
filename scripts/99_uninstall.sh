#!/usr/bin/env bash
set -Eeuo pipefail

# Uninstall media server
# Stops containers and optionally removes data

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
PURGE=false
REMOVE_CONFIG=false
REMOVE_MEDIA=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --purge) PURGE=true; shift ;;
        --remove-config) REMOVE_CONFIG=true; shift ;;
        --remove-media) REMOVE_MEDIA=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Safely uninstall media server components"
            echo ""
            echo "Options:"
            echo "  --dry-run         Show what would be done without making changes"
            echo "  --purge           Remove Docker images (but preserve configs)"
            echo "  --remove-config   Remove configuration directories (DESTRUCTIVE)"
            echo "  --remove-media    Remove media files and unmount drives (VERY DESTRUCTIVE)"
            echo "  --verbose         Show detailed output"
            echo "  --help            Show this help message"
            echo ""
            echo "Warning: --remove-config and --remove-media are DESTRUCTIVE operations"
            echo "         Always create a backup before using these options"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

log_info "=== Media Server Uninstall ==="
log_info ""

# Confirmation for destructive operations
if [[ "$REMOVE_CONFIG" == "true" ]] || [[ "$REMOVE_MEDIA" == "true" ]]; then
    log_error "⚠ WARNING: DESTRUCTIVE OPERATION REQUESTED ⚠"
    if [[ "$REMOVE_CONFIG" == "true" ]]; then
        log_warn "  - Application configurations will be DELETED"
    fi
    if [[ "$REMOVE_MEDIA" == "true" ]]; then
        log_warn "  - Media files will be DELETED"
        log_warn "  - Drives will be UNMOUNTED"
    fi
    log_warn ""
    log_warn "This action CANNOT be undone!"
    log_warn "Press Ctrl+C within 15 seconds to cancel..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 15
    fi
    log_info "Proceeding with uninstall..."
fi

COMPOSE_FILE="compose/docker-compose.yml"

# Step 1: Stop containers
log_info "[1/5] Stopping Docker containers..."
if [[ -f "$COMPOSE_FILE" ]]; then
    if [[ "$DRY_RUN" == "false" ]]; then
        docker compose -f "$COMPOSE_FILE" down
        log_info "✓ Containers stopped and removed"
    else
        log_info "[DRY RUN] Would run: docker compose -f $COMPOSE_FILE down"
    fi
else
    log_warn "Compose file not found, skipping container shutdown"
fi

# Step 2: Remove Docker network
log_info "[2/5] Cleaning up Docker network..."
if docker network inspect media-net &>/dev/null; then
    if [[ "$DRY_RUN" == "false" ]]; then
        docker network rm media-net 2>/dev/null || log_warn "Network removal failed (may be in use)"
        log_info "✓ Network removed"
    else
        log_info "[DRY RUN] Would remove Docker network: media-net"
    fi
else
    log_info "Network 'media-net' not found, skipping"
fi

# Step 3: Remove Docker images (if --purge)
log_info "[3/5] Handling Docker images..."
if [[ "$PURGE" == "true" ]]; then
    log_info "Removing Docker images..."
    IMAGES=(
        "lscr.io/linuxserver/jellyfin:latest"
        "fallenbagel/jellyseerr:latest"
        "lscr.io/linuxserver/sonarr:latest"
        "lscr.io/linuxserver/radarr:latest"
        "lscr.io/linuxserver/prowlarr:latest"
        "rogerfar/rdtclient:latest"
        "containrrr/watchtower:latest"
        "cloudflare/cloudflared:latest"
    )

    if [[ "$DRY_RUN" == "false" ]]; then
        for image in "${IMAGES[@]}"; do
            if docker images -q "$image" &>/dev/null; then
                docker rmi "$image" 2>/dev/null && log_info "  ✓ Removed: $image" || log_warn "  ⚠ Failed to remove: $image"
            fi
        done
        log_info "✓ Images removed"
    else
        log_info "[DRY RUN] Would remove Docker images"
    fi
else
    log_info "Preserving Docker images (use --purge to remove)"
fi

# Step 4: Remove configuration (if --remove-config)
log_info "[4/5] Handling configurations..."
if [[ "$REMOVE_CONFIG" == "true" ]]; then
    log_warn "Removing configuration directories..."

    CONFIG_DIRS=("config" "cloudflared")
    CONFIG_FILES=(".env")

    if [[ "$DRY_RUN" == "false" ]]; then
        for dir in "${CONFIG_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                rm -rf "$dir"
                log_info "  ✓ Removed: $dir/"
            fi
        done

        # Remove cloudflared from home directory
        if [[ -d "${HOME}/cloudflared" ]]; then
            rm -rf "${HOME}/cloudflared"
            log_info "  ✓ Removed: ~/cloudflared/"
        fi

        for file in "${CONFIG_FILES[@]}"; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log_info "  ✓ Removed: $file"
            fi
        done

        log_info "✓ Configurations removed"
    else
        log_info "[DRY RUN] Would remove configurations"
    fi
else
    log_info "Preserving configurations (use --remove-config to remove)"
fi

# Step 5: Remove media and unmount (if --remove-media)
log_info "[5/5] Handling media storage..."
if [[ "$REMOVE_MEDIA" == "true" ]]; then
    log_error "⚠ REMOVING MEDIA FILES AND UNMOUNTING DRIVES ⚠"

    if [[ "$DRY_RUN" == "false" ]]; then
        # Unmount drives
        for mount in /mnt/movies /mnt/tv; do
            if mountpoint -q "$mount"; then
                log_info "Unmounting $mount..."
                umount "$mount" && log_info "  ✓ Unmounted: $mount" || log_error "  ✗ Failed to unmount: $mount"
            fi
        done

        # Remove mount points
        for mount in /mnt/movies /mnt/tv; do
            if [[ -d "$mount" ]]; then
                rmdir "$mount" 2>/dev/null && log_info "  ✓ Removed: $mount" || log_warn "  ⚠ Could not remove: $mount (not empty?)"
            fi
        done

        # Remove fstab entries
        if [[ -f /etc/fstab ]]; then
            log_info "Removing fstab entries..."
            cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
            sed -i '/\/mnt\/movies/d' /etc/fstab
            sed -i '/\/mnt\/tv/d' /etc/fstab
            log_info "  ✓ Updated /etc/fstab (backup created)"
        fi

        log_info "✓ Media storage cleaned up"
    else
        log_info "[DRY RUN] Would remove media and unmount drives"
    fi
else
    log_info "Preserving media storage (use --remove-media to remove)"
fi

# Summary
log_info ""
log_info "=== Uninstall Summary ==="
log_info "✓ Containers stopped"
if [[ "$PURGE" == "true" ]]; then
    log_info "✓ Docker images removed"
else
    log_info "○ Docker images preserved"
fi
if [[ "$REMOVE_CONFIG" == "true" ]]; then
    log_info "✓ Configurations removed"
else
    log_info "○ Configurations preserved in: config/, .env, ~/cloudflared/"
fi
if [[ "$REMOVE_MEDIA" == "true" ]]; then
    log_info "✓ Media storage unmounted"
else
    log_info "○ Media storage preserved"
fi

log_info ""
if [[ "$REMOVE_CONFIG" == "false" ]]; then
    log_info "To reinstall:"
    log_info "  docker compose -f compose/docker-compose.yml up -d"
    log_info ""
    log_info "To completely remove everything:"
    log_info "  $0 --purge --remove-config"
fi

log_info ""
log_info "Uninstall complete!"
