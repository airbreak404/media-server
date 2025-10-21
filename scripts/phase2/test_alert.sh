#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Sending test alert..."
bash "$SCRIPT_DIR/send_alert.sh" "info" "Test Alert" "This is a test notification from your media server."
echo "✓ Test alert sent. Check your notification channel."
