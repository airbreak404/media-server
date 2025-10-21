#!/usr/bin/env bash
set -Eeuo pipefail
# System Update Script (OPT-IN)
# Updates OS, Docker, and optionally containers

log_info() { echo -e "\033[0;32m[INFO]\033[0m $*"; }

log_info "=== System Update (OPT-IN) ==="

# Backup first
bash scripts/phase3/backup_advanced.sh daily

# Update OS
log_info "Updating OS..."
sudo apt update && sudo apt upgrade -y

# Update Docker
log_info "Updating Docker..."
sudo apt install --only-upgrade docker-ce docker-ce-cli containerd.io docker-compose-plugin -y || true

# Optionally update containers
if [[ "${AUTO_UPDATE_CONTAINERS:-false}" == "true" ]]; then
    log_info "Updating containers..."
    docker compose -f compose/docker-compose.yml pull
    docker compose -f compose/docker-compose.yml -f compose/docker-compose.phase1.yml pull 2>/dev/null || true
    docker compose -f compose/docker-compose.yml up -d
fi

log_info "✓ Update complete. Reboot recommended: sudo reboot"
