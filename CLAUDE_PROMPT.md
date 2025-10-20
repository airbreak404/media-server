# Automated Jellyfin Media Server on Raspberry Pi 5 — Claude Prompt

**Role:** Act as a senior DevOps/SRE paired‑programmer. Your job is to **plan, generate, and verify** a fully automated, idempotent setup for my home media server. You will produce **scripts, configs, and docs** and package them into a single downloadable archive.

## 0) Success criteria (read carefully)
- **Zero‑touch install:** Running one bootstrap command should provision everything end‑to‑end on a **Raspberry Pi 5 (16 GB RAM)** with **Raspberry Pi OS Lite 64‑bit** installed on a **256 GB USB SSD**.
- **Idempotent & safe:** Re‑running scripts must be safe. Use checks/guards; never destroy data without explicit `--force`.
- **Automated stack:** Docker + Compose services for **Jellyfin, Jellyseerr, Sonarr, Radarr, Prowlarr, RdtClient (Real‑Debrid), Watchtower, Cloudflared**.
- **Storage layout:** Two 8 TB USB HDDs mounted ext4 at `/mnt/movies` and `/mnt/tv`, plus `/mnt/movies/downloads` for temporary downloads. Persist mounts via `PARTUUID` in `/etc/fstab` with `nofail`. Ownership: **UID/GID 1000**, `chmod 775`.  
- **Networking:** **Separate subdomains** per service (e.g., `tv.example.org`, `requests.example.org`, `sonarr.example.org`, etc.) routed through **Cloudflare Tunnel** (no port‑forwarding). Cloudflared runs in Docker, uses a shared `media-net` network and ingress rules mapping hostnames → container services.
- **Containers:** Compose uses ARM64‑compatible images; set `PUID=1000`, `PGID=1000`, `TZ=America/Detroit`, and for Jellyfin mount `/dev/dri` for VAAPI. `UMASK=002` on RdtClient so *Arr apps can import.
- **Quality bar:** Provide **pre‑flight checks, post‑deploy health checks, and rollback instructions**, plus a concise **OPERATIONS.md**.
- **Deliverable:** Create a **zip/tgz** named `media-server-bundle-<date>.zip` containing all scripts/configs and documentation.

> Note: Hardware, storage mount points, Docker service list, Cloudflare Tunnel approach, and permissions reflect my requirements. Use them as the single source of truth.

---

## 1) General coding practices (apply everywhere)
- Default to **Bash** for host automation and **YAML** for Compose. Keep scripts **POSIX‑friendly** where possible.
- Put `set -Eeuo pipefail` at top of scripts; use `trap` to surface errors; add clear **logging** helpers (info/warn/error).
- **Idempotency:** Probe/skip if done (`command -v`, file exists, systemd unit present, volume mounted, etc.). Include `--dry-run` flag for any script that makes changes.
- **Inputs & secrets:** Read configs from a `.env` file; never hard‑code secrets. Accept overrides via env vars/flags.
- **Checks:** After each stage, run verifications (e.g., `docker compose ps`, HTTP health probes, Jellyfin API ping).
- **Style:** Shellcheck‑clean, descriptive function names, comments where intent isn’t obvious. Keep files small and composable.
- **Packaging:** Provide a Makefile with common targets (`make bootstrap`, `make up`, `make down`, `make verify`, `make backup`).

---

## 2) Project facts you must assume (fill placeholders where shown)
- **Domain:** `tylerhoward.org` (managed in Cloudflare).  
- **Subdomains:** Use **distinct hostnames**:  
  - `tv.tylerhoward.org` → Jellyfin (8096)  
  - `requests.tylerhoward.org` → Jellyseerr (5055)  
  - `sonarr.tylerhoward.org` → Sonarr (8989)  
  - `radarr.tylerhoward.org` → Radarr (7878)  
  - `prowlarr.tylerhoward.org` → Prowlarr (9696)  
  - (optional) `rdt.tylerhoward.org` → RdtClient (6500, if exposed)
- **Cloudflared dir & perms:** Use `~/cloudflared` and ensure it’s owned by **UID 65532** inside the container context.
- **Media paths in containers:** Jellyfin mount read‑only media: `/media/movies` and `/media/tv`. Sonarr uses `/tv`, Radarr `/movies`, both see downloads at `/data/downloads` mapped to host `/mnt/movies/downloads`.
- **Download client emulation:** RdtClient’s qBittorrent‑compatible API on port 6500, categories `sonarr` and `radarr`, and **Remote Path Mapping** from `/data/downloads/` → `/data/downloads/` in *Arr apps (path is identical to keep mapping trivial).
- **Network:** Create and use a Compose network named `media-net` shared by all services including cloudflared.

