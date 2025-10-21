#!/usr/bin/env bash
set -Eeuo pipefail

# Advanced Backup Script with Cloud Sync
# Supports: Local, Backblaze B2, AWS S3, Google Drive

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

TIER="${1:-daily}"  # daily, weekly, monthly
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups"
BACKUP_NAME="media-server-${TIER}-${TIMESTAMP}"

log_info "=== Advanced Backup ($TIER) ==="

mkdir -p "$BACKUP_DIR"

# What to backup based on tier
case $TIER in
    daily)
        log_info "Backing up: configs only"
        tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
            .env config/ compose/ >/dev/null 2>&1
        KEEP_DAYS=7
        ;;
    weekly)
        log_info "Backing up: configs + metadata"
        tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
            .env config/ compose/ --exclude='config/*/cache' >/dev/null 2>&1
        KEEP_DAYS=28
        ;;
    monthly)
        log_info "Backing up: full config + logs"
        tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
            .env config/ compose/ scripts/ >/dev/null 2>&1
        KEEP_DAYS=90
        ;;
    *)
        log_error "Invalid tier: $TIER"
        exit 1
        ;;
esac

BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

log_info "✓ Backup created: $BACKUP_FILE ($BACKUP_SIZE)"

# Cloud sync if configured
if [[ -f config/backup/rclone.conf ]] && command -v rclone &>/dev/null; then
    REMOTE=$(grep -m1 "type =" config/backup/rclone.conf | awk '{print $1}' | tr -d '[]')
    if [[ -n "$REMOTE" ]]; then
        log_info "Syncing to cloud: $REMOTE"
        rclone --config config/backup/rclone.conf copy "$BACKUP_FILE" "${REMOTE}:media-server-backups/" >/dev/null 2>&1 && \
            log_info "✓ Cloud sync complete" || log_warn "Cloud sync failed"
    fi
fi

# Cleanup old backups
find "$BACKUP_DIR" -name "media-server-${TIER}-*.tar.gz" -mtime +${KEEP_DAYS} -delete 2>/dev/null || true
log_info "✓ Cleanup complete (kept ${KEEP_DAYS} days)"

log_info "Backup complete: $BACKUP_FILE"
