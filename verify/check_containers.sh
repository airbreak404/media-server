#!/usr/bin/env bash
# Quick container status check

set -euo pipefail

echo "Checking Docker containers..."

CONTAINERS=("jellyfin" "jellyseerr" "sonarr" "radarr" "prowlarr" "rdtclient" "watchtower" "cloudflared")

ALL_OK=true

for container in "${CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        STATUS=$(docker inspect --format='{{.State.Status}}' "$container")
        if [[ "$STATUS" == "running" ]]; then
            echo "✓ $container: running"
        else
            echo "✗ $container: $STATUS"
            ALL_OK=false
        fi
    else
        echo "✗ $container: not found"
        ALL_OK=false
    fi
done

echo ""

if [[ "$ALL_OK" == "true" ]]; then
    echo "All containers OK!"
    exit 0
else
    echo "Some containers have issues!"
    exit 1
fi
