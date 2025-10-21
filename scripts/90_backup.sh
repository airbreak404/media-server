#!/usr/bin/env bash
set -Eeuo pipefail

# Backup media server configuration
# Creates timestamped archive of configs and credentials

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
BACKUP_DIR="${BACKUP_DIR:-./backups}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run         Show what would be backed up"
            echo "  --backup-dir DIR  Backup directory (default: ./backups)"
            echo "  --verbose         Show detailed output"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/media-server-backup-${TIMESTAMP}.tar.gz"

log_info "=== Media Server Backup ==="
log_info "Backup file: $BACKUP_FILE"
log_info ""

# Create backup directory
if [[ ! -d "$BACKUP_DIR" ]]; then
    log_info "Creating backup directory: $BACKUP_DIR"
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$BACKUP_DIR"
    fi
fi

log_info "[1/3] Preparing backup contents..."

# Files and directories to backup
BACKUP_ITEMS=(
    ".env"
    "compose/docker-compose.yml"
    "cloudflared/config.yml"
    "config/"
)

# Add cloudflared credentials if they exist
if [[ -d "${HOME}/cloudflared" ]]; then
    CLOUDFLARED_DIR="${HOME}/cloudflared"
    log_info "  Including Cloudflare Tunnel credentials from $CLOUDFLARED_DIR"
fi

# Check what exists
log_info "Backup contents:"
for item in "${BACKUP_ITEMS[@]}"; do
    if [[ -e "$item" ]]; then
        if [[ -d "$item" ]]; then
            SIZE=$(du -sh "$item" 2>/dev/null | awk '{print $1}')
            log_info "  ✓ $item/ ($SIZE)"
        else
            SIZE=$(du -h "$item" 2>/dev/null | awk '{print $1}')
            log_info "  ✓ $item ($SIZE)"
        fi
    else
        log_warn "  ⚠ $item (not found, skipping)"
    fi
done

log_info "[2/3] Creating backup archive..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Create temporary directory for staging
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    # Copy items to staging directory
    for item in "${BACKUP_ITEMS[@]}"; do
        if [[ -e "$item" ]]; then
            if [[ -d "$item" ]]; then
                mkdir -p "$TEMP_DIR/$(dirname "$item")"
                cp -r "$item" "$TEMP_DIR/$item"
            else
                mkdir -p "$TEMP_DIR/$(dirname "$item")"
                cp "$item" "$TEMP_DIR/$item"
            fi
        fi
    done

    # Copy cloudflared credentials if they exist
    if [[ -d "${CLOUDFLARED_DIR:-}" ]]; then
        mkdir -p "$TEMP_DIR/cloudflared-credentials"
        cp -r "$CLOUDFLARED_DIR"/* "$TEMP_DIR/cloudflared-credentials/" 2>/dev/null || true
    fi

    # Create backup metadata
    cat > "$TEMP_DIR/backup-info.txt" <<EOF
Media Server Backup
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Hostname: $(hostname)
System: $(uname -a)

Backed up items:
$(for item in "${BACKUP_ITEMS[@]}"; do [[ -e "$item" ]] && echo "  - $item"; done)

Container status at backup time:
$(docker compose -f compose/docker-compose.yml ps 2>/dev/null || echo "N/A")

Restore instructions:
1. Extract this archive to the media-server directory
2. Restore .env and compose/docker-compose.yml
3. Restore config/ directory
4. Restore cloudflared credentials to ~/cloudflared/
5. Run: docker compose -f compose/docker-compose.yml up -d
EOF

    # Create tarball
    tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" .

    log_info "✓ Backup created: $BACKUP_FILE"

    # Show backup size
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | awk '{print $1}')
    log_info "  Size: $BACKUP_SIZE"
else
    log_info "[DRY RUN] Would create backup: $BACKUP_FILE"
fi

log_info "[3/3] Cleanup old backups..."
# Keep only last 7 backups
if [[ "$DRY_RUN" == "false" ]]; then
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/media-server-backup-*.tar.gz 2>/dev/null | wc -l)
    if [[ $BACKUP_COUNT -gt 7 ]]; then
        log_info "Removing old backups (keeping 7 most recent)..."
        ls -1t "$BACKUP_DIR"/media-server-backup-*.tar.gz | tail -n +8 | xargs rm -f
        REMOVED=$((BACKUP_COUNT - 7))
        log_info "✓ Removed $REMOVED old backup(s)"
    else
        log_info "No old backups to remove (found $BACKUP_COUNT)"
    fi
else
    log_info "[DRY RUN] Would cleanup old backups"
fi

log_info ""
log_info "✓ Backup complete!"
log_info ""
log_info "Restore instructions:"
log_info "  1. Stop services: docker compose -f compose/docker-compose.yml down"
log_info "  2. Extract backup: tar -xzf $BACKUP_FILE"
log_info "  3. Restore cloudflared: cp -r cloudflared-credentials/* ~/cloudflared/"
log_info "  4. Start services: docker compose -f compose/docker-compose.yml up -d"
log_info ""
log_info "Available backups:"
if [[ -d "$BACKUP_DIR" ]]; then
    ls -lh "$BACKUP_DIR"/media-server-backup-*.tar.gz 2>/dev/null | tail -5 || log_info "  No backups found"
fi
