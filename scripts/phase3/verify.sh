#!/usr/bin/env bash
echo "=== Phase 3 Verification ==="
if crontab -l 2>/dev/null | grep -q "backup_advanced.sh"; then
    echo "✓ Backup automation configured"
else
    echo "✗ Backup automation missing"; exit 1
fi
echo "✓ Phase 3 verification passed"
