#!/usr/bin/env bash
set -Eeuo pipefail

# Alert Notification Sender
# Supports: ntfy.sh, Discord, Telegram, Email
# Usage: send_alert.sh <severity> <title> <message>

SEVERITY="$1"
TITLE="$2"
MESSAGE="$3"

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/monitoring/alert_config.sh"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Get emoji for severity
get_emoji() {
    case $1 in
        critical) echo "🚨" ;;
        warning) echo "⚠️" ;;
        info) echo "ℹ️" ;;
        *) echo "📢" ;;
    esac
}

# Get priority for ntfy
get_priority() {
    case $1 in
        critical) echo "5" ;;
        warning) echo "4" ;;
        info) echo "3" ;;
        *) echo "3" ;;
    esac
}

EMOJI=$(get_emoji "$SEVERITY")
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Send via ntfy.sh
send_ntfy() {
    if [[ -z "${NTFY_TOPIC:-}" ]]; then
        return
    fi

    local ntfy_server="${NTFY_SERVER:-https://ntfy.sh}"
    local priority=$(get_priority "$SEVERITY")

    curl -s -X POST "${ntfy_server}/${NTFY_TOPIC}" \
        -H "Title: ${EMOJI} ${TITLE}" \
        -H "Priority: ${priority}" \
        -H "Tags: ${SEVERITY},media-server" \
        -d "${MESSAGE}

Host: ${HOSTNAME}
Time: ${TIMESTAMP}" >/dev/null 2>&1 || true
}

# Send via Discord
send_discord() {
    if [[ -z "${DISCORD_WEBHOOK:-}" ]]; then
        return
    fi

    local color
    case $SEVERITY in
        critical) color="15158332" ;;  # Red
        warning) color="16776960" ;;   # Yellow
        info) color="3447003" ;;       # Blue
        *) color="9807270" ;;          # Gray
    esac

    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "${EMOJI} ${TITLE}",
    "description": "${MESSAGE}",
    "color": ${color},
    "fields": [
      {"name": "Host", "value": "${HOSTNAME}", "inline": true},
      {"name": "Severity", "value": "${SEVERITY}", "inline": true}
    ],
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)

    curl -s -X POST "${DISCORD_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null 2>&1 || true
}

# Send via Telegram
send_telegram() {
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        return
    fi

    local text="${EMOJI} *${TITLE}*

${MESSAGE}

Host: \`${HOSTNAME}\`
Time: ${TIMESTAMP}"

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${text}" \
        -d "parse_mode=Markdown" >/dev/null 2>&1 || true
}

# Send via Email
send_email() {
    if [[ -z "${EMAIL_TO:-}" ]]; then
        return
    fi

    local subject="${EMOJI} ${TITLE} - ${HOSTNAME}"
    local body="Media Server Alert

Title: ${TITLE}
Severity: ${SEVERITY}
Message: ${MESSAGE}

Host: ${HOSTNAME}
Time: ${TIMESTAMP}

---
This is an automated alert from your media server monitoring system.
"

    if command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" "$EMAIL_TO" 2>/dev/null || true
    fi
}

# Send to all configured channels
send_ntfy
send_discord
send_telegram
send_email

# Log to syslog
logger -t media-server-monitor "[${SEVERITY}] ${TITLE}: ${MESSAGE}"
