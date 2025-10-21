# Phased Deployment Guide

Safe, incremental deployment of media server features.

## Overview

The media server uses a **phased deployment strategy** to safely add features over time:

- **Phase 0 (Bootstrap)**: Core media services
- **Phase 1**: Foundation enhancements
- **Phase 2**: Monitoring & alerting
- **Phase 3**: Automation & maintenance

Each phase:
✅ Is independently testable
✅ Can be rolled back safely
✅ Doesn't break previous phases
✅ Has verification built-in

---

## Phase 0: Bootstrap (Core System)

**What you get:**
- Jellyfin, Jellyseerr, Sonarr, Radarr, Prowlarr
- RdtClient (Real-Debrid)
- Cloudflare Tunnel
- Tailscale SSH (optional)
- Watchtower

**Deploy:**
```bash
make bootstrap
```

**Test for:** 24-48 hours

---

## Phase 1: Foundation Services

**What gets added:**
- **Bazarr** - Automatic subtitle downloads
- **Caddy** - HTTPS reverse proxy for LAN
- **Homer** - Beautiful dashboard
- **Performance optimization** - System tuning

**Why now:** Essential quality-of-life improvements, low risk

**Deploy:**
```bash
make phase-1
```

**New access:**
- Dashboard: `http://[PI_IP]:8080`
- HTTPS via Caddy: `https://pi.local:8443`
- Bazarr: `http://[PI_IP]:6767`

**Verify:**
```bash
make verify-phase-1
```

**Rollback:**
```bash
make rollback-phase-1
```

**Test for:** 24-48 hours

---

## Phase 2: Monitoring & Alerting

**What gets added:**
- **Health monitoring daemon** (runs every 5 min)
- **Multi-channel alerts** (ntfy/Discord/Telegram/Email)
- **Metrics collection** (disk, temp, containers)
- **State tracking** (alerts only on changes)

**Why now:** Know when things break before users complain

**Deploy:**
```bash
make phase-2
```

**Interactive setup:**
- Choose notification method
- Configure credentials
- Test alert sent

**Verify:**
```bash
make verify-phase-2

# Send test alert
make test-alert
```

**View logs:**
```bash
tail -f config/monitoring/logs/monitor.log
```

**Rollback:**
```bash
make rollback-phase-2
```

**Test for:** 1 week (tune alert thresholds)

---

## Phase 3: Automation & Maintenance

**What gets added:**
- **Advanced backups** (daily/weekly/monthly with cloud sync)
- **System updates** (opt-in automation)
- **Webhook notifier** (media ready notifications)

**Why now:** Hands-free operation, bulletproof backups

**Deploy:**
```bash
make phase-3
```

**Interactive setup:**
- Enable auto-updates? (recommend: NO)
- Configure cloud backup? (optional)
- Install webhook notifier? (optional)

**Scheduled jobs:**
```
Daily 3:00 AM   → Backup configs
Weekly Sun 4:00 → Backup configs + metadata
Monthly 1st 5:00 → Full backup
```

**Verify:**
```bash
make verify-phase-3

# Check cron
crontab -l
```

**Test backup:**
```bash
bash scripts/phase3/backup_advanced.sh daily
ls -lh backups/
```

**Rollback:**
```bash
make rollback-phase-3
```

**Test for:** 1 week (verify backups working)

---

## Quick Reference

### Check Deployment Status
```bash
make show-phases
```

Output:
```
Phase 0 (Bootstrap): ✓ Deployed
Phase 1 (Foundation): ✓ Deployed
Phase 2 (Monitoring): ✓ Deployed
Phase 3 (Automation): ✗ Not deployed
```

### Deploy All Phases
```bash
# After bootstrap completes:
make phase-1
# Test 24-48 hours

make phase-2
# Test 1 week

make phase-3
# Test 1 week
```

### Rollback Strategy
```bash
# Rollback Phase 3 only
make rollback-phase-3

# Rollback to Phase 0 (nuclear option)
make rollback-phase-3
make rollback-phase-2
make rollback-phase-1
```

---

## Recommended Timeline

**Week 1:**
- Day 1: Deploy Phase 0 (bootstrap)
- Day 2-3: Deploy Phase 1
- Test everything works

**Week 2:**
- Day 4-5: Deploy Phase 2
- Configure alerts
- Tune thresholds

**Week 3:**
- Day 8-10: Deploy Phase 3
- Configure backups
- Test automation

**Week 4+:**
- System is production-ready
- All automation active
- Hands-free operation

---

## Troubleshooting

### Phase 1 Issues

**Caddy not starting:**
```bash
docker logs caddy
# Check port conflicts (443, 80)
sudo netstat -tlnp | grep :443
```

**Homer dashboard empty:**
```bash
# Regenerate config
bash scripts/phase1/install.sh
```

### Phase 2 Issues

**No alerts received:**
```bash
# Test alert system
make test-alert

# Check config
cat config/monitoring/alert_config.sh

# Check logs
tail config/monitoring/logs/monitor.log
```

**Too many alerts:**
```bash
# Edit thresholds in:
nano scripts/phase2/health_monitor.sh
```

### Phase 3 Issues

**Backups not running:**
```bash
# Check cron
crontab -l | grep backup

# Test manual backup
bash scripts/phase3/backup_advanced.sh daily
```

**Cloud sync failing:**
```bash
# Check rclone config
rclone --config config/backup/rclone.conf listremotes
```

---

## Safety Features

Each phase includes:
- ✅ Pre-deployment backup
- ✅ Verification script
- ✅ Rollback procedure
- ✅ Error handling
- ✅ Dry-run mode

**Best practices:**
1. Deploy one phase at a time
2. Test each phase before proceeding
3. Don't skip verification
4. Keep backups external to Pi

---

## Resource Usage

| Phase | Added RAM | Added Disk | CPU Impact |
|-------|-----------|------------|------------|
| 0 | 1.4 GB | 50 MB | Baseline |
| 1 | +170 MB | +100 MB | Minimal |
| 2 | +10 MB | +10 MB/month | 5 sec/5 min |
| 3 | +150 MB | Varies | 5 min/day |
| **Total** | **~1.75 GB** | **~200 MB** | **Low** |

Raspberry Pi 5 (16 GB): **89% RAM free** ✅

---

## Next Steps After Phase 3

**Optional enhancements:**
- Custom Flask dashboard
- AI recommendations
- Content lifecycle management
- Homelab integrations

**Or just enjoy:**
- Fully automated media server
- Self-monitoring
- Self-healing
- Hands-free backups

You're done! 🎉
