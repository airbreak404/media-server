# Adding Tailscale to Media Server

Guide for safely adding Tailscale SSH access without breaking Cloudflare Tunnel.

## Prerequisites

- Media server fully deployed and working
- Cloudflare Tunnel connected
- Health checks passing: `make health`

## Installation Steps

### 1. Capture Baseline

```bash
cd ~/media-server

# Run health checks
make health

# Save current network state
mkdir -p baseline
ip route show > baseline/routes-before.txt
cat /etc/resolv.conf > baseline/dns-before.txt
docker logs cloudflared | tail -50 > baseline/cloudflared-before.txt
```

### 2. Install Tailscale

```bash
# Install
curl -fsSL https://tailscale.com/install.sh | sh

# DO NOT run 'tailscale up' yet!
```

### 3. Configure Tailscale (CRITICAL FLAGS)

```bash
# Start Tailscale with safe settings
sudo tailscale up \
  --accept-routes=false \
  --advertise-exit-node=false \
  --accept-dns=false \
  --ssh

# Authenticate via the URL it provides
```

**Flag explanations:**
- `--accept-routes=false` - Don't accept subnet routes from other nodes
- `--advertise-exit-node=false` - Don't act as exit node
- `--accept-dns=false` - **CRITICAL** - Don't use Tailscale DNS
- `--ssh` - Enable Tailscale SSH access

### 4. Verify Tailscale Didn't Break Anything

```bash
# Check Tailscale is connected
tailscale status

# Get your Tailscale IP
tailscale ip -4

# CRITICAL: Check default route didn't change
ip route show | grep default
# Should still point to your LAN gateway (192.168.x.1), NOT 100.x.x.x

# Check DNS didn't change
cat /etc/resolv.conf
# Should NOT have 100.100.100.100

# Test Cloudflare Tunnel
docker logs cloudflared | tail -20 | grep "Registered tunnel"
# Should see: "Registered tunnel connection"
```

### 5. Run Health Checks

```bash
# Full health check
make health

# Network-specific check
bash verify/check_network.sh

# All checks should PASS
```

### 6. Test SSH via Tailscale

```bash
# From another device with Tailscale installed:
ssh pi@100.x.x.x  # Use your Tailscale IP

# Or use machine name:
ssh pi@raspberry-pi
```

## Troubleshooting

### Cloudflare Tunnel Lost Connection

**Symptom:**
```
docker logs cloudflared
# Error: dial tcp: lookup connection errors
```

**Fix:**
```bash
# Option 1: Restart with host DNS
docker compose -f compose/docker-compose.yml restart cloudflared

# Option 2: Disable Tailscale temporarily
sudo tailscale down
docker compose -f compose/docker-compose.yml restart cloudflared
sudo tailscale up --accept-routes=false --accept-dns=false --ssh

# Option 3: Set explicit DNS in Docker
# Edit compose/docker-compose.yml, add to cloudflared:
dns:
  - 1.1.1.1
  - 1.0.0.1
```

### Services Can't Resolve Each Other

**Symptom:**
```
docker exec sonarr curl http://radarr:7878
# curl: (6) Could not resolve host: radarr
```

**Fix:**
```bash
# Restart Docker networking
docker compose -f compose/docker-compose.yml down
docker compose -f compose/docker-compose.yml up -d
```

### Default Route Changed

**Symptom:**
```bash
ip route show | grep default
# default via 100.x.x.x dev tailscale0  # WRONG!
```

**Fix:**
```bash
# Reconfigure Tailscale
sudo tailscale down
sudo tailscale up --accept-routes=false --advertise-exit-node=false --accept-dns=false --ssh
```

## Rollback Procedure

If Tailscale breaks your setup:

```bash
# 1. Stop Tailscale
sudo tailscale down

# 2. Disable Tailscale service
sudo systemctl stop tailscaled
sudo systemctl disable tailscaled

# 3. Restart Docker services
docker compose -f compose/docker-compose.yml restart

# 4. Verify everything works
make health

# 5. If still broken, reboot
sudo reboot
```

## Recommended Access Patterns

**For SSH:**
- Via Tailscale: `ssh pi@100.x.x.x` ✅ PREFERRED
- Via LAN: `ssh pi@192.168.x.x` ✅ Works
- Via Internet: Not exposed ⛔

**For Services:**
- Public: `https://tv.tylerhoward.org` ✅ PREFERRED (Cloudflare Tunnel)
- LAN: `http://192.168.x.x:8096` ✅ Works
- Tailscale: `http://100.x.x.x:8096` ✅ Works but redundant

## Making Tailscale Persistent

Once verified working, make config persistent:

```bash
# Enable Tailscale service
sudo systemctl enable tailscaled

# Configure to start with safe settings
echo 'tailscale up --accept-routes=false --advertise-exit-node=false --accept-dns=false --ssh' | \
  sudo tee /etc/rc.local
sudo chmod +x /etc/rc.local
```

## Monitoring

Add to your regular health checks:

```bash
# Check both are working
make health && bash verify/check_network.sh
```

---

**Important Notes:**

1. **Never enable `--accept-dns=true`** - This will break Docker DNS
2. **Never enable exit node mode** - Unnecessary for SSH
3. **Always test after Tailscale updates** - Updates can reset settings
4. **Keep Cloudflare Tunnel as primary** - Tailscale is backup/admin access

## Summary

✅ Safe to use Tailscale for SSH access
✅ Must disable Tailscale DNS
✅ Must not use as exit node
✅ Cloudflare Tunnel remains primary access method
✅ Both can coexist happily with proper configuration
