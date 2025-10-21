#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== Phase 2 Rollback ==="
echo "Removing monitoring and alerts..."

# Remove cron job
crontab -l 2>/dev/null | grep -v "health_monitor.sh" | crontab - || true

# Remove config
rm -rf config/monitoring

echo "✓ Rollback complete"