---

## 3) Files & directories to generate
Create this repo layout, then package it:
```
media-server/
├─ README.md
├─ OPERATIONS.md
├─ .env.sample
├─ compose/
│  └─ docker-compose.yml
├─ cloudflared/
│  └─ config.yml          # ingress rules; tunnel ID templated; credentials mount path
├─ scripts/
│  ├─ 00_preflight.sh
│  ├─ 01_format_and_mount_drives.sh
│  ├─ 02_install_docker.sh
│  ├─ 03_cloudflared_login_and_tunnel.sh
│  ├─ 04_generate_dns_records.md      # operator notes for Cloudflare DNS (CNAME → <TUNNEL_ID>.cfargotunnel.com)
│  ├─ 05_compose_up.sh
│  ├─ 06_configure_apps_via_api.py    # optional: Sonarr/Radarr/Prowlarr/Jellyseerr initial API wiring
│  ├─ 07_health_checks.sh
│  ├─ 90_backup.sh
│  └─ 99_uninstall.sh
├─ verify/
│  ├─ check_mounts.sh
│  ├─ check_containers.sh
│  └─ curl_checks.sh
└─ Makefile
```

---

## 4) .env variables (template values; generate `.env.sample`)
```
TZ=America/Detroit
PUID=1000
PGID=1000
UMASK=002
MOVIES_MOUNT=/mnt/movies
TV_MOUNT=/mnt/tv
DOWNLOADS_DIR=/mnt/movies/downloads

# Cloudflare Tunnel
CF_TUNNEL_NAME=media-tunnel
CF_TUNNEL_ID=<REPLACE_WITH_ID>
CF_TUNNEL_CREDENTIALS=/etc/cloudflared/<REPLACE_WITH_ID>.json
CF_DOMAIN=tylerhoward.org

# Subdomains
JELLYFIN_HOST=tv.tylerhoward.org
JELLYSEERR_HOST=requests.tylerhoward.org
SONARR_HOST=sonarr.tylerhoward.org
RADARR_HOST=radarr.tylerhoward.org
PROWLARR_HOST=prowlarr.tylerhoward.org
RDT_HOST=rdt.tylerhoward.org
```

---

## 5) docker-compose.yml requirements
- Single `media-net` network; no host‑port publishing for *Arr apps (access via Cloudflare). Expose LAN ports only where noted (Jellyfin 8096, Jellyseerr 5055, RdtClient 6500 optional).
- **Jellyfin:** `lscr.io/linuxserver/jellyfin:latest`, mount `/dev/dri`, volumes: configs under `./config/jellyfin`, media read‑only.
- **Jellyseerr:** `fallenbagel/jellyseerr:latest` with config under `./config/jellyseerr`.
- **Sonarr/Radarr/Prowlarr:** LSIO images, configs under `./config/*`, proper library/download mounts.
- **RdtClient:** `rogerfar/rdtclient:latest` with `/data/db` and `/data/downloads` mounts; `UMASK=002`.
- **Watchtower:** daily checks; cleanup old images.
- **Cloudflared:** mounts `~/cloudflared` and runs `tunnel run ${CF_TUNNEL_NAME}`.

> Compose must be ARM64‑compatible and ready to come up cleanly after reboot (drive mounts present).

---

## 6) Cloudflared config.yml (ingress)
Template the following for `cloudflared/config.yml` (use env‑expanded values where possible):
```yaml
tunnel: ${CF_TUNNEL_ID}
credentials-file: ${CF_TUNNEL_CREDENTIALS}
ingress:
  - hostname: ${JELLYFIN_HOST}
    service: http://jellyfin:8096
  - hostname: ${JELLYSEERR_HOST}
    service: http://jellyseerr:5055
  - hostname: ${SONARR_HOST}
    service: http://sonarr:8989
  - hostname: ${RADARR_HOST}
    service: http://radarr:7878
  - hostname: ${PROWLARR_HOST}
    service: http://prowlarr:9696
  # optional external UI for RdtClient; otherwise omit
  - hostname: ${RDT_HOST}
    service: http://rdtclient:6500
  - service: http_status:404
```

