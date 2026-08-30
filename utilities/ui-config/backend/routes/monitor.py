"""
backend/routes/monitor.py
Monitoring API endpoints for system, Docker, NiFi, and services performance.
"""

import logging
from flask import Blueprint, jsonify
import psutil

try:
    import docker
except ImportError:
    docker = None

from backend.config import config_manager

logger = logging.getLogger(__name__)

monitor_bp = Blueprint('monitor', __name__, url_prefix='/api/monitor')


def _calculate_cpu_percent(stats):
    """Calculate CPU percentage from Docker stats"""
    try:
        cpu_delta = stats["cpu_stats"]["cpu_usage"]["total_usage"] - \
                    stats["precpu_stats"]["cpu_usage"]["total_usage"]
        system_delta = stats["cpu_stats"]["system_cpu_usage"] - \
                       stats["precpu_stats"]["system_cpu_usage"]
        if system_delta > 0:
            return round((cpu_delta / system_delta) * 100.0, 2)
    except (KeyError, TypeError, ZeroDivisionError):
        pass
    return 0.0


@monitor_bp.route('/system')
def monitor_system():
    """System-level performance metrics"""
    try:
        return jsonify({
            "success": True,
            "cpu_percent": psutil.cpu_percent(interval=0.5),
            "memory": {
                "total": psutil.virtual_memory().total,
                "used": psutil.virtual_memory().used,
                "percent": psutil.virtual_memory().percent
            },
            "disk": {
                "total": psutil.disk_usage('/').total,
                "used": psutil.disk_usage('/').used,
                "percent": psutil.disk_usage('/').percent
            }
        })
    except Exception as e:
        logger.error(f"System monitoring error: {e}")
        return jsonify({"success": False, "error": str(e)}), 500


@monitor_bp.route('/docker')
def monitor_docker():
    """Docker containers + real-time performance stats"""
    if docker is None:
        return jsonify({"success": False, "error": "docker package not installed"}), 500

    try:
        client = docker.from_env()
        containers = client.containers.list(all=True)

        result = []
        for c in containers:
            stats = {}
            try:
                if c.status == "running":
                    stats_raw = c.stats(stream=False)
                    stats = {
                        "cpu_percent": _calculate_cpu_percent(stats_raw),
                        "memory_usage_mb": round(stats_raw.get("memory_stats", {}).get("usage", 0) / (1024 * 1024), 2),
                        "memory_limit_mb": round(stats_raw.get("memory_stats", {}).get("limit", 0) / (1024 * 1024), 2),
                    }
            except Exception:
                pass

            result.append({
                "id": c.short_id,
                "name": c.name,
                "status": c.status,
                "image": c.image.tags[0] if c.image.tags else "unknown",
                "stats": stats
            })

        return jsonify({"success": True, "containers": result, "count": len(result)})
    except Exception as e:
        logger.error(f"Docker monitoring error: {e}")
        return jsonify({"success": False, "error": str(e)}), 500


@monitor_bp.route('/nifi')
def monitor_nifi():
    """NiFi connection and basic status"""
    try:
        from backend.app import nifi_client  # avoid circular import
        status = nifi_client.test_connection()
        return jsonify({
            "success": True,
            "connected": status.get("success", False),
            "version": status.get("version"),
            "authenticated": bool(config_manager.config.auth_token)
        })
    except Exception as e:
        logger.error(f"NiFi monitoring error: {e}")
        return jsonify({"success": False, "error": str(e)}), 500


@monitor_bp.route('/services')
def monitor_services():
    """High-level overview of all managed services"""
    services = [
        {"name": "NiFi", "type": "core", "status": "managed", "endpoint": "/config-nifi"},
        {"name": "IDOL Setup", "type": "core", "status": "managed", "endpoint": "/config-idol"},
        {"name": "Docker Engine", "type": "infrastructure", "status": "monitored"},
        {"name": "GitHub Flow Registry", "type": "integration", "status": "optional"},
        {"name": "LLM Integration", "type": "feature", "status": "conditional"},
    ]
    return jsonify({"success": True, "services": services})


@monitor_bp.route('/status')
def proxy_real_monitor_status():
    """
    Proxy to the real IDOL Monitor UI backend (the advanced one on port 5011).
    This avoids hard-coding localhost:5011 in the frontend and solves CORS.
    Returns the exact same structure as http://localhost:5011/api/status
    """
    import requests
    try:
        resp = requests.get('http://localhost:5011/api/status', timeout=4)
        data = resp.json()
        if 'ok' not in data:
            data['ok'] = resp.status_code < 400
        return jsonify(data), resp.status_code
    except requests.exceptions.RequestException as e:
        logger.warning(f"Monitor UI backend unreachable: {e}")
        return jsonify({
            "ok": False,
            "error": "Monitor backend not reachable",
            "source": "proxy",
            "services": [],
            "summary": {"total": 0, "healthy": 0, "degraded": 0}
        }), 502
    except Exception as e:
        logger.error(f"Unexpected error proxying monitor status: {e}")
        return jsonify({"ok": False, "error": str(e), "source": "proxy"}), 500
