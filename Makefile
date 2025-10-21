.PHONY: help preflight install up down restart logs status health backup verify clean

COMPOSE_FILE := compose/docker-compose.yml

help: ## Show this help message
	@echo "Media Server Management Commands"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make preflight        - Run preflight checks"
	@echo "  make install          - Full installation (requires sudo)"
	@echo "  make install-tailscale- Install Tailscale for SSH (optional)"
	@echo "  make bootstrap        - Complete bootstrap (format drives, install, deploy)"
	@echo ""
	@echo "Service Commands:"
	@echo "  make up            - Start all services"
	@echo "  make down          - Stop all services"
	@echo "  make restart       - Restart all services"
	@echo "  make status        - Show container status"
	@echo ""
	@echo "Maintenance Commands:"
	@echo "  make logs          - View all logs (add SVC=name for specific service)"
	@echo "  make health        - Run health checks"
	@echo "  make verify        - Quick verification (mounts, containers, endpoints)"
	@echo "  make backup        - Create backup"
	@echo "  make update        - Pull latest images and restart"
	@echo ""
	@echo "Cleanup Commands:"
	@echo "  make clean         - Stop services (preserve data)"
	@echo "  make uninstall     - Uninstall (preserve configs)"
	@echo ""
	@echo "Phased Deployment:"
	@echo "  make phase-1       - Foundation (Bazarr, Caddy, Homer)"
	@echo "  make phase-2       - Monitoring & Alerting"
	@echo "  make phase-3       - Automation & Backups"
	@echo "  make show-phases   - Show deployment status"
	@echo ""
	@echo "Examples:"
	@echo "  make logs SVC=jellyfin"
	@echo "  make restart SVC=sonarr"

preflight: ## Run preflight checks
	@bash scripts/00_preflight.sh

bootstrap: ## Complete bootstrap (WARNING: formats drives)
	@echo "Starting full bootstrap..."
	@sudo bash scripts/00_preflight.sh
	@echo ""
	@echo "⚠ WARNING: This will format drives /dev/sda and /dev/sdb"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		sudo bash scripts/01_format_and_mount_drives.sh --format && \
		sudo bash scripts/02_install_docker.sh && \
		( [ -f .env ] && source .env && [ "$${INSTALL_TAILSCALE:-true}" = "true" ] && \
		  sudo bash scripts/02b_install_tailscale.sh || \
		  echo "Skipping Tailscale installation" ) && \
		bash scripts/03_cloudflared_login_and_tunnel.sh && \
		bash scripts/05_compose_up.sh && \
		bash scripts/07_health_checks.sh; \
	else \
		echo "Bootstrap cancelled"; \
		exit 1; \
	fi

install: ## Install Docker and dependencies (requires sudo)
	@sudo bash scripts/02_install_docker.sh

install-tailscale: ## Install Tailscale for secure SSH (optional)
	@sudo bash scripts/02b_install_tailscale.sh

up: ## Start all services
	@bash scripts/05_compose_up.sh

down: ## Stop all services
	@docker compose -f $(COMPOSE_FILE) down

restart: ## Restart services (SVC=service_name for specific service)
ifdef SVC
	@docker compose -f $(COMPOSE_FILE) restart $(SVC)
	@echo "Restarted $(SVC)"
else
	@docker compose -f $(COMPOSE_FILE) restart
	@echo "Restarted all services"
endif

logs: ## View logs (SVC=service_name for specific service)
ifdef SVC
	@docker compose -f $(COMPOSE_FILE) logs -f $(SVC)
else
	@docker compose -f $(COMPOSE_FILE) logs -f
endif

status: ## Show container status
	@docker compose -f $(COMPOSE_FILE) ps

health: ## Run comprehensive health checks
	@bash scripts/07_health_checks.sh

verify: ## Quick verification checks
	@echo "Running quick verification..."
	@bash verify/check_mounts.sh
	@echo ""
	@bash verify/check_containers.sh
	@echo ""
	@bash verify/curl_checks.sh

backup: ## Create configuration backup
	@bash scripts/90_backup.sh

update: ## Pull latest images and restart services
	@echo "Pulling latest images..."
	@docker compose -f $(COMPOSE_FILE) pull
	@echo "Restarting services..."
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "Update complete!"

clean: ## Stop all services
	@docker compose -f $(COMPOSE_FILE) down
	@echo "Services stopped. Configurations preserved."

uninstall: ## Uninstall services (preserves configs)
	@bash scripts/99_uninstall.sh

# Development/testing targets
.PHONY: dry-run-all

dry-run-all: ## Dry run all scripts
	@echo "=== Dry run all scripts ==="
	@bash scripts/00_preflight.sh --dry-run || true
	@bash scripts/01_format_and_mount_drives.sh --dry-run || true
	@bash scripts/05_compose_up.sh --dry-run || true
	@bash scripts/90_backup.sh --dry-run || true

# Phase Deployment System
.PHONY: phase-1 phase-2 phase-3 verify-phase-1 verify-phase-2 verify-phase-3 rollback-phase-1 rollback-phase-2 rollback-phase-3

phase-1: ## Phase 1: Foundation Services (Bazarr, Caddy, Homer, Performance)
	@echo "=== Deploying Phase 1: Foundation Services ==="
	@bash scripts/phase1/install.sh

phase-2: ## Phase 2: Monitoring & Alerting
	@echo "=== Deploying Phase 2: Monitoring & Alerting ==="
	@bash scripts/phase2/install.sh

phase-3: ## Phase 3: Automation & Maintenance
	@echo "=== Deploying Phase 3: Automation & Maintenance ==="
	@bash scripts/phase3/install.sh

verify-phase-1: ## Verify Phase 1 installation
	@bash scripts/phase1/verify.sh

verify-phase-2: ## Verify Phase 2 installation
	@bash scripts/phase2/verify.sh

verify-phase-3: ## Verify Phase 3 installation
	@bash scripts/phase3/verify.sh

rollback-phase-1: ## Rollback Phase 1 to Phase 0
	@bash scripts/phase1/rollback.sh

rollback-phase-2: ## Rollback Phase 2
	@bash scripts/phase2/rollback.sh

rollback-phase-3: ## Rollback Phase 3
	@bash scripts/phase3/rollback.sh

test-alert: ## Send test notification (Phase 2 required)
	@bash scripts/phase2/test_alert.sh

show-phases: ## Show deployed phases
	@echo "=== Deployed Phases ==="
	@echo -n "Phase 0 (Bootstrap): "
	@docker ps --format '{{.Names}}' | grep -q jellyfin && echo "✓ Deployed" || echo "✗ Not deployed"
	@echo -n "Phase 1 (Foundation): "
	@docker ps --format '{{.Names}}' | grep -q bazarr && echo "✓ Deployed" || echo "✗ Not deployed"
	@echo -n "Phase 2 (Monitoring): "
	@crontab -l 2>/dev/null | grep -q health_monitor && echo "✓ Deployed" || echo "✗ Not deployed"
	@echo -n "Phase 3 (Automation): "
	@crontab -l 2>/dev/null | grep -q backup_advanced && echo "✓ Deployed" || echo "✗ Not deployed"
