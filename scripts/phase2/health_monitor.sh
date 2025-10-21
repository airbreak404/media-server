#!/usr/bin/env bash
set -Eeuo pipefail

# Health Monitor Daemon for Media Server
# Runs periodic checks and sends alerts on failures
# Designed to run via cron every 5 minutes

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/monitoring/monitor_config.sh"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Defaults
ALERT_SCRIPT="${ALERT_SCRIPT:-${SCRIPT_DIR}/send_alert.sh}"
METRICS_DIR="${METRICS_DIR:-${SCRIPT_DIR}/../../config/monitoring/metrics}"
STATE_FILE="${STATE_FILE:-${SCRIPT_DIR}/../../config/monitoring/health_state.txt}"
QUIET_MODE="${QUIET_MODE:-false}"

# Create directories
mkdir -p "$METRICS_DIR"
mkdir -p "$(dirname "$STATE_FILE")"

# Logging
log() {
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    fi
}

# Alert function
send_alert() {
    local severity=$1
    local title=$2
    local message=$3

    if [[ -x "$ALERT_SCRIPT" ]]; then
        bash "$ALERT_SCRIPT" "$severity" "$title" "$message"
    fi
}

# Get previous state
get_previous_state() {
    local check_name=$1
    grep "^${check_name}:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 || echo "unknown"
}

# Save current state
save_state() {
    local check_name=$1
    local state=$2

    # Remove old entry
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${check_name}:" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi

    # Add new entry
    echo "${check_name}:${state}" >> "$STATE_FILE"
}

# Alert only on state change
alert_on_change() {
    local check_name=$1
    local current_state=$2
    local severity=$3
    local title=$4
    local message=$5

    local previous_state
    previous_state=$(get_previous_state "$check_name")

    if [[ "$previous_state" != "$current_state" ]]; then
        send_alert "$severity" "$title" "$message"
        save_state "$check_name" "$current_state"
    fi
}

log "Starting health checks..."

# Check 1: Cloudflare Tunnel
log "Checking Cloudflare Tunnel..."
if docker ps --format '{{.Names}}' | grep -q "^cloudflared$"; then
    if docker logs cloudflared 2>&1 | tail -20 | grep -q "Registered tunnel connection"; then
        log "✓ Cloudflare Tunnel connected"
        alert_on_change "cloudflared" "healthy" "info" "Cloudflare Tunnel Restored" "Tunnel connection re-established"
    else
        log "✗ Cloudflare Tunnel not connected"
        alert_on_change "cloudflared" "unhealthy" "critical" "Cloudflare Tunnel Down" "Tunnel is not connected. Services may be inaccessible."
    fi
else
    log "✗ Cloudflare Tunnel container not running"
    alert_on_change "cloudflared" "stopped" "critical" "Cloudflare Tunnel Stopped" "Container is not running!"
fi

# Check 2: Disk Space
log "Checking disk space..."
MOVIES_USAGE=$(df /mnt/movies 2>/dev/null | awk 'NR==2 {print int($5)}' || echo "0")
TV_USAGE=$(df /mnt/tv 2>/dev/null | awk 'NR==2 {print int($5)}' || echo "0")

echo "$(date +%s),${MOVIES_USAGE},${TV_USAGE}" >> "$METRICS_DIR/disk_usage.log"

if [[ $MOVIES_USAGE -gt 90 ]]; then
    alert_on_change "disk_movies" "critical" "critical" "Disk Space Critical" "/mnt/movies is ${MOVIES_USAGE}% full!"
elif [[ $MOVIES_USAGE -gt 85 ]]; then
    alert_on_change "disk_movies" "warning" "warning" "Disk Space Warning" "/mnt/movies is ${MOVIES_USAGE}% full"
else
    alert_on_change "disk_movies" "healthy" "info" "Disk Space OK" "/mnt/movies usage back to normal"
fi

if [[ $TV_USAGE -gt 90 ]]; then
    alert_on_change "disk_tv" "critical" "critical" "Disk Space Critical" "/mnt/tv is ${TV_USAGE}% full!"
elif [[ $TV_USAGE -gt 85 ]]; then
    alert_on_change "disk_tv" "warning" "warning" "Disk Space Warning" "/mnt/tv is ${TV_USAGE}% full"
else
    alert_on_change "disk_tv" "healthy" "info" "Disk Space OK" "/mnt/tv usage back to normal"
fi

# Check 3: Container Health
log "Checking containers..."
EXPECTED_CONTAINERS=("jellyfin" "jellyseerr" "sonarr" "radarr" "prowlarr" "rdtclient" "watchtower" "cloudflared")

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        RESTART_COUNT=$(docker inspect --format='{{.RestartCount}}' "$container")

        if [[ $RESTART_COUNT -gt 5 ]]; then
            alert_on_change "container_${container}_restarts" "critical" "critical" "Container Restarting" "${container} has restarted ${RESTART_COUNT} times!"
        elif [[ $RESTART_COUNT -gt 3 ]]; then
            alert_on_change "container_${container}_restarts" "warning" "warning" "Container Issues" "${container} has restarted ${RESTART_COUNT} times"
        else
            alert_on_change "container_${container}" "running" "info" "${container} Running" "Container is back online"
        fi
    else
        log "✗ Container $container not running"
        alert_on_change "container_${container}" "stopped" "critical" "Container Stopped" "${container} is not running!"
    fi
done

# Check 4: System Temperature (Raspberry Pi specific)
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP / 1000))

    echo "$(date +%s),${TEMP_C}" >> "$METRICS_DIR/temperature.log"

    if [[ $TEMP_C -gt 80 ]]; then
        alert_on_change "temperature" "critical" "critical" "High Temperature" "CPU temperature is ${TEMP_C}°C! Risk of throttling."
    elif [[ $TEMP_C -gt 70 ]]; then
        alert_on_change "temperature" "warning" "warning" "Elevated Temperature" "CPU temperature is ${TEMP_C}°C"
    else
        alert_on_change "temperature" "normal" "info" "Temperature Normal" "CPU temperature back to normal"
    fi

    log "Temperature: ${TEMP_C}°C"
fi

# Check 5: Internet Connectivity
log "Checking internet connectivity..."
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    alert_on_change "internet" "connected" "info" "Internet Restored" "Internet connectivity restored"
else
    log "✗ No internet connectivity"
    alert_on_change "internet" "disconnected" "critical" "Internet Down" "No internet connectivity detected!"
fi

# Cleanup old metrics (keep 30 days)
find "$METRICS_DIR" -name "*.log" -type f -mtime +30 -delete 2>/dev/null || true

log "Health checks complete"
