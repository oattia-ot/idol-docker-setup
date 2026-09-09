#!/usr/bin/env python3
"""
Flask backend for Config Monitor UI (IDOL Monitoring Stack)
- Dynamically discovers real Docker services (all idol-* containers)
- Special support for idol-demo-* application services (Find, Community, View, Content, NiFi, etc.)
- Shows real running status, live CPU/MEM metrics from Docker
- Keeps the beautiful frontend unchanged
"""

from flask import Flask, jsonify, send_from_directory
from datetime import datetime, timezone
import docker
from docker.errors import DockerException
import socket
import subprocess
import requests
from requests.exceptions import RequestException
import urllib3
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# Suppress InsecureRequestWarning for self-signed HTTPS probes
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

app = Flask(__name__, static_folder='static', static_url_path='')

# ============================================================
# SIMPLE CACHE + PARALLEL STATS (Fix for slow "Open Live Monitor")
# ============================================================
_STATUS_CACHE = {
    "data": None,
    "timestamp": 0,
    "ttl": 4.5   # seconds — perfect for 8s frontend polling
}

def _get_cached_status():
    now = time.time()
    if (_STATUS_CACHE["data"] is not None and 
        now - _STATUS_CACHE["timestamp"] < _STATUS_CACHE["ttl"]):
        return _STATUS_CACHE["data"]
    return None

def _set_cached_status(data):
    _STATUS_CACHE["data"] = data
    _STATUS_CACHE["timestamp"] = time.time()
# ============================================================

# Friendly name + port + description mapping for idol-* containers
# Includes URL and default credentials where applicable
SERVICE_INFO = {
    "idol-yacht": {
        "name": "Yacht",
        "port": 5001,
        "description": "Container Management UI",
        "endpoint": "localhost:5001",
        "url": "http://localhost:5001",
        "credentials": "admin@idol.local / opentext1!"
    },
    "idol-dockge": {
        "name": "Dockge",
        "port": 5002,
        "description": "Docker Compose Stack Manager",
        "endpoint": "localhost:5002",
        "url": "http://localhost:5002",
        "credentials": "admin / opentext1!"
    },
    "idol-dozzle": {
        "name": "Dozzle",
        "port": 5003,
        "description": "Real-time Log Viewer",
        "endpoint": "localhost:5003",
        "url": "http://localhost:5003",
        "credentials": "admin / opentext1!"
    },
    "idol-cadvisor": {
        "name": "cAdvisor",
        "port": 5004,
        "description": "Container Metrics Collector",
        "endpoint": "localhost:5004",
        "url": "http://localhost:5004",
        "credentials": None   # No login required
    },
    "idol-prometheus": {
        "name": "Prometheus",
        "port": 5005,
        "description": "Metrics Collection & Storage",
        "endpoint": "localhost:5005",
        "url": "http://localhost:5005",
        "credentials": None
    },
    "idol-grafana": {
        "name": "Grafana",
        "port": 5006,
        "description": "Metrics Visualization Dashboard",
        "endpoint": "localhost:5006",
        "url": "http://localhost:5006",
        "credentials": "admin / opentext1!"
    },
    "idol-loki": {
        "name": "Loki",
        "port": 5007,
        "description": "Log Aggregation System",
        "endpoint": "localhost:5007",
        "url": "http://localhost:5007",
        "credentials": None
    },
    "idol-promtail": {
        "name": "Promtail",
        "port": 5008,
        "description": "Log Shipper for Loki",
        "endpoint": "localhost:5008",
        "url": "http://localhost:5008",
        "credentials": None
    },
    "idol-dokemon": {
        "name": "Dokemon",
        "port": 5009,
        "description": "Simple Docker Monitor",
        "endpoint": "localhost:5009",
        "url": "http://localhost:5009",
        "credentials": None
    },
    "idol-node-exporter": {
        "name": "Node Exporter",
        "port": 5010,
        "description": "System Metrics Exporter",
        "endpoint": "localhost:5010",
        "url": "http://localhost:5010",
        "credentials": None
    },
    "idol-monitor-ui": {
        "name": "Config Monitor UI",
        "port": 5011,
        "description": "This Dashboard",
        "endpoint": "localhost:5011",
        "url": "http://localhost:5011",
        "credentials": None
    },

    # ============================================================
    # IDOL Demo Application Services (from docker ps output)
    # These are the actual IDOL components running in the demo
    # ============================================================
    "idol-demo-httpd-reverse-proxy-1": {
        "name": "HTTPD Reverse Proxy",
        "port": 8330,
        "description": "Apache Reverse Proxy for IDOL Demo",
        "endpoint": "localhost:8330",
        "url": "http://localhost:8330",
        "credentials": None
    },
    "idol-demo-idol-find-1": {
        "name": "IDOL Find",
        "port": 8440,
        "description": "IDOL Find - Enterprise Search UI",
        "endpoint": "localhost:8440",
        "url": "http://localhost:8440",
        "credentials": None
    },
    "idol-demo-idol-community-1": {
        "name": "IDOL Community",
        "port": 9030,
        "description": "IDOL Community Server (9030-9032)",
        "endpoint": "localhost:9030-9032",
        "url": "http://localhost:9030",
        "credentials": None
    },
    "idol-demo-idol-view-1": {
        "name": "IDOL View",
        "port": 9080,
        "description": "IDOL View Server (9080-9082)",
        "endpoint": "localhost:9080-9082",
        "url": "http://localhost:9080",
        "credentials": None
    },
    "idol-demo-idol-content-1": {
        "name": "IDOL Content",
        "port": 9100,
        "description": "IDOL Content Server (9100-9102)",
        "endpoint": "localhost:9100-9102",
        "url": "http://localhost:9100",
        "credentials": None
    },
    "idol-demo-idol-nifi-1": {
        "name": "IDOL NiFi",
        "port": 8443,
        "description": "Apache NiFi for IDOL Data Pipelines (8443/11000/8001)",
        "endpoint": "localhost:8443,11000,8001",
        "url": "https://localhost:8443",
        "credentials": None
    },
    "idol-demo-idol-agentstore-1": {
        "name": "IDOL Agentstore",
        "port": 9050,
        "description": "IDOL Agentstore (9050-9052)",
        "endpoint": "localhost:9050-9052",
        "url": None,
        "credentials": None
    },
    "idol-demo-idol-categorisation-agentstore-1": {
        "name": "IDOL Categorisation Agentstore",
        "port": 9180,
        "description": "IDOL Categorisation Agentstore (9180-9182)",
        "endpoint": "localhost:9180-9182",
        "url": None,
        "credentials": None
    },
    "idol-demo-idol-category-1": {
        "name": "IDOL Category",
        "port": 9020,
        "description": "IDOL Category Server (9020-9022)",
        "endpoint": "localhost:9020-9022",
        "url": None,
        "credentials": None
    },
}


