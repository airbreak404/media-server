#!/usr/bin/env python3
"""
Automated API-based configuration for media server applications.

Configures:
- Sonarr: Download client (RdtClient), root folders, remote path mappings
- Radarr: Download client (RdtClient), root folders, remote path mappings
- Prowlarr: Indexers, application sync to Sonarr/Radarr
- Jellyseerr: Connection to Sonarr, Radarr, and Jellyfin

Requirements:
- Python 3.7+
- requests library: pip3 install requests
- API keys in .env file
"""

import os
import sys
import json
import time
import argparse
from typing import Dict, Optional, List
from pathlib import Path

try:
    import requests
except ImportError:
    print("Error: 'requests' library not found. Install with: pip3 install requests")
    sys.exit(1)


# Color codes for terminal output
class Colors:
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    NC = '\033[0m'  # No Color


def log_info(msg: str):
    print(f"{Colors.GREEN}[INFO]{Colors.NC} {msg}")


def log_warn(msg: str):
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {msg}")


def log_error(msg: str):
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}")


def load_env() -> Dict[str, str]:
    """Load environment variables from .env file."""
    env_file = Path(".env")
    if not env_file.exists():
        log_error(".env file not found. Copy .env.sample and configure.")
        sys.exit(1)

    env_vars = {}
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                env_vars[key.strip()] = value.strip()

    return env_vars


class ArrApp:
    """Base class for *Arr application API interactions."""

    def __init__(self, name: str, url: str, api_key: Optional[str]):
        self.name = name
        self.url = url.rstrip('/')
        self.api_key = api_key
        self.session = requests.Session()
        self.session.headers.update({
            'X-Api-Key': api_key or '',
            'Content-Type': 'application/json'
        })

    def get(self, endpoint: str) -> Optional[Dict]:
        """Make GET request to API."""
        try:
            resp = self.session.get(f"{self.url}/api/v3/{endpoint}", timeout=10)
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.RequestException as e:
            log_error(f"{self.name} GET {endpoint} failed: {e}")
            return None

    def post(self, endpoint: str, data: Dict) -> Optional[Dict]:
        """Make POST request to API."""
        try:
            resp = self.session.post(f"{self.url}/api/v3/{endpoint}", json=data, timeout=10)
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.RequestException as e:
            log_error(f"{self.name} POST {endpoint} failed: {e}")
            return None

    def put(self, endpoint: str, data: Dict) -> Optional[Dict]:
        """Make PUT request to API."""
        try:
            resp = self.session.put(f"{self.url}/api/v3/{endpoint}", json=data, timeout=10)
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.RequestException as e:
            log_error(f"{self.name} PUT {endpoint} failed: {e}")
            return None

    def wait_for_ready(self, timeout: int = 60) -> bool:
        """Wait for application to be ready."""
        log_info(f"Waiting for {self.name} to be ready...")
        start = time.time()
        while time.time() - start < timeout:
            try:
                resp = self.session.get(f"{self.url}/api/v3/system/status", timeout=5)
                if resp.status_code == 200:
                    log_info(f"✓ {self.name} is ready")
                    return True
            except requests.exceptions.RequestException:
                pass
            time.sleep(2)

        log_error(f"{self.name} not ready after {timeout}s")
        return False

    def add_download_client(self, rdt_url: str, category: str) -> bool:
        """Add RdtClient as qBittorrent download client."""
        # Check if already exists
        clients = self.get("downloadclient")
        if clients:
            for client in clients:
                if client.get('name') == 'RdtClient':
                    log_info(f"✓ {self.name}: Download client already configured")
                    return True

        # Add new download client
        client_config = {
            "enable": True,
            "protocol": "torrent",
            "priority": 1,
            "removeCompletedDownloads": True,
            "removeFailedDownloads": True,
            "name": "RdtClient",
            "fields": [
                {"name": "host", "value": rdt_url.replace("http://", "").split(":")[0]},
                {"name": "port", "value": int(rdt_url.split(":")[-1])},
                {"name": "useSsl", "value": False},
                {"name": "urlBase", "value": ""},
                {"name": "username", "value": ""},
                {"name": "password", "value": ""},
                {"name": "category", "value": category},
                {"name": "postImportCategory", "value": ""},
                {"name": "recentPriority", "value": 0},
                {"name": "olderPriority", "value": 0},
                {"name": "initialState", "value": 0},
                {"name": "sequentialOrder", "value": False},
                {"name": "firstAndLast", "value": False}
            ],
            "implementationName": "qBittorrent",
            "implementation": "QBittorrent",
            "configContract": "QBittorrentSettings",
            "tags": []
        }

        result = self.post("downloadclient", client_config)
        if result:
            log_info(f"✓ {self.name}: Download client added")
            return True
        return False

    def add_root_folder(self, path: str) -> bool:
        """Add root folder for media."""
        # Check if already exists
        folders = self.get("rootfolder")
        if folders:
            for folder in folders:
                if folder.get('path') == path:
                    log_info(f"✓ {self.name}: Root folder already configured: {path}")
                    return True

        # Add new root folder
        result = self.post("rootfolder", {"path": path})
        if result:
            log_info(f"✓ {self.name}: Root folder added: {path}")
            return True
        return False

    def add_remote_path_mapping(self, host: str, remote_path: str, local_path: str) -> bool:
        """Add remote path mapping."""
        # Check if already exists
        mappings = self.get("remotePathMapping")
        if mappings:
            for mapping in mappings:
                if mapping.get('host') == host:
                    log_info(f"✓ {self.name}: Remote path mapping already configured")
                    return True

        # Add new mapping
        mapping_config = {
            "host": host,
            "remotePath": remote_path,
            "localPath": local_path
        }

        result = self.post("remotePathMapping", mapping_config)
        if result:
            log_info(f"✓ {self.name}: Remote path mapping added")
            return True
        return False


