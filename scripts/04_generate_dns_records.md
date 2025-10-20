# Cloudflare DNS Configuration Guide

After creating your Cloudflare Tunnel, you must add DNS records to route your subdomains through the tunnel.

## Prerequisites

- Cloudflare Tunnel created (run `./scripts/03_cloudflared_login_and_tunnel.sh`)
- Your domain (`tylerhoward.org`) managed in Cloudflare
- Tunnel ID from `.env` file or script output

## Finding Your Tunnel ID

Check your `.env` file:
```bash
grep CF_TUNNEL_ID .env
```

Or check the credentials file:
```bash
ls ~/cloudflared/*.json
```

The filename (without `.json`) is your tunnel ID.

## Adding DNS Records

### Option 1: Cloudflare Dashboard (Recommended)

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain: `tylerhoward.org`
3. Navigate to **DNS** → **Records**
4. For each subdomain, add a **CNAME** record:

| Type  | Name     | Target                              | Proxy Status | TTL  |
|-------|----------|-------------------------------------|--------------|------|
| CNAME | tv       | `<TUNNEL_ID>.cfargotunnel.com`      | Proxied      | Auto |
| CNAME | requests | `<TUNNEL_ID>.cfargotunnel.com`      | Proxied      | Auto |
| CNAME | sonarr   | `<TUNNEL_ID>.cfargotunnel.com`      | Proxied      | Auto |
| CNAME | radarr   | `<TUNNEL_ID>.cfargotunnel.com`      | Proxied      | Auto |
| CNAME | prowlarr | `<TUNNEL_ID>.cfargotunnel.com`      | Proxied      | Auto |
| CNAME | rdt      | `<TUNNEL_ID>.cfargotunnel.com`      | Proxied      | Auto |

**Important:**
- Replace `<TUNNEL_ID>` with your actual tunnel ID
- Set **Proxy status** to **Proxied** (orange cloud) for Cloudflare protection
- TTL should be set to **Auto**

### Option 2: Using Cloudflare API

If you have the Cloudflare API token, you can automate this:

```bash
# Set your API token and Zone ID
export CF_API_TOKEN="your-api-token"
export CF_ZONE_ID="your-zone-id"
export CF_TUNNEL_ID="your-tunnel-id"

# Array of subdomains
SUBDOMAINS=("tv" "requests" "sonarr" "radarr" "prowlarr" "rdt")

# Add CNAME records
for subdomain in "${SUBDOMAINS[@]}"; do
  curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{
      \"type\": \"CNAME\",
      \"name\": \"${subdomain}\",
      \"content\": \"${CF_TUNNEL_ID}.cfargotunnel.com\",
      \"proxied\": true,
      \"ttl\": 1
    }"
done
```

### Option 3: Using Cloudflare CLI (`cloudflared`)

```bash
# Source your tunnel ID
source .env

# Add DNS routes
cloudflared tunnel route dns ${CF_TUNNEL_NAME} tv.tylerhoward.org
cloudflared tunnel route dns ${CF_TUNNEL_NAME} requests.tylerhoward.org
cloudflared tunnel route dns ${CF_TUNNEL_NAME} sonarr.tylerhoward.org
cloudflared tunnel route dns ${CF_TUNNEL_NAME} radarr.tylerhoward.org
cloudflared tunnel route dns ${CF_TUNNEL_NAME} prowlarr.tylerhoward.org
cloudflared tunnel route dns ${CF_TUNNEL_NAME} rdt.tylerhoward.org
```

## Verification

After adding DNS records:

1. Wait 1-2 minutes for DNS propagation
2. Verify DNS resolution:
   ```bash
   nslookup tv.tylerhoward.org
   dig requests.tylerhoward.org
   ```

3. Check that the CNAME points to your tunnel:
   ```bash
   dig tv.tylerhoward.org CNAME +short
   ```
   Should return: `<TUNNEL_ID>.cfargotunnel.com`

## Service Mapping

Your subdomains will route to these services:

| Subdomain                   | Service    | Internal Port | Purpose                    |
|-----------------------------|------------|---------------|----------------------------|
| tv.tylerhoward.org          | Jellyfin   | 8096          | Media streaming            |
| requests.tylerhoward.org    | Jellyseerr | 5055          | Media requests             |
| sonarr.tylerhoward.org      | Sonarr     | 8989          | TV show management         |
| radarr.tylerhoward.org      | Radarr     | 7878          | Movie management           |
| prowlarr.tylerhoward.org    | Prowlarr   | 9696          | Indexer management         |
| rdt.tylerhoward.org         | RdtClient  | 6500          | Download client (optional) |

## Security Recommendations

1. **Enable Cloudflare Access** (optional but recommended):
   - Protect admin interfaces (Sonarr, Radarr, Prowlarr)
   - Keep Jellyfin and Jellyseerr open for users

2. **Set up WAF rules**:
   - Block common attack patterns
   - Rate limit requests

3. **Enable HTTPS enforcement**:
   - Cloudflare automatically provides SSL
   - Tunnel uses secure connection to origin

## Troubleshooting

### DNS not resolving
- Check that records are set to **Proxied** (orange cloud)
- Wait up to 5 minutes for DNS propagation
- Clear your local DNS cache: `sudo systemd-resolve --flush-caches`

### Tunnel not accessible
- Ensure cloudflared container is running: `docker ps | grep cloudflared`
- Check cloudflared logs: `docker logs cloudflared`
- Verify tunnel status in Cloudflare dashboard

### 502/504 errors
- Ensure backend services are running
- Check that service names in `config.yml` match container names
- Verify containers are on the `media-net` network

## Next Steps

After DNS records are configured:

```bash
./scripts/05_compose_up.sh
```

This will bring up all services and make them accessible via your subdomains.