# ============================================================
# Dynamic Protocol + FQDN Detection (inspired by user's script)
# ============================================================

PROTOCOL_CACHE = {}
FQDN_CACHE = None


def get_domain_suffix():
    """Get domain suffix using hostname -d, with fallback to socket.getfqdn()."""
    global FQDN_CACHE
    if FQDN_CACHE is not None:
        return FQDN_CACHE

    try:
        result = subprocess.run(
            ['hostname', '-d'],
            capture_output=True, text=True, timeout=2
        )
        domain = result.stdout.strip()
        if domain and domain != '(none)':
            FQDN_CACHE = domain
            return domain
    except Exception:
        pass

    try:
        fqdn = socket.getfqdn()
        if '.' in fqdn:
            FQDN_CACHE = fqdn.split('.', 1)[1]
            return FQDN_CACHE
    except Exception:
        pass

    FQDN_CACHE = "local"
    return "local"


def detect_protocol_for_port(port, use_host="host.docker.internal"):
    """
    Check if a port responds to HTTPS or HTTP.
    Tries HTTPS first; falls back to HTTP.
    Returns (proto, status_code) or (None, None) if unreachable.
    Results are cached per port so repeated calls are instant.
    """
    if not port:
        return None, None

    cache_key = f"proto:{port}"
    if cache_key in PROTOCOL_CACHE:
        return PROTOCOL_CACHE[cache_key]

    for proto in ('https', 'http'):
        url = f"{proto}://{use_host}:{port}"
        try:
            resp = requests.head(
                url,
                timeout=2.5,
                verify=False,          # self-signed certs are fine for detection
                allow_redirects=True
            )
            if 100 <= resp.status_code < 500:
                PROTOCOL_CACHE[cache_key] = (proto, resp.status_code)
                print(f"[PROTO] port {port} → {proto.upper()} ({resp.status_code})")
                return proto, resp.status_code
        except RequestException:
            continue

    PROTOCOL_CACHE[cache_key] = (None, None)
    print(f"[PROTO] port {port} → unreachable (no HTTP/HTTPS response)")
    return None, None


def detect_protocol_for_services(service_infos):
    """
    Run protocol detection in parallel for all services that have a port.
    Returns a dict: {port: proto}
    service_infos: list of (container_name, info_dict)
    """
    # Collect unique ports that need probing (skip already-cached)
    ports_to_probe = {
        info.get("port")
        for _, info in service_infos
        if info.get("port") and f"proto:{info['port']}" not in PROTOCOL_CACHE
    }

    if ports_to_probe:
        print(f"[PROTO] Probing {len(ports_to_probe)} ports in parallel: {sorted(ports_to_probe)}")
        with ThreadPoolExecutor(max_workers=min(20, len(ports_to_probe))) as executor:
            futures = {
                executor.submit(detect_protocol_for_port, port): port
                for port in ports_to_probe
            }
            for future in as_completed(futures):
                port = futures[future]
                try:
                    future.result()   # result is stored in PROTOCOL_CACHE by the function itself
                except Exception as exc:
                    print(f"[WARN] Protocol probe failed for port {port}: {exc}")
    else:
        print("[PROTO] All ports already cached — skipping probe")