Also generate a short operator guide to add **CNAME** DNS records in Cloudflare for each hostname → `<CF_TUNNEL_ID>.cfargotunnel.com`.

---

## 7) Script specifications (high‑level)
- **00_preflight.sh**: Check OS/arch, sudo, disk visibility, network, and that `/mnt/movies` and `/mnt/tv` aren’t already mounted incorrectly. Print a plan; support `--fix` to remediate minor issues.
- **01_format_and_mount_drives.sh**: Non‑destructive by default. If `--format` is set, partition new disks (`/dev/sda`, `/dev/sdb`) to single ext4 partitions, `mkfs.ext4`, create mount points, mount, set ownership/permissions, fetch `PARTUUID` via `blkid`, append to `/etc/fstab` with `nofail`, then `mount -a` and verify.
- **02_install_docker.sh**: Install Docker Engine and Compose v2, add current user to `docker` group, verify with `docker run hello-world`.
- **03_cloudflared_login_and_tunnel.sh**: Run `cloudflared tunnel login` in a container, create tunnel `${CF_TUNNEL_NAME}`, capture `${CF_TUNNEL_ID}`, write `cloudflared/config.yml`, remind user to add DNS CNAMEs, then start the cloudflared service container on `media-net`.
- **05_compose_up.sh**: Create required folders (`./config/*`), generate `compose/docker-compose.yml` from template, `docker compose up -d`, wait for health, print service URLs.
- **06_configure_apps_via_api.py** (optional but preferred): 
  - Sonarr/Radarr: add **qBittorrent** client pointing to `rdtclient:6500` with credentials; set categories `sonarr`/`radarr`; add **Remote Path Mapping** `/data/downloads` → `/data/downloads`; configure root folders `/tv` and `/movies`.
  - Prowlarr: add common public/private indexers if keys provided; sync to Sonarr/Radarr via Apps API.
  - Jellyseerr: connect to Sonarr/Radarr and (optionally) Jellyfin using API keys & internal service URLs.
- **07_health_checks.sh**: Confirm mounts (`findmnt`), containers running, and HTTP probes: `/system/status` for Jellyfin, `/api/v3/system/status` for *Arr (with API keys), etc. Print a compact PASS/FAIL matrix.
- **90_backup.sh**: Tar configs under `./config/*` + `.env`, with timestamp. Document restore procedure.
- **99_uninstall.sh**: Stop containers, **do not** remove volumes by default; optionally clean images/containers with a `--purge` flag.

All scripts support `--dry-run`, `--verbose`, exit with non‑zero on failure, and print next‑step hints.

---

## 8) Post‑deploy checklist (generate as OPERATIONS.md)
- Set admin passwords in Sonarr/Radarr/Jellyseerr UIs.
- (Optional) Enable Cloudflare Access for admin subdomains.
- Verify *Arr can grab from Prowlarr, RdtClient downloads into `/data/downloads/<category>` and imports succeed.
- Play a file in Jellyfin; verify hardware decode/transcode if enabled.
- Confirm Watchtower logs; pin image tags if you prefer manual upgrades.

---

## 9) What to output to me (packaging)
1. The full project directory shown above with all files populated.
2. A single archive `media-server-bundle-<YYYYMMDD>.zip` containing the directory.
3. A short “release notes” summary of what you generated.
4. Clear **one‑line commands** for: preflight; full bootstrap; health check; backup; and safe teardown.

---

## 10) Guardrails
- Never embed my real tokens or passwords—use placeholders and `.env.sample` only.
- Don’t publish *Arr admin ports publicly unless explicitly requested (Cloudflare tunnel routes are sufficient).
- Avoid destructive disk ops without `--format` / `--force` confirmation.
- Prefer stable, official Docker images suitable for ARM64.

---

## 11) Runbook (first run)
I will:
1) Fill `.env` with my domain/tunnel IDs and API keys.  
2) Run: `sudo bash ./scripts/00_preflight.sh && sudo bash ./scripts/01_format_and_mount_drives.sh --format && sudo bash ./scripts/02_install_docker.sh && bash ./scripts/03_cloudflared_login_and_tunnel.sh && docker compose -f ./compose/docker-compose.yml up -d && bash ./scripts/07_health_checks.sh`

You should: generate everything above and hand me the archive with simple usage instructions.