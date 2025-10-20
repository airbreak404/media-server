#!/usr/bin/env bash
# Quick HTTP endpoint checks

set -euo pipefail

echo "Checking service endpoints..."

check_endpoint() {
    local name=$1
    local url=$2

    if curl -sf --max-time 5 "$url" &>/dev/null; then
        echo "✓ $name: $url"
        return 0
    else
        echo "✗ $name: $url (not responding)"
        return 1
    fi
}

ALL_OK=true

check_endpoint "Jellyfin" "http://localhost:8096/health" || ALL_OK=false
check_endpoint "Jellyseerr" "http://localhost:5055/api/v1/status" || ALL_OK=false
check_endpoint "Sonarr" "http://localhost:8989" || ALL_OK=false
check_endpoint "Radarr" "http://localhost:7878" || ALL_OK=false
check_endpoint "Prowlarr" "http://localhost:9696" || ALL_OK=false
check_endpoint "RdtClient" "http://localhost:6500" || ALL_OK=false

echo ""

if [[ "$ALL_OK" == "true" ]]; then
    echo "All services responding!"
    exit 0
else
    echo "Some services not responding!"
    exit 1
fi