def get_short_hostname():
    """Get the short hostname of the Docker *host* (not the container itself)."""
    # Best option: read from mounted /host/hostname (see docker-compose volume)
    try:
        with open('/host/hostname', 'r') as f:
            host = f.read().strip()
            if host:
                return host.split('.')[0]
    except Exception:
        pass

    # Fallbacks (container hostname - not ideal)
    try:
        result = subprocess.run(
            ['hostname', '-s'],
            capture_output=True, text=True, timeout=2
        )
        short = result.stdout.strip()
        if short:
            return short
    except Exception:
        pass

    try:
        return socket.gethostname().split('.')[0]
    except Exception:
        return "host"


def build_service_url(name, port, info):
    """
    Build the best URL for a service.
    Protocol is taken from PROTOCOL_CACHE (populated by detect_protocol_for_services).
    Falls back to the static 'url' in SERVICE_INFO, then plain http.
    """
    if not port:
        # No port → honour the static URL from SERVICE_INFO (e.g. services with no web UI)
        return info.get("url")

    # Pick protocol from cache; fall back to static info url's scheme, then http
    cached_proto, _ = PROTOCOL_CACHE.get(f"proto:{port}", (None, None))
    if cached_proto:
        proto = cached_proto
    else:
        # Derive from the static url in SERVICE_INFO if available
        static_url = info.get("url") or ""
        proto = static_url.split("://")[0] if "://" in static_url else "http"

    domain = get_domain_suffix()
    short_host = get_short_hostname()

    if domain and domain != "local":
        base = name.replace("idol-demo-", "").replace("-1", "").replace("idol-", "")
        friendly_host = f"{base}.{domain}" if base else f"{short_host}.{domain}"
        return f"{proto}://{friendly_host}:{port}"
    else:
        return f"{proto}://{short_host}:{port}"


def get_container_stats(container):
    """Get live CPU and Memory usage from Docker stats API."""
    if not container.attrs.get("State", {}).get("Running"):
        return None, None

    try:
        stats = container.stats(stream=False)

        # Memory usage
        mem_stats = stats.get("memory_stats", {})
        mem_usage = mem_stats.get("usage", 0)
        mem_limit = mem_stats.get("limit", 1)
        memory_percent = round((mem_usage / mem_limit) * 100, 1) if mem_limit > 0 else 0

        # CPU usage calculation (requires two data points, but we use a simple approximation)
        cpu_stats = stats.get("cpu_stats", {})
        precpu_stats = stats.get("precpu_stats", {})

        cpu_delta = cpu_stats.get("cpu_usage", {}).get("total_usage", 0) - \
                    precpu_stats.get("cpu_usage", {}).get("total_usage", 0)
        system_delta = cpu_stats.get("system_cpu_usage", 0) - precpu_stats.get("system_cpu_usage", 0)
        online_cpus = cpu_stats.get("online_cpus", 1)

        cpu_percent = 0.0
        if system_delta > 0 and cpu_delta > 0:
            cpu_percent = round((cpu_delta / system_delta) * online_cpus * 100.0, 1)

        return cpu_percent, memory_percent

    except Exception as e:
        print(f"[WARN] Could not get stats for {container.name}: {e}")
        return None, None


