#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== Phase 2 Verification ==="

# Check cron
if crontab -l 2>/dev/null | grep -q "health_monitor.sh"; then
    echo "✓ Cron job configured"
else
    echo "✗ Cron job missing"
    exit 1
fi

# Check config
if [[ -d config/monitoring ]]; then
    echo "✓ Monitoring directory exists"
else
    echo "✗ Monitoring directory missing"
    exit 1
fi

echo "✓ Phase 2 verification passed"
