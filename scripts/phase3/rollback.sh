#!/usr/bin/env bash
echo "=== Phase 3 Rollback ==="
crontab -l 2>/dev/null | grep -v "backup_advanced.sh" | grep -v "system_update.sh" | crontab - || true
sudo systemctl disable --now media-webhook.service 2>/dev/null || true
echo "✓ Rollback complete"
