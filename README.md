# Media Server (Raspberry Pi 5) — Bootstrap Repo

Tiny starter repo so Claude can take it from here.

## What this repo is for
- Host the **prompt/spec** for an automated media-server stack on **Raspberry Pi 5**.
- Let **Claude** generate the full project (scripts, Compose, Cloudflare Tunnel config, etc.) via a PR.
- Keep history, reviews, and easy updates.

## How to start (super simple)
1. Add `CLAUDE_PROMPT.md` (use the one I provided).
2. In Claude, authorize GitHub → open this repo → say:
   > “Use `CLAUDE_PROMPT.md` as the spec. Create branch `feat/bootstrap`. Generate the full project (scripts, compose, cloudflared config, `.env.sample`, `OPERATIONS.md`). Open a PR.”
3. Review/merge the PR, then follow the generated `OPERATIONS.md` for setup.

## Subdomains (Cloudflare Tunnel)
- `tv.tylerhoward.org` (Jellyfin)
- `requests.tylerhoward.org` (Jellyseerr)
- `sonarr.tylerhoward.org` (Sonarr)
- `radarr.tylerhoward.org` (Radarr)
- `prowlarr.tylerhoward.org` (Prowlarr)
- *(optional)* `rdt.tylerhoward.org` (RdtClient)

## Conventions
- **No secrets in git**: keep `.env` local; PRs should only include `.env.sample`.
- Branch format: `feat/*`, `fix/*`, `chore/*`.
- PRs should include a brief checklist and test notes.

---
*Next step:* commit this README and the `.gitignore` below, push, then let Claude open the first PR.
