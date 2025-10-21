#!/usr/bin/env bash
set -Eeuo pipefail

log_info() { echo -e "\033[0;32m[INFO]\033[0m $*"; }

log_info "=== Phase 3: Automation & Maintenance ==="
log_info "Installing: Advanced backups, Updates (opt-in), Webhooks"

# Setup cron for backups
CRON_DAILY="0 3 * * * cd $(pwd) && bash scripts/phase3/backup_advanced.sh daily"
CRON_WEEKLY="0 4 * * 0 cd $(pwd) && bash scripts/phase3/backup_advanced.sh weekly"
CRON_MONTHLY="0 5 1 * * cd $(pwd) && bash scripts/phase3/backup_advanced.sh monthly"

(crontab -l 2>/dev/null | grep -v "backup_advanced.sh" ; echo "$CRON_DAILY" ; echo "$CRON_WEEKLY" ; echo "$CRON_MONTHLY") | crontab -

log_info "✓ Backup automation configured"
log_info "  Daily:   3:00 AM"
log_info "  Weekly:  Sunday 4:00 AM"
log_info "  Monthly: 1st @ 5:00 AM"

# Ask about auto-updates
read -p "Enable automatic OS/Docker updates? (not recommended) [y/N]: " AUTO_UPDATE
if [[ $AUTO_UPDATE =~ ^[Yy]$ ]]; then
    CRON_UPDATE="0 2 * * 0 cd $(pwd) && bash scripts/phase3/system_update.sh"
    (crontab -l 2>/dev/null ; echo "$CRON_UPDATE") | crontab -
    log_info "✓ Auto-updates enabled (Sunday 2:00 AM)"
else
    log_info "✓ Auto-updates disabled (manual only)"
fi

# Setup webhook listener (optional)
read -p "Install webhook notifier for *Arr apps? [y/N]: " WEBHOOK
if [[ $WEBHOOK =~ ^[Yy]$ ]]; then
    if command -v python3 &>/dev/null; then
        # Create systemd service
        sudo bash -c "cat > /etc/systemd/system/media-webhook.service" <<'WEBHOOK_SERVICE'
[Unit]
Description=Media Server Webhook Notifier
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/python3 apps/webhook-notifier/app.py
Restart=always

[Install]
WantedBy=multi-user.target
WEBHOOK_SERVICE
        sudo systemctl enable --now media-webhook.service
        log_info "✓ Webhook notifier installed (port 8090)"
    fi
fi

bash scripts/phase3/verify.sh
log_info ""
log_info "=== Phase 3 Complete! ==="
log_info "Automation configured. Check: crontab -l"
