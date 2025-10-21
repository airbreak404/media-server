#!/usr/bin/env bash
# Quick test to verify both Tailscale and Cloudflare Tunnel are working

set -euo pipefail

echo "=== Network Connectivity Test ==="
echo ""

# Test 1: Internet connectivity
echo "[1/4] Testing internet connectivity..."
if ping -c 2 8.8.8.8 &>/dev/null; then
    echo "✓ Internet: OK"
else
    echo "✗ Internet: FAILED"
    exit 1
fi

# Test 2: Cloudflare Tunnel status
echo "[2/4] Testing Cloudflare Tunnel..."
if docker ps | grep -q cloudflared; then
    if docker logs cloudflared 2>&1 | tail -20 | grep -q "Registered tunnel connection"; then
        echo "✓ Cloudflare Tunnel: Connected"
    else
        echo "⚠ Cloudflare Tunnel: Running but may not be connected"
    fi
else
    echo "✗ Cloudflare Tunnel: Not running"
fi

# Test 3: Tailscale status (if installed)
echo "[3/4] Testing Tailscale..."
if command -v tailscale &>/dev/null; then
    if tailscale status &>/dev/null; then
        TS_IP=$(tailscale ip -4 2>/dev/null)
        echo "✓ Tailscale: Connected ($TS_IP)"
    else
        echo "✗ Tailscale: Installed but not connected"
    fi
else
    echo "○ Tailscale: Not installed"
fi

# Test 4: Docker networking
echo "[4/4] Testing Docker networking..."
if docker network inspect media-net &>/dev/null; then
    CONTAINER_COUNT=$(docker network inspect media-net --format '{{len .Containers}}')
    echo "✓ Docker network 'media-net': $CONTAINER_COUNT containers"
else
    echo "✗ Docker network 'media-net': Not found"
fi

echo ""
echo "=== Routing Table ==="
ip route show | head -5

echo ""
echo "=== DNS Configuration ==="
cat /etc/resolv.conf | grep nameserver

echo ""
echo "Network test complete!"
