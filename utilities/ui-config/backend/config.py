"""
backend/config.py
Centralized configuration + runtime state manager for the entire UI.
This is the single source of truth for NiFi, GitHub, IDOL paths, ports, etc.
"""

import os
import json
import logging
from typing import Any, Dict, Optional
from dataclasses import dataclass, field, asdict
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass
class AppConfig:
    """Runtime configuration dataclass"""
    # NiFi
    nifi_api_url: str = "https://localhost:8443/nifi-api"
    nifi_port: int = 8443
    container_name: str = "nifi"
    docker_image: str = "apache/nifi:latest"
    nifi_username: Optional[str] = None
    nifi_password: Optional[str] = None
    auth_token: Optional[str] = None
    registry_id: Optional[str] = None

    # GitHub
    github_owner: Optional[str] = None
    github_repo_name: Optional[str] = None
    github_token: Optional[str] = None
    github_branch: str = "main"
    github_flow_dir: str = "nifi-flows"
    github_api_url: str = "https://api.github.com"

    # IDOL Paths
    idol_base_path: str = "/opt/idol-deployment"
    idol_shared_folder_path: str = "/shared-folder"
    nifi_flows_dir: str = "/nifi-flows"

    # Feature Flags
    llm_integration_enabled: bool = False
    rich_media_enabled: bool = False
    data_admin_enabled: bool = False

    # Internal
    _config_file: str = field(default="/app/config/runtime-config.json", repr=False)


class ConfigManager:
    """Singleton-style configuration manager"""

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.config = AppConfig()
        self._load_from_env()
        self._load_from_file()
        self._initialized = True
        logger.info("ConfigManager initialized")

    def _load_from_env(self):
        """Load values from environment variables"""
        env_map = {
            "nifi_api_url": "NIFI_API_URL",
            "nifi_port": ("NIFI_PORT", int),
            "container_name": "NIFI_CONTAINER_NAME",
            "idol_base_path": "IDOL_BASE_PATH",
            "idol_shared_folder_path": "IDOL_SHARED_FOLDER_PATH",
            "nifi_flows_dir": "IDOL_NIFI_FLOWS_DIR",
            "github_owner": "GITHUB_OWNER",
            "github_repo_name": "GITHUB_REPO_NAME",
            "github_token": "GITHUB_TOKEN",
            "github_branch": "GITHUB_BRANCH",
        }

        for attr, env_key in env_map.items():
            if isinstance(env_key, tuple):
                env_key, converter = env_key
            else:
                converter = str

            value = os.getenv(env_key)
            if value is not None:
                try:
                    setattr(self.config, attr, converter(value))
                except Exception as e:
                    logger.warning(f"Failed to convert env var {env_key}: {e}")

    def _load_from_file(self):
        path = Path(self.config._config_file)
        if path.exists():
            try:
                with open(path) as f:
                    data = json.load(f)
                    for k, v in data.items():
                        if hasattr(self.config, k):
                            setattr(self.config, k, v)
                logger.info("Loaded config from file")
            except Exception as e:
                logger.error(f"Failed to load config file: {e}")

    def save(self):
        """Persist current config to disk"""
        path = Path(self.config._config_file)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as f:
            json.dump(asdict(self.config), f, indent=2)
        logger.info("Configuration saved")

    def update(self, data: Dict[str, Any]):
        """Update config from dict"""
        for key, value in data.items():
            if hasattr(self.config, key):
                setattr(self.config, key, value)
        self.save()

    def get_safe_config(self) -> Dict[str, Any]:
        """Return config without secrets"""
        data = asdict(self.config)
        if data.get("github_token"):
            data["github_token"] = "***REDACTED***"
        if data.get("nifi_password"):
            data["nifi_password"] = "***REDACTED***"
        return data

    def validate_port_and_url(self, port: int, url: str) -> list:
        issues = []
        if not (1 <= port <= 65535):
            issues.append("Port must be between 1-65535")
        if url and not url.startswith(("http://", "https://")):
            issues.append("URL must start with http:// or https://")
        return issues


# Global instance (use this everywhere in the app)
config_manager = ConfigManager()