def get_real_services():
    """Discover real idol-* containers and return structured data for the UI.
    
    OPTIMIZED VERSION:
    - Short TTL cache (4.5s) → repeated polls are instant
    - Parallel Docker stats using ThreadPoolExecutor (big speed improvement)
    """
    # Return cached result if still fresh
    cached = _get_cached_status()
    if cached is not None:
        return cached["services"]

    services = []

    try:
        client = docker.from_env()
        containers = client.containers.list(all=True)
        print(f"[INFO] Docker connected. Total containers on host: {len(containers)}")
    except DockerException as e:
        print(f"[ERROR] Cannot connect to Docker: {e}")
        return []

    idol_containers = [c for c in containers if c.name.startswith("idol-")]
    if not idol_containers:
        print("[INFO] No idol-* containers found")
        _set_cached_status({"services": []})
        return []

    def _get_info(name):
        return SERVICE_INFO.get(name, {
            "name": name.replace("idol-", "").replace("-1", "").replace("-", " ").title().replace("Demo ", "IDOL Demo "),
            "port": None,
            "description": "IDOL Demo Component" if name.startswith("idol-demo-") else "Docker Service",
            "endpoint": ""
        })

    # Collect basic info first (fast)
    basic_info = []
    for container in idol_containers:
        name = container.name
        info = _get_info(name)
        state = container.attrs.get("State", {})
        is_running = state.get("Running", False)
        status_text = state.get("Status", "unknown")
        started_at = state.get("StartedAt", "")
        last_check = started_at if started_at and started_at != "0001-01-01T00:00:00Z" else datetime.now(timezone.utc).isoformat()

        basic_info.append({
            "container": container,
            "name": name,
            "info": info,
            "is_running": is_running,
            "status_text": status_text,
            "last_check": last_check
        })

    # Parallel stats fetching for running containers only
    running_containers = [b["container"] for b in basic_info if b["is_running"]]
    stats_map = {}

    if running_containers:
        print(f"[INFO] Fetching live stats for {len(running_containers)} running idol-* containers (parallel)...")
        with ThreadPoolExecutor(max_workers=min(12, len(running_containers))) as executor:
            future_to_name = {
                executor.submit(get_container_stats, c): c.name
                for c in running_containers
            }
            for future in as_completed(future_to_name):
                cname = future_to_name[future]
                try:
                    cpu, mem = future.result()
                    stats_map[cname] = (cpu, mem)
                except Exception as e:
                    print(f"[WARN] Stats failed for {cname}: {e}")
                    stats_map[cname] = (None, None)
    else:
        print("[INFO] No running idol-* containers — skipping stats")

    # ── Parallel protocol detection for all services ──────────────────────────
    # Must run before build_service_url so PROTOCOL_CACHE is populated
    service_infos = [(b["name"], b["info"]) for b in basic_info]
    detect_protocol_for_services(service_infos)
    # ─────────────────────────────────────────────────────────────────────────

    # Build final service list
    for b in basic_info:
        name = b["name"]
        info = b["info"]
        is_running = b["is_running"]
        cpu, memory = stats_map.get(name, (None, None))

        ui_status = "healthy" if is_running else "degraded"

        service = {
            "id": name,
            "group": "idol-demo" if name.startswith("idol-demo-") else "monitoring",
            "name": info["name"],
            "status": ui_status,
            "uptime": "N/A" if not is_running else "Running",
            "last_check": b["last_check"],
            "version": b["container"].image.tags[0].split(":")[-1] if b["container"].image.tags else "latest",
            "instances": 1,
            "cpu": cpu,
            "memory": memory,
            "response_ms": None,
            "region": "local",
            "endpoint": info["endpoint"],
            "description": info["description"],
            "port": info["port"],
            "url": build_service_url(name, info.get("port"), info),
            "credentials": info.get("credentials"),
            "docker_status": b["status_text"],
            "image": b["container"].image.tags[0] if b["container"].image.tags else b["container"].image.id[:12]
        }
        services.append(service)

    services.sort(key=lambda s: s.get("port") or 9999)

    idol_demo_count = sum(1 for s in services if s["id"].startswith("idol-demo-"))
    monitoring_count = len(services) - idol_demo_count
    print(f"[INFO] Discovered {len(services)} idol-* services ({monitoring_count} monitoring + {idol_demo_count} IDOL Demo)")

    _set_cached_status({"services": services})
    return services

@app.route('/api/status')
def api_status():
    services = get_real_services()

    healthy_count = sum(1 for s in services if s["status"] == "healthy")
    degraded_count = sum(1 for s in services if s["status"] == "degraded")
    monitoring_count = sum(1 for s in services if s.get("group") == "monitoring")
    demo_count = sum(1 for s in services if s.get("group") == "idol-demo")

    print(f"[INFO] /api/status called → {len(services)} services | monitoring: {monitoring_count}, idol-demo: {demo_count} | {healthy_count} healthy, {degraded_count} degraded")

    return jsonify({
        "ok": True,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "services": services,
        "summary": {
            "total": len(services),
            "healthy": healthy_count,
            "degraded": degraded_count,
            "monitoring": monitoring_count,
            "idol_demo": demo_count
        },
        "source": "docker"
    })


@app.route('/')
def index():
    return send_from_directory('static', 'config-monitor.html')


@app.route('/<path:path>')
def static_files(path):
    return send_from_directory('static', path)


if __name__ == '__main__':
    print("🚀 Starting Service Health Dashboard (REAL Docker mode) on http://localhost:5011")
    print("   → Open http://localhost:5011 in your browser")
    print("   → Press F12 in browser to see detailed frontend console logs")
    print("   → Server logs (docker logs / ./monitor.sh logs monitor-ui) will show discovery info")
    app.run(host='0.0.0.0', port=5000, debug=True)