#!/usr/bin/env bash
set -Eeuo pipefail

# Phase 2 Installation: Monitoring & Alerting
# Adds: Health monitoring, Alerts, Metrics collection

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

trap 'log_error "Phase 2 installation failed at line $LINENO"' ERR

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Install Phase 2: Monitoring & Alerting"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done"
            echo "  --help       Show this message"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

log_info "=== Phase 2: Monitoring & Alerting Installation ==="
log_info ""
log_info "This will add:"
log_info "  • Health monitoring daemon (runs every 5 minutes)"
log_info "  • Multi-channel alerting (ntfy/Discord/Telegram/Email)"
log_info "  • Metrics collection (disk, temp, containers)"
log_info ""

if [[ "$DRY_RUN" == "false" ]]; then
    read -p "Choose notification method [ntfy/discord/telegram/email/none]: " NOTIFICATION_METHOD
fi

log_step "[1/5] Creating monitoring directories..."
mkdir -p config/monitoring/metrics
mkdir -p config/monitoring/logs
log_info "✓ Directories created"

log_step "[2/5] Configuring monitoring..."
cat > config/monitoring/monitor_config.sh <<'EOF'
# Monitoring Configuration
ALERT_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/../../scripts/phase2/send_alert.sh"
METRICS_DIR="$(dirname "${BASH_SOURCE[0]}")/metrics"
STATE_FILE="$(dirname "${BASH_SOURCE[0]}")/health_state.txt"
QUIET_MODE=true
EOF

log_step "[3/5] Configuring alerts..."
if [[ "$DRY_RUN" == "false" ]]; then
    case ${NOTIFICATION_METHOD:-none} in
        ntfy)
            read -p "Enter ntfy topic name [media-server-alerts]: " NTFY_TOPIC
            NTFY_TOPIC=${NTFY_TOPIC:-media-server-alerts}
            cat > config/monitoring/alert_config.sh <<EOF
# Alert Configuration
NTFY_TOPIC="${NTFY_TOPIC}"
NTFY_SERVER="https://ntfy.sh"
EOF
            log_info "✓ ntfy.sh configured. Subscribe at: https://ntfy.sh/${NTFY_TOPIC}"
            ;;
        discord)
            read -p "Enter Discord webhook URL: " DISCORD_WEBHOOK
            cat > config/monitoring/alert_config.sh <<EOF
# Alert Configuration
DISCORD_WEBHOOK="${DISCORD_WEBHOOK}"
EOF
            log_info "✓ Discord configured"
            ;;
        telegram)
            read -p "Enter Telegram bot token: " TELEGRAM_BOT_TOKEN
            read -p "Enter Telegram chat ID: " TELEGRAM_CHAT_ID
            cat > config/monitoring/alert_config.sh <<EOF
# Alert Configuration
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
EOF
            log_info "✓ Telegram configured"
            ;;
        email)
            read -p "Enter email address: " EMAIL_TO
            cat > config/monitoring/alert_config.sh <<EOF
# Alert Configuration
EMAIL_TO="${EMAIL_TO}"
EOF
            log_info "✓ Email configured"
            ;;
        *)
            touch config/monitoring/alert_config.sh
            log_info "✓ Notifications disabled"
            ;;
    esac
fi

log_step "[4/5] Setting up cron job..."
if [[ "$DRY_RUN" == "false" ]]; then
    MEDIA_SERVER_DIR="$(pwd)"
    CRON_CMD="*/5 * * * * cd ${MEDIA_SERVER_DIR} && bash scripts/phase2/health_monitor.sh >> config/monitoring/logs/monitor.log 2>&1"

    (crontab -l 2>/dev/null | grep -v "health_monitor.sh" ; echo "$CRON_CMD") | crontab -
    log_info "✓ Cron job added (runs every 5 minutes)"
fi

log_step "[5/5] Running initial health check..."
if [[ "$DRY_RUN" == "false" ]]; then
    bash scripts/phase2/health_monitor.sh
    bash scripts/phase2/verify.sh
fi

log_info ""
log_info "=== Phase 2 Installation Complete! ==="
log_info ""
log_info "Monitoring active:"
log_info "  ✓ Health checks run every 5 minutes"
log_info "  ✓ Alerts sent on state changes"
log_info "  ✓ Metrics stored in config/monitoring/metrics/"
log_info ""
log_info "View logs: tail -f config/monitoring/logs/monitor.log"
log_info "Test alert: bash scripts/phase2/test_alert.sh"
log_info ""
log_info "Next: make phase-3"