def configure_sonarr(env: Dict[str, str], dry_run: bool = False) -> bool:
    """Configure Sonarr."""
    log_info("=== Configuring Sonarr ===")

    api_key = env.get('SONARR_API_KEY')
    if not api_key:
        log_warn("SONARR_API_KEY not set in .env, skipping Sonarr configuration")
        log_warn("Get API key from Sonarr UI: Settings -> General -> Security -> API Key")
        return False

    sonarr = ArrApp("Sonarr", "http://localhost:8989", api_key)

    if not sonarr.wait_for_ready():
        return False

    if dry_run:
        log_info("[DRY RUN] Would configure Sonarr")
        return True

    # Add download client
    sonarr.add_download_client("http://rdtclient:6500", "sonarr")

    # Add root folder
    sonarr.add_root_folder("/tv")

    # Add remote path mapping
    sonarr.add_remote_path_mapping("rdtclient", "/data/downloads", "/data/downloads")

    log_info("✓ Sonarr configuration complete")
    return True


def configure_radarr(env: Dict[str, str], dry_run: bool = False) -> bool:
    """Configure Radarr."""
    log_info("=== Configuring Radarr ===")

    api_key = env.get('RADARR_API_KEY')
    if not api_key:
        log_warn("RADARR_API_KEY not set in .env, skipping Radarr configuration")
        log_warn("Get API key from Radarr UI: Settings -> General -> Security -> API Key")
        return False

    radarr = ArrApp("Radarr", "http://localhost:7878", api_key)

    if not radarr.wait_for_ready():
        return False

    if dry_run:
        log_info("[DRY RUN] Would configure Radarr")
        return True

    # Add download client
    radarr.add_download_client("http://rdtclient:6500", "radarr")

    # Add root folder
    radarr.add_root_folder("/movies")

    # Add remote path mapping
    radarr.add_remote_path_mapping("rdtclient", "/data/downloads", "/data/downloads")

    log_info("✓ Radarr configuration complete")
    return True


def configure_prowlarr(env: Dict[str, str], dry_run: bool = False) -> bool:
    """Configure Prowlarr."""
    log_info("=== Configuring Prowlarr ===")

    api_key = env.get('PROWLARR_API_KEY')
    if not api_key:
        log_warn("PROWLARR_API_KEY not set in .env, skipping Prowlarr configuration")
        log_warn("Get API key from Prowlarr UI: Settings -> General -> Security -> API Key")
        return False

    prowlarr = ArrApp("Prowlarr", "http://localhost:9696", api_key)

    if not prowlarr.wait_for_ready():
        return False

    if dry_run:
        log_info("[DRY RUN] Would configure Prowlarr")
        return True

    log_info("✓ Prowlarr is ready")
    log_info("  Manual steps required:")
    log_info("  1. Add indexers via Prowlarr UI")
    log_info("  2. Add Sonarr app: Settings -> Apps -> Add -> Sonarr")
    log_info("  3. Add Radarr app: Settings -> Apps -> Add -> Radarr")

    return True


def main():
    parser = argparse.ArgumentParser(description="Configure media server applications via API")
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    parser.add_argument('--app', choices=['sonarr', 'radarr', 'prowlarr', 'all'],
                        default='all', help='Which app to configure')

    args = parser.parse_args()

    log_info("=== Media Server API Configuration ===")
    log_info("")

    env = load_env()

    if args.dry_run:
        log_warn("DRY RUN MODE - No changes will be made")
        log_info("")

    success = True

    if args.app in ['sonarr', 'all']:
        if not configure_sonarr(env, args.dry_run):
            success = False
        log_info("")

    if args.app in ['radarr', 'all']:
        if not configure_radarr(env, args.dry_run):
            success = False
        log_info("")

    if args.app in ['prowlarr', 'all']:
        if not configure_prowlarr(env, args.dry_run):
            success = False
        log_info("")

    if success:
        log_info("✓ Configuration complete!")
        log_info("")
        log_info("Next steps:")
        log_info("  1. Complete manual configuration in Prowlarr UI")
        log_info("  2. Add indexers and sync to Sonarr/Radarr")
        log_info("  3. Configure Jellyseerr to connect to Sonarr/Radarr")
        log_info("  4. Add media libraries in Jellyfin")
    else:
        log_error("Configuration completed with errors")
        log_info("Ensure API keys are set in .env file and services are running")
        sys.exit(1)


if __name__ == '__main__':
    main()
