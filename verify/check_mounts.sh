#!/usr/bin/env bash
# Quick mount point verification

set -euo pipefail

source .env 2>/dev/null || true

MOVIES_MOUNT="${MOVIES_MOUNT:-/mnt/movies}"
TV_MOUNT="${TV_MOUNT:-/mnt/tv}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-/mnt/movies/downloads}"

echo "Checking mount points..."

if mountpoint -q "$MOVIES_MOUNT"; then
    echo "✓ Movies mounted: $MOVIES_MOUNT"
    df -h "$MOVIES_MOUNT"
else
    echo "✗ Movies NOT mounted: $MOVIES_MOUNT"
    exit 1
fi

if mountpoint -q "$TV_MOUNT"; then
    echo "✓ TV mounted: $TV_MOUNT"
    df -h "$TV_MOUNT"
else
    echo "✗ TV NOT mounted: $TV_MOUNT"
    exit 1
fi

if [[ -d "$DOWNLOADS_DIR" ]]; then
    echo "✓ Downloads directory exists: $DOWNLOADS_DIR"
else
    echo "✗ Downloads directory missing: $DOWNLOADS_DIR"
    exit 1
fi

echo ""
echo "All mount points OK!"
