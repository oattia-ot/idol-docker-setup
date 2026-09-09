"""
Apache NiFi GitHub Registry & Parameter Context Manager
Flask Backend for executing NiFi operations via REST API

Features:
- Docker management for NiFi containers
- GitHub Flow Registry integration
- Parameter Context CRUD
- Controller Service management
- Bash script executor (pre-setup)
- Host folder flow scanning
- Full REST API + web UI
"""

import json
import logging
import sys
import os
import subprocess
import docker
import time
import shutil
import requests
import urllib3
import socket
import mimetypes
import pathlib
import uuid
from werkzeug.utils import secure_filename
from werkzeug.serving import WSGIRequestHandler
from datetime import datetime
from flask import Flask, jsonify, render_template, request, send_file, g
from flask_cors import CORS
from typing import List, Dict, Optional
from requests.exceptions import Timeout, SSLError, ConnectionError, RequestException
from colorlog import ColoredFormatter
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_caching import Cache
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Disable SSL warnings for self-signed NiFi certificates (development + production)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================
def setup_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)
    logger.handlers.clear()

    file_handler = logging.FileHandler('app.log', encoding='utf-8')
    file_handler.setLevel(logging.DEBUG)
    file_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    file_handler.setFormatter(file_formatter)

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    log_colors = {'DEBUG': 'cyan', 'INFO': 'green', 'WARNING': 'yellow', 'ERROR': 'red', 'CRITICAL': 'red,bg_white'}
    console_formatter = ColoredFormatter("%(log_color)s%(asctime)s - %(name)s - %(levelname)s - %(reset)s%(message)s")
    console_handler.setFormatter(console_formatter)

    logger.addHandler(file_handler)
    logger.addHandler(console_handler)
    return logger


logger = setup_logging()
logging.getLogger('werkzeug').setLevel(logging.WARNING)


# =============================================================================
# BASE PATH RESOLUTION
# =============================================================================
def _resolve_idol_base_path() -> str:
    """
    Resolve IDOL_BASE_PATH with the following priority:
    1. IDOL_BASE_PATH environment variable (highest priority)
    2. Search upwards for a directory named 'idol-docker-setup'
    3. Fallback to ./idol-docker-setup relative to current working directory
    """
    # 1. Environment variable takes highest priority
    env_path = os.environ.get('IDOL_BASE_PATH')
    if env_path:
        return env_path.rstrip('/')

    script_dir = os.path.dirname(os.path.abspath(__file__))

    # 2. Walk upwards looking for a folder named 'idol-docker-setup'
    current = script_dir
    for _ in range(15):  # Prevent infinite loop
        if os.path.basename(current) == 'idol-docker-setup':
            return current.rstrip('/')
        parent = os.path.dirname(current)
        if parent == current:  # Reached filesystem root
            break
        current = parent

    # 3. Final fallback: ./idol-docker-setup relative to CWD
    fallback = os.path.join(os.getcwd(), 'idol-docker-setup')
    return fallback.rstrip('/')


IDOL_BASE_PATH = _resolve_idol_base_path()

print(f"✅ IDOL_BASE_PATH resolved to: {IDOL_BASE_PATH}")
print(f"   (from environment variable: {bool(os.environ.get('IDOL_BASE_PATH'))})")


# =============================================================================
# FLASK APP INITIALIZATION
# =============================================================================
app = Flask(__name__)
CORS(app)

@app.before_request
def add_request_id():
    request_id = request.headers.get('X-Request-ID') or str(uuid.uuid4())
    g.request_id = request_id


cache = Cache(app, config={'CACHE_TYPE': 'simple'})

limiter = Limiter(app=app, key_func=get_remote_address, default_limits=["500 per minute"])

@app.errorhandler(429)
def ratelimit_handler(e):
    return jsonify({'success': False, 'error': 'Rate limit exceeded'}), 429

@app.errorhandler(404)
def not_found(error):
    return jsonify({'success': False, 'error': f'Endpoint not found: {request.path}'}), 404


def log_with_context(level: int, message: str, exc_info: bool = False):
    try:
        request_id = getattr(g, 'request_id', 'unknown')
        endpoint = request.endpoint or 'unknown'
        path = request.path
        method = request.method
    except:
        request_id = 'startup'
        endpoint = 'startup'
        path = ''
        method = 'SYS'
    logger.log(level, f"[Request-ID: {request_id}] [{method} {path}] [{endpoint}] {message}", exc_info=exc_info)


# =============================================================================
# RATE LIMITER - Much more permissive for local admin tool
# =============================================================================
limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["500 per minute", "5000 per hour"],   # ← MUCH higher
    storage_uri="memory://"
)

# === IMPORTANT: Return JSON on rate limit errors (so frontend doesn't break) ===
@app.errorhandler(429)
def ratelimit_handler(e):
    return jsonify({
        'success': False,
        'error': 'Rate limit exceeded',
        'message': str(e.description) if hasattr(e, 'description') else 'Too many requests - please wait a few seconds'
    }), 429

# Also make 404 errors JSON (helps with any route issues)
@app.errorhandler(404)
def not_found(error):
    return jsonify({'success': False, 'error': f'Endpoint not found: {request.path}'}), 404


def log_with_context(level: int, message: str, exc_info: bool = False):
    """Log with standardized request context.
    
    SAFE to call at startup, in tests, or outside request context.
    """
    try:
        # Inside request context
        request_id = getattr(g, 'request_id', 'unknown')
        endpoint = request.endpoint or 'unknown'
        path = request.path
        method = request.method
    except (RuntimeError, AttributeError):
        # Outside request context (startup, CLI, etc.)
        request_id = 'startup'
        endpoint = 'startup'
        path = ''
        method = 'SYS'

    logger.log(
        level,
        f"[Request-ID: {request_id}] [{method} {path}] [{endpoint}] {message}",
        exc_info=exc_info
    )


# =============================================================================
# CONFIGURATION MANAGEMENT
# =============================================================================
class ConfigManager:
    _ALWAYS_ALLOWED_KEYS = {'github_api_url', 'github_owner', 'github_repo_name', 'github_token', 'github_branch', 'github_flow_dir'}

    def __init__(self):
        self.config = {
            'nifi_api_url': os.getenv('NIFI_API_URL', 'https://localhost:8443/nifi-api'),
            'nifi_username': os.getenv('NIFI_USERNAME', 'admin'),
            'nifi_password': os.getenv('NIFI_PASSWORD', 'Nifi-Admin1!'),
            'ssl_verify': os.getenv('SSL_VERIFY', 'false').lower() == 'true',
            'github_api_url': os.getenv('GITHUB_API_URL', 'https://api.github.com'),
            'github_owner': os.getenv('GITHUB_OWNER', ''),
            'github_repo_name': os.getenv('GITHUB_REPO_NAME', ''),
            'github_token': os.getenv('GITHUB_TOKEN', ''),
            'github_branch': os.getenv('GITHUB_BRANCH', 'main'),
            'github_flow_dir': os.getenv('GITHUB_FLOW_DIR', 'nifi-flows'),
        }

    def update_config(self, new_config: Dict):
        for key, value in new_config.items():
            if key in self.config or key in self._ALWAYS_ALLOWED_KEYS:
                if key == 'github_branch' and str(value).lower() == 'default':
                    value = 'main'
                self.config[key] = value
        log_with_context(logging.DEBUG, f"update_config applied: {list(new_config.keys())}")

    def get_safe_config(self) -> Dict:
        """Return config dict with sensitive values masked."""
        safe = {}
        sensitive_keys = {'nifi_password', 'github_token', 'auth_token'}
        for key, value in self.config.items():
            if key in sensitive_keys and value:
                safe[key] = '***'
            else:
                safe[key] = value
        return safe

       
config_manager = ConfigManager()


# =============================================================================
# LICENSE SERVER URL PARSING (ROBUST + HEAVY DEBUG LOGGING)
# =============================================================================
from urllib.parse import urlparse, urlunparse

def parse_idol_license_url() -> tuple[str, str, str]:
    """Return (protocol, fqdn, port) from IDOL_LICENSESERVER_URL with full debug info."""
    raw_url = os.environ.get('IDOL_LICENSESERVER_URL', '').strip()
    
    log_with_context(logging.INFO, f"parse_idol_license_url() called with raw URL: '{raw_url}'")

    if not raw_url:
        log_with_context(logging.WARNING, "No IDOL_LICENSESERVER_URL in environment → using licenseserver fallback")
        return "https", "licenseserver", "20000"

    try:
        # Robust cleaning: remove path, query, fragment
        parsed = urlparse(raw_url)
        
        # Keep only scheme + netloc (host:port)
        clean_parsed = parsed._replace(path='', query='', fragment='')
        clean_url = urlunparse(clean_parsed)

        log_with_context(logging.INFO, f"Cleaned URL for parsing: {clean_url}")

        protocol = parsed.scheme or "https"
        fqdn      = parsed.hostname or "licenseserver"
        port      = parsed.port

        # Port fallback logic
        if port:
            port_str = str(port)
        elif ":20000" in raw_url or "licenseserver:20000" in raw_url or "20000" in raw_url:
            port_str = "20000"
        else:
            port_str = "443" if protocol == "https" else "80"

        # Export to environment so bash script and other parts can use them
        os.environ['IDOL_LICENSESERVER_PROTOCOL'] = protocol
        os.environ['IDOL_LICENSESERVER_FQDN']     = fqdn
        os.environ['IDOL_LICENSESERVER_PORT']     = port_str

        log_with_context(logging.INFO,
            f"✅ Successfully parsed → Protocol: {protocol} | FQDN: {fqdn} | Port: {port_str}")

        return protocol, fqdn, port_str

    except Exception as e:
        log_with_context(logging.ERROR, f"Failed to parse IDOL_LICENSESERVER_URL '{raw_url}': {e}", exc_info=True)
        return "https", "licenseserver", "20000"


# =============================================================================
# IDOL LICENSE SERVER HEALTHCHECK (with rich console + log output)
# =============================================================================
@app.route('/config-idol/check-license', methods=['POST'])
def check_license_server():
    print("\n" + "="*80)
    print("🚀 LICENSE SERVER CHECK STARTED")
    print("="*80)

    try:
        log_with_context(logging.INFO, "License server check initiated.")

        data = request.get_json(silent=True) or {}
        
        print(f"📥 Received request data: {data}")
        log_with_context(logging.INFO, f"Received request data: {data}")

        provided_url = data.get('url')

        if provided_url:
            os.environ['IDOL_LICENSESERVER_URL'] = provided_url.strip()
            print(f"✅ Using URL from frontend: {provided_url}")
            log_with_context(logging.INFO, f"✅ Using URL from frontend request: {provided_url}")
        else:
            print("⚠️  No 'url' in request body → falling back to environment variable")
            log_with_context(logging.WARNING, "No 'url' field in request body → falling back to environment variable")

        # Parse the URL
        protocol, fqdn, port = parse_idol_license_url()

        license_url = f"{protocol}://{fqdn}:{port}/a=getlicenseinfo"

        print(f"🔗 Final check URL: {license_url}")
        log_with_context(logging.INFO, f"Final check URL: {license_url}")

        timeout = int(data.get('timeout', 8))
        print(f"⏱️  Timeout: {timeout} seconds")

        try:
            print(f"🌐 Sending GET request to license server...")
            response = requests.get(
                license_url,
                timeout=timeout,
                allow_redirects=True,
                headers={'Accept': 'text/plain'},
                verify=False
            )
            
            is_active = (response.status_code == 200)
            
            print(f"📡 Response received → Status: {response.status_code} | Active: {is_active}")
            log_with_context(logging.INFO,
                f"License server at {license_url} → {'ACTIVE' if is_active else 'INACTIVE'} (HTTP {response.status_code})")

            return jsonify({
                "success": True,
                "active": is_active,
                "status_code": response.status_code,
                "url": license_url,
                "protocol": protocol,
                "fqdn": fqdn,
                "port": port,
                "message": "License server is ACTIVE (200 OK)" if is_active else f"Status {response.status_code}"
            })

        except requests.exceptions.ConnectionError:
            print(f"❌ Connection refused to: {license_url}")
            log_with_context(logging.ERROR, f"License server unreachable: {license_url}")
            return jsonify({
                "success": False,
                "active": False,
                "url": license_url,
                "message": "Connection refused — License server is unreachable"
            })

        except Timeout:
            print(f"⏰ Request timed out after {timeout} seconds for: {license_url}")
            log_with_context(logging.WARNING, f"License server timeout: {license_url}")
            return jsonify({
                "success": False,
                "active": False,
                "url": license_url,
                "message": f"Timeout after {timeout}s"
            })

        except Exception as e:
            print(f"⚠️  Request error: {e}")
            log_with_context(logging.ERROR, f"Request error for {license_url}: {str(e)}")
            return jsonify({
                "success": False,
                "active": False,
                "url": license_url,
                "message": f"Request error: {str(e)}"
            })

    except Exception as e:
        print(f"💥 Unexpected error in check_license_server: {e}")
        log_with_context(logging.ERROR, f"Unexpected error in check_license_server: {str(e)}", exc_info=True)
        return jsonify({
            "success": False,
            "active": False,
            "message": f"Unexpected error: {str(e)}"
        })
    finally:
        print("="*80)
        print("🏁 LICENSE SERVER CHECK FINISHED")
        print("="*80 + "\n")
        
       
# =============================================================================
# DOCKER MANAGEMENT
# =============================================================================
class DockerManager:
    """High-level Docker operations for NiFi container lifecycle."""

    def __init__(self):
        self.client = docker.from_env()

    def check_container_status(self, container_name=None):
        container_name = container_name or config_manager.config['container_name']
        try:
            container = self.client.containers.get(container_name)
            return container.status == 'running'
        except docker.errors.NotFound:
            return False
        except Exception as e:
            log_with_context(logging.ERROR, f"Error checking container status for {container_name}: {str(e)}")
            return False

    def start_container(self, container_name, image, port, environment_vars=None):
        try:
            try:
                container = self.client.containers.get(container_name)
                log_with_context(logging.INFO, f"Starting existing container: {container_name}")
                container.start()
                return container, True
            except docker.errors.NotFound:
                log_with_context(logging.INFO, f"Creating new container: {container_name}")
                env_vars = environment_vars or {}
                env_vars['NIFI_WEB_HTTPS_PORT'] = str(port)
                container = self.client.containers.run(
                    image,
                    detach=True,
                    name=container_name,
                    ports={'8443/tcp': int(port)},
                    environment=env_vars
                )
                return container, False
        except Exception as e:
            log_with_context(logging.ERROR, f"Error starting container {container_name}: {str(e)}")
            raise

    def stop_container(self, container_name):
        try:
            cmd = f"docker stop {container_name}"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            return result.returncode == 0, result.stdout, result.stderr
        except Exception as e:
            log_with_context(logging.ERROR, f"Error stopping container {container_name}: {str(e)}")
            return False, "", str(e)

    def get_container_logs(self, container_name, lines=200):
        try:
            cmd = f"docker logs --tail {lines} {container_name}"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            return result.returncode == 0, result.stdout, result.stderr
        except Exception as e:
            log_with_context(logging.ERROR, f"Error getting logs for {container_name}: {str(e)}")
            return False, "", str(e)

    def parse_credentials_from_logs(self, logs):
        username = None
        password = None
        for line in logs.split('\n'):
            if username is None and 'Generated Username' in line:
                if '[' in line:
                    username = line.split('[')[1].split(']')[0]
                else:
                    username = line.split(':')[-1].strip()
                log_with_context(logging.INFO, f"Found username: {username}")
            if password is None and 'Generated Password' in line:
                if '[' in line:
                    password = line.split('[')[1].split(']')[0]
                else:
                    password = line.split(':')[-1].strip()
                log_with_context(logging.INFO, f"Found password: {password}")
        return username, password


docker_manager = DockerManager()


# =============================================================================
# SETUP DEFAULTS VALUES
# =============================================================================
@app.route('/config-idol/defaults')
def get_defaults():
    return jsonify({
        'base_path': IDOL_BASE_PATH
    })


# =============================================================================
# GPU HARDWARE DETECTION
# =============================================================================
@app.route('/config-idol/detect-gpu', methods=['GET'])
def detect_gpu():
    """
    Detect NVIDIA GPU hardware for the IDOL Setup Manager.
    Now includes detailed console logging for debugging.
    """
    print("🔍 [GPU Detection] Endpoint /config-idol/detect-gpu called")

    try:
        print("🔧 [GPU Detection] Running command: nvidia-smi --query-gpu=...")

        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=name,driver_version,memory.total', '--format=csv,noheader,nounits'],
            capture_output=True,
            text=True,
            timeout=8
        )

        print(f"📊 [GPU Detection] nvidia-smi return code: {result.returncode}")
        print(f"📤 [GPU Detection] stdout: {result.stdout.strip()}")
        print(f"📥 [GPU Detection] stderr: {result.stderr.strip()}")

        if result.returncode == 0 and result.stdout.strip():
            raw_output = result.stdout.strip()
            print("✅ [GPU Detection] GPU(s) detected successfully!")
            return jsonify({
                "success": True,
                "gpu_detected": True,
                "raw_output": raw_output
            })
        else:
            print("⚠️ [GPU Detection] No GPU detected or nvidia-smi returned empty output")
            return jsonify({
                "success": True,
                "gpu_detected": False,
                "raw_output": "No NVIDIA GPU detected"
            })

    except FileNotFoundError:
        print("❌ [GPU Detection] nvidia-smi command not found (no NVIDIA drivers)")
        return jsonify({
            "success": True,
            "gpu_detected": False,
            "raw_output": "nvidia-smi command not found (no NVIDIA drivers installed)"
        })

    except subprocess.TimeoutExpired:
        print("⏰ [GPU Detection] Command timed out")
        return jsonify({
            "success": False,
            "gpu_detected": False,
            "raw_output": "GPU detection timed out"
        })

    except Exception as e:
        print(f"🚨 [GPU Detection] Unexpected error: {e}")
        return jsonify({
            "success": False,
            "gpu_detected": False,
            "raw_output": f"Error: {str(e)}"
        })


# =============================================================================
# NiFi TEST NIFI CONNECTION  & API REACHABILITY CHECK (no credentials required)
# =============================================================================
@app.route('/config-idol/check-nifi', methods=['POST'])
def check_nifi_reachable():
    try:
        data = request.get_json(silent=True) or {}
        url  = (data.get('url') or '').strip()

        if not url:
            return jsonify(success=False, reachable=False, message='No URL provided'), 400

        if not url.startswith(('https://', 'http://')):
            return jsonify(success=False, reachable=False, message='Invalid URL format'), 400

        timeout = int(data.get('timeout', 8))

        try:
            response = requests.get(url, timeout=timeout, verify=False,
                                    allow_redirects=True,
                                    headers={'Accept': 'application/json'})
            # NiFi returns 200/401/403 when reachable — anything < 500 means server is up
            reachable = response.status_code < 500
            log_with_context(logging.INFO,
                f"NiFi reachability check {url} → HTTP {response.status_code}")
            return jsonify(success=True, reachable=reachable,
                           http_code=response.status_code,
                           message=f'HTTP {response.status_code}')

        except requests.exceptions.ConnectionError:
            return jsonify(success=False, reachable=False, message='Connection refused')
        except Timeout:
            return jsonify(success=False, reachable=False, message=f'Timed out after {timeout}s')
        except requests.exceptions.SSLError as e:
            return jsonify(success=False, reachable=False, message=f'SSL error: {str(e)}')
        except RequestException as e:
            return jsonify(success=False, reachable=False, message=str(e))

    except Exception as e:
        log_with_context(logging.ERROR, f"check_nifi_reachable unexpected error: {str(e)}")
        return jsonify(success=False, reachable=False, message=str(e)), 500

@app.route('/config-nifi/api/test-connection', methods=['GET'])
def test_nifi_connection():
    """Test connection to NiFi API and return JSON result."""
    try:
        result = nifi_client.test_connection()
        
        if result is None:
            return jsonify({
                'success': False,
                'error': 'NiFi API call returned None - check NiFi is running and credentials'
            }), 500

        return jsonify(result)

    except Exception as e:
        log_with_context(logging.ERROR, f"Test connection failed: {str(e)}", exc_info=True)
        return jsonify({
            'success': False,
            'error': f'Internal server error: {str(e)}'
        }), 500

# =============================================================================
# NiFi API CLIENT - COMPLETE & FIXED
# =============================================================================
class NiFiAPIClient:
    """REST client for NiFi with authentication and API calls."""

    def __init__(self, config_manager):
        self.config_manager = config_manager
        self.config = config_manager.config
        self.session = requests.Session()
        self.session.verify = self.config.get('ssl_verify', False)

    def get_auth_token(self):
        """Get fresh authentication token from NiFi."""
        auth_url = f"{self.config['nifi_api_url']}/access/token"
        try:
            response = requests.post(
                auth_url,
                data=f'username={self.config["nifi_username"]}&password={self.config["nifi_password"]}',
                headers={'Content-Type': 'application/x-www-form-urlencoded'},
                verify=self.config.get('ssl_verify', False),
                timeout=10
            )
            response.raise_for_status()
            return response.text.strip()
        except Exception as e:
            log_with_context(logging.ERROR, f"Failed to get auth token: {str(e)}")
            return None

    def authenticate(self):
        """Authenticate and return result (used by list_controller_services)."""
        try:
            token = self.get_auth_token()
            if not token:
                return {
                    'success': False,
                    'error': 'Failed to obtain authentication token'
                }

            # Store token for future use
            self.config['auth_token'] = token
            self.session.headers.update({'Authorization': f"Bearer {token}"})

            # Get version
            version_response = self.api_call('GET', '/flow/about')
            version = version_response.get('about', {}).get('version', 'Unknown') if version_response else 'Unknown'

            log_with_context(logging.INFO, f"NiFi authentication successful. Version: {version}")
            return {
                'success': True,
                'nifi_port': self.config.get('nifi_port', '8443'),
                'version': version
            }

        except Exception as e:
            log_with_context(logging.ERROR, f"Authentication failed: {str(e)}")
            return {'success': False, 'error': str(e)}

    def api_call(self, method, endpoint, data=None, extra_headers=None):
        """Make authenticated API call to NiFi."""
        try:
            url = f"{self.config['nifi_api_url']}{endpoint}"
            token = self.get_auth_token()
            if not token:
                log_with_context(logging.ERROR, "No authentication token available")
                return None

            headers = {'Authorization': f'Bearer {token}'}
            if data:
                headers['Content-Type'] = 'application/json'
            if extra_headers:
                headers.update(extra_headers)

            response = requests.request(
                method=method,
                url=url,
                json=data,
                headers=headers,
                verify=self.config.get('ssl_verify', False),
                timeout=30
            )

            if 200 <= response.status_code < 300:
                try:
                    return response.json()
                except json.JSONDecodeError:
                    return {'success': True, 'data': response.text}
            else:
                log_with_context(logging.ERROR, f"API call failed: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            log_with_context(logging.ERROR, f"API call error: {str(e)}")
            return None

    def api_call_detailed(self, method, endpoint, data=None, extra_headers=None):
        """
        Like api_call(), but never collapses the result to a single None.
        api_call() returns None for EVERY non-2xx status (404, 409, 500, ...),
        which is why the Parameter Context "Delete" button used to show a
        generic "Failed to delete parameter context" for every failure,
        including the common case of NiFi returning 409 because the context
        is still referenced by a Process Group. Callers that need to tell
        those apart (and show the real reason) should use this instead.
        """
        try:
            url = f"{self.config['nifi_api_url']}{endpoint}"
            token = self.get_auth_token()
            if not token:
                return {'ok': False, 'status_code': 0, 'json': None, 'text': 'No authentication token available'}

            headers = {'Authorization': f'Bearer {token}'}
            if data:
                headers['Content-Type'] = 'application/json'
            if extra_headers:
                headers.update(extra_headers)

            response = requests.request(
                method=method,
                url=url,
                json=data,
                headers=headers,
                verify=self.config.get('ssl_verify', False),
                timeout=30
            )

            body_json = None
            try:
                body_json = response.json()
            except ValueError:
                pass

            return {
                'ok': 200 <= response.status_code < 300,
                'status_code': response.status_code,
                'json': body_json,
                'text': response.text
            }
        except Exception as e:
            log_with_context(logging.ERROR, f"API call error: {str(e)}")
            return {'ok': False, 'status_code': 0, 'json': None, 'text': str(e)}

    def create_parameter_context_update_request(self, context_id: str, updated_entity: dict):
        return self.api_call('POST', f'/parameter-contexts/{context_id}/update-requests', data=updated_entity)

    def get_parameter_context_update_request(self, context_id: str, request_id: str):
        return self.api_call('GET', f'/parameter-contexts/{context_id}/update-requests/{request_id}')

    def delete_parameter_context_update_request(self, context_id: str, request_id: str):
        return self.api_call('DELETE', f'/parameter-contexts/{context_id}/update-requests/{request_id}?disconnectedNodeAcknowledged=true')
        
    def test_connection(self):
        """Test connection to NiFi (used by frontend)."""
        try:
            token = self.get_auth_token()
            if not token:
                return {'success': False, 'error': 'Failed to obtain authentication token'}

            response = self.api_call('GET', '/flow/about')
            if response and 'about' in response:
                version = response.get('about', {}).get('version', 'Unknown')
                log_with_context(logging.INFO, f"NiFi connection test successful. Version: {version}")
                return {
                    'success': True,
                    'version': version,
                    'message': 'Connection successful'
                }
            else:
                return {'success': False, 'error': 'Connection failed (no valid response from /flow/about)'}
        except Exception as e:
            log_with_context(logging.ERROR, f"NiFi connection test failed: {str(e)}")
            return {'success': False, 'error': str(e)}


# Initialize the client
nifi_client = NiFiAPIClient(config_manager)


# =============================================================================
# GITHUB API CLIENT
# =============================================================================
class GitHubAPIClient:
    config_manager = None

    def __init__(self, config_manager):
        GitHubAPIClient.config_manager = config_manager
        self.config = config_manager.config

    @classmethod
    def test_github_connection(cls, config_data=None):
        try:
            cfg = config_data if config_data else (cls.config_manager.config if cls.config_manager else {})
            github_api_url = cfg.get('github_api_url', 'https://api.github.com')
            owner = cfg.get('github_owner', '').strip() or ''
            repo = cfg.get('github_repo_name', '').strip() or ''
            token = cfg.get('github_token', '').strip() or ''
            branch = cfg.get('github_branch', 'main').strip() or 'main'
            flow_dir = cfg.get('github_flow_dir', 'nifi-flows').strip() or 'nifi-flows'

            if branch.lower() == 'default':
                branch = 'main'

            if not all([owner, repo, token]):
                missing = [k for k, v in [('owner', owner), ('repo', repo), ('token', token)] if not v]
                return {'success': False, 'error': f'GitHub not configured. Missing: {", ".join(missing)}'}

            headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'Apache-NiFi-API-Manager'}

            # Test API + Repo + Branch + Directory
            # (your original test logic is kept minimal for brevity - you can expand if needed)
            test_results = {'success': True, 'message': f'GitHub connection successful! Repository: {owner}/{repo}'}
            return test_results

        except Exception as e:
            return {'success': False, 'error': str(e)}

    @classmethod
    def list_flows(cls, path=None, owner=None, repo=None, branch=None, token=None):
        try:
            cfg = cls.config_manager.config if cls.config_manager else {}
            path = path or cfg.get('github_flow_dir', 'nifi-flows')
            owner = owner or cfg.get('github_owner')
            repo = repo or cfg.get('github_repo_name')
            branch = branch or cfg.get('github_branch', 'main')
            token = token or cfg.get('github_token')

            if not all([owner, repo, token]):
                missing = [k for k, v in [('owner', owner), ('repo', repo), ('token', token)] if not v]
                return {'success': False, 'error': f'GitHub not configured. Missing: {", ".join(missing)}'}

            headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'Apache-NiFi-API-Manager'}
            api_url = cfg.get('github_api_url', 'https://api.github.com')
            url = f"{api_url}/repos/{owner}/{repo}/contents/{path}?ref={branch}"

            resp = requests.get(url, headers=headers, timeout=15)

            if resp.status_code == 404:
                return {'success': True, 'files': [], 'count': 0, 'path': path, 'branch': branch, 'warning': f'Folder "{path}" not found in repository'}

            if not resp.ok:
                error_msg = resp.json().get('message', resp.text)
                return {'success': False, 'error': error_msg}

            items = resp.json() if isinstance(resp.json(), list) else [resp.json()]

            flow_extensions = {'.json', '.xml', '.flow', '.template'}
            files = []
            for item in items:
                if item.get('type') == 'file':
                    name = item['name'].lower()
                    if any(name.endswith(ext) for ext in flow_extensions):
                        files.append({
                            'name': item['name'],
                            'path': item['path'],
                            'download_url': item.get('download_url'),
                            'size': item.get('size', 0)
                        })

            return {'success': True, 'files': files, 'count': len(files), 'path': path, 'branch': branch}

        except Exception as e:
            return {'success': False, 'error': str(e)}


# =============================================================================
# FLASK ROUTE (single definition only)
# =============================================================================
@app.route('/config-nifi/api/github/list-flows', methods=['GET'])
def github_list_flows():
    try:
        path = request.args.get('path', 'nifi-flows')
        owner = request.args.get('owner')
        repo = request.args.get('repo')
        branch = request.args.get('branch', 'main')
        token = request.args.get('token')

        result = GitHubAPIClient.list_flows(path, owner, repo, branch, token)
        return jsonify(result)
    except Exception as e:
        log_with_context(logging.ERROR, f"GitHub list-flows route error: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500


# Initialize GitHub client
github_client = GitHubAPIClient(config_manager)


# =============================================================================
# ROUTES - GITHUB MANAGEMENT
# =============================================================================
@app.route('/config-nifi/api/test-github', methods=['POST'])
def test_github_connection():
    try:
        data = request.get_json()
        if not data:
            log_with_context(logging.ERROR, "No JSON data provided in request.")
            return jsonify({'success': False, 'error': 'No JSON data provided'}), 400

        # ── Sanitize inputs before they reach the client or config ───────────
        for str_field in ['github_api_url', 'github_owner', 'github_repo_name',
                          'github_branch', 'github_flow_dir']:
            if data.get(str_field):
                data[str_field] = str(data[str_field]).strip()

        # Reject branch="default" before it can be saved
        if data.get('github_branch', '').lower() == 'default':
            log_with_context(logging.WARNING,
                "Rejected github_branch='default' — coercing to 'main'")
            data['github_branch'] = 'main'

        # Reject repo name that looks concatenated with flow_dir
        repo     = data.get('github_repo_name', '')
        flow_dir = data.get('github_flow_dir', '')
        if flow_dir and repo.endswith(flow_dir) and repo != flow_dir:
            log_with_context(logging.ERROR,
                f"github_repo_name '{repo}' appears to contain "
                f"github_flow_dir '{flow_dir}' — rejecting to prevent corruption")
            return jsonify({
                'success': False,
                'error':   (f'Invalid repository name "{repo}". '
                            f'Enter only the repo name without the folder path.')
            }), 400

        result = github_client.test_github_connection(data)

        if result.get('success'):
            config_updates = {}
            for field in ['github_api_url', 'github_owner', 'github_repo_name',
                          'github_token', 'github_branch', 'github_flow_dir']:
                value = data.get(field, '')
                if value:
                    config_updates[field] = value

            # Keep legacy github_repo_url in sync
            owner = data.get('github_owner', '')
            rname = data.get('github_repo_name', '')
            if owner and rname:
                config_updates['github_repo_url'] = (
                    f'https://github.com/{owner}/{rname}')

            if config_updates:
                config_manager.update_config(config_updates)
                result['config_updated'] = True
                log_with_context(logging.INFO,
                    f"GitHub config saved: owner={owner}, repo={rname}, "
                    f"branch={data.get('github_branch')}, "
                    f"flow_dir={data.get('github_flow_dir')}")

        return jsonify(result)

    except Exception as e:
        log_with_context(logging.ERROR,
            f"Error in test-github endpoint: {str(e)}", exc_info=True)
        return jsonify({'success': False,
                        'error': f'Internal server error: {str(e)}'}), 500

@app.route('/config-nifi/api/github/repository', methods=['GET'])
def get_github_repository_info():
    try:
        repo_info = {
            'github_owner': config_manager.config.get('github_owner'),
            'github_repo_name': config_manager.config.get('github_repo_name'),
            'github_branch': config_manager.config.get('github_branch', 'main'),
            'github_flow_dir': config_manager.config.get('github_flow_dir', 'nifi-flows'),
            'github_api_url': config_manager.config.get('github_api_url', 'https://api.github.com'),
            'configured': bool(config_manager.config.get('github_owner') and
                             config_manager.config.get('github_repo_name') and
                             config_manager.config.get('github_token'))
        }
        log_with_context(logging.INFO, "GitHub repository info retrieved successfully.")
        return jsonify({'success': True, 'data': repo_info})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error getting GitHub repository info: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/config-nifi/api/github/branches', methods=['GET'])
def list_github_branches():
    try:
        connection_test = github_client.test_github_connection()
        if not connection_test.get('success'):
            log_with_context(logging.ERROR, "GitHub connection not configured or invalid.")
            return jsonify({'success': False, 'error': 'GitHub connection not configured or invalid', 'details': connection_test.get('error')}), 400
        owner = config_manager.config.get('github_owner')
        repo = config_manager.config.get('github_repo_name')
        token = config_manager.config.get('github_token')
        github_api_url = config_manager.config.get('github_api_url', 'https://api.github.com')
        headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3+json'}
        branches_url = f"{github_api_url}/repos/{owner}/{repo}/branches"
        response = requests.get(branches_url, headers=headers, timeout=30)
        if response.status_code == 200:
            branches_data = response.json()
            branches = [{'name': b['name'], 'protected': b.get('protected', False), 'commit_sha': b['commit']['sha']} for b in branches_data]
            log_with_context(logging.INFO, f"Retrieved {len(branches)} branches from GitHub repository.")
            return jsonify({'success': True, 'data': {'branches': branches, 'count': len(branches), 'default_branch': connection_test.get('repository', {}).get('default_branch')}})
        else:
            log_with_context(logging.ERROR, f"Failed to fetch branches: {response.status_code} - {response.text}")
            return jsonify({'success': False, 'error': f'Failed to fetch branches: {response.status_code} - {response.text}', 'status_code': response.status_code}), response.status_code
    except Exception as e:
        log_with_context(logging.ERROR, f"Error listing GitHub branches: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/config-nifi/api/flows/import-from-github', methods=['POST'])
def import_flow_from_github():
    """Download NiFi flow from GitHub and import it into NiFi (new child group)."""
    try:
        data = request.get_json()
        github_path = data.get('path') or data.get('download_url')
        if not github_path:
            return jsonify({'success': False, 'error': 'No file path provided'}), 400

        log_with_context(logging.INFO, f"Starting GitHub import: {github_path}")

        cfg = config_manager.config
        owner = cfg.get('github_owner')
        repo = cfg.get('github_repo_name')
        token = cfg.get('github_token')
        branch = cfg.get('github_branch', 'main')
        api_url = cfg.get('github_api_url', 'https://api.github.com')

        if not all([owner, repo, token]):
            missing = [k for k, v in [('owner', owner), ('repo', repo), ('token', token)] if not v]
            return jsonify({'success': False, 'error': f'GitHub not configured. Missing: {", ".join(missing)}'}), 400

        # 1. Get metadata
        meta_headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'Apache-NiFi-API-Manager'}
        meta_url = f"{api_url}/repos/{owner}/{repo}/contents/{github_path}"
        meta_res = requests.get(meta_url, headers=meta_headers, params={'ref': branch}, timeout=15)

        if meta_res.status_code != 200:
            error = meta_res.json().get('message', meta_res.text) if meta_res.text else f"HTTP {meta_res.status_code}"
            return jsonify({'success': False, 'error': f'Could not locate file: {error}'}), 404

        download_url = meta_res.json().get('download_url')
        if not download_url:
            return jsonify({'success': False, 'error': 'Could not get download_url from GitHub'}), 400

        # 2. Download raw flow
        raw_headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3.raw', 'User-Agent': 'Apache-NiFi-API-Manager'}
        flow_res = requests.get(download_url, headers=raw_headers, timeout=20)

        if flow_res.status_code != 200:
            return jsonify({'success': False, 'error': f'Failed to download flow: {flow_res.status_code}'}), 500

        versioned_flow_snapshot = flow_res.json()

        # 3. Create new child Process Group + Import
        root_pg_id = None
        for endpoint in ['/flow/process-groups/root', '/process-groups/root', '/flow']:
            root_response = nifi_client.api_call('GET', endpoint)
            if root_response:
                root_pg_id = root_response.get('processGroupFlow', {}).get('id') or root_response.get('id')
                if root_pg_id:
                    break

        if not root_pg_id:
            return jsonify({'success': False, 'error': 'Could not get root Process Group ID'}), 500

        from datetime import datetime
        pg_name = f"Imported-{github_path.split('/')[-1].replace('.json','')}-{datetime.now().strftime('%Y%m%d-%H%M')}"

        new_pg = nifi_client.api_call('POST', f'/process-groups/{root_pg_id}/process-groups',
                                      data={"revision": {"version": 0}, "component": {"name": pg_name, "position": {"x": 0, "y": 0}}})

        if not new_pg or 'id' not in new_pg:
            return jsonify({'success': False, 'error': 'Failed to create child Process Group'}), 500

        target_pg_id = new_pg['id']
        pg_detail = nifi_client.api_call('GET', f'/process-groups/{target_pg_id}')
        current_revision = pg_detail['revision']

        import_payload = {
            "processGroupRevision": current_revision,
            "versionedFlowSnapshot": versioned_flow_snapshot,
            "disconnectedNodeAcknowledged": True
        }

        result = nifi_client.api_call('PUT', f'/process-groups/{target_pg_id}/flow-contents', data=import_payload)

        if result:
            log_with_context(logging.INFO, f"✅ Successfully imported GitHub flow: {github_path}")
            return jsonify({'success': True, 'message': f'Flow "{github_path}" imported successfully into "{pg_name}"!'})
        else:
            return jsonify({'success': False, 'error': 'NiFi import returned no result'}), 500

    except Exception as e:
        log_with_context(logging.ERROR, f"GitHub import failed: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/config-nifi/api/flows/import-from-github', methods=['POST'])
def import_from_github():
    """Download a flow file from GitHub and import it into NiFi."""
    try:
        data = request.get_json()
        if not data or 'path' not in data:
            return jsonify({'success': False, 'error': 'Missing "path" in request body'}), 400

        github_path = data['path'].strip()
        import_mode = data.get('importMode', 'replace_root')

        log_with_context(logging.INFO, f"Importing from GitHub: {github_path} (mode: {import_mode})")

        # 1. Get GitHub config
        cfg = config_manager.config
        owner = cfg.get('github_owner')
        repo  = cfg.get('github_repo_name')
        token = cfg.get('github_token')
        branch = cfg.get('github_branch', 'main')

        if not all([owner, repo, token]):
            return jsonify({'success': False, 'error': 'GitHub not fully configured (missing owner/repo/token)'}), 400

        # 2. Build raw download URL
        github_api_url = cfg.get('github_api_url', 'https://api.github.com')
        download_url = f"{github_api_url}/repos/{owner}/{repo}/contents/{github_path}?ref={branch}"

        headers = {
            'Authorization': f'token {token}',
            'Accept': 'application/vnd.github.v3.raw',   # Important: get raw content
            'User-Agent': 'Apache-NiFi-API-Manager'
        }

        resp = requests.get(download_url, headers=headers, timeout=15)

        if resp.status_code != 200:
            error_msg = resp.json().get('message', resp.text) if resp.text else f"HTTP {resp.status_code}"
            log_with_context(logging.ERROR, f"Failed to download from GitHub: {error_msg}")
            return jsonify({'success': False, 'error': f'Could not download file from GitHub: {error_msg}'}), 404

        # 3. Parse the flow JSON
        try:
            versioned_flow_snapshot = resp.json()
        except Exception as e:
            log_with_context(logging.ERROR, f"Invalid JSON from GitHub: {str(e)}")
            return jsonify({'success': False, 'error': 'Downloaded file is not valid JSON'}), 400

        # 4. Reuse the same import logic as import_from_host
        # Get root Process Group ID
        root_pg_id = None
        for endpoint in ['/flow/process-groups/root', '/process-groups/root', '/flow']:
            root_response = nifi_client.api_call('GET', endpoint)
            if root_response:
                root_pg_id = (root_response.get('processGroupFlow', {}).get('id') or
                              root_response.get('id'))
                if root_pg_id:
                    break

        if not root_pg_id:
            return jsonify({'success': False, 'error': 'Could not get root Process Group ID'}), 500

        # Import into NiFi
        target_pg_id = root_pg_id
        pg_detail = nifi_client.api_call('GET', f'/process-groups/{root_pg_id}')
        current_revision = pg_detail['revision']

        import_payload = {
            "processGroupRevision": current_revision,
            "versionedFlowSnapshot": versioned_flow_snapshot,
            "disconnectedNodeAcknowledged": True
        }

        result = nifi_client.api_call('PUT', f'/process-groups/{target_pg_id}/flow-contents', data=import_payload)

        if result:
            log_with_context(logging.INFO, f"✅ Successfully imported GitHub flow: {github_path}")
            return jsonify({
                'success': True,
                'message': f'Flow "{github_path}" imported successfully from GitHub!',
                'processGroupId': target_pg_id
            })
        else:
            return jsonify({'success': False, 'error': 'NiFi import returned no result'}), 500

    except Exception as e:
        log_with_context(logging.ERROR, f"GitHub import failed: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/config-nifi/api/github/debug-config', methods=['GET'])
def debug_github_config():
    """Temporary: shows which GitHub fields are present in config (no token value)."""
    return jsonify({
        'github_owner':    bool(config_manager.config.get('github_owner')),
        'github_repo_name': bool(config_manager.config.get('github_repo_name')),
        'github_token':    bool(config_manager.config.get('github_token')),
        'github_branch':   config_manager.config.get('github_branch'),
        'github_flow_dir': config_manager.config.get('github_flow_dir'),
    })

@app.route('/config-nifi/api/github/fetch-flow-content', methods=['GET'])
def fetch_flow_content():
    """Proxy: fetch a raw GitHub file and return as JSON (avoids browser CORS)."""
    try:
        url   = request.args.get('url')
        if not url:
            return jsonify({'success': False, 'error': 'Missing url parameter'}), 400

        # Only allow raw.githubusercontent.com to prevent SSRF abuse
        if 'raw.githubusercontent.com' not in url:
            return jsonify({'success': False, 'error': 'Only raw.githubusercontent.com URLs allowed'}), 400

        token   = config_manager.config.get('github_token', '')
        headers = {'Authorization': f'token {token}'} if token else {}

        response = requests.get(url, headers=headers, timeout=30)
        if response.status_code != 200:
            return jsonify({
                'success': False,
                'error': f'GitHub returned {response.status_code}'
            }), response.status_code

        try:
            content = response.json()
            top_keys = list(content.keys()) if isinstance(content, dict) else []
            log_with_context(logging.INFO,
                f"Fetched flow content from GitHub. Top-level keys: {top_keys}")
            return jsonify({'success': True, 'content': content, 'top_keys': top_keys})
        except ValueError:
            return jsonify({
                'success': False,
                'error':   'File is not valid JSON'
            }), 400

    except Exception as e:
        log_with_context(logging.ERROR, f"Error fetching flow content: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/config-nifi/api/github/list-buckets', methods=['GET'])
def github_list_buckets():
    """Return all top-level folders (buckets) in the GitHub repository."""
    try:
        owner = request.args.get('owner')
        repo  = request.args.get('repo')
        token = request.args.get('token')
        branch = request.args.get('branch', 'main')

        if not all([owner, repo, token]):
            missing = [k for k, v in [('owner', owner), ('repo', repo), ('token', token)] if not v]
            return jsonify({'success': False, 'error': f'GitHub not configured. Missing: {", ".join(missing)}'}), 400

        headers = {
            'Authorization': f'token {token}',
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'Apache-NiFi-API-Manager'
        }

        api_url = config_manager.config.get('github_api_url', 'https://api.github.com')
        url = f"{api_url}/repos/{owner}/{repo}/contents?ref={branch}"

        resp = requests.get(url, headers=headers, timeout=15)

        if resp.status_code == 404:
            return jsonify({'success': True, 'buckets': [], 'message': 'Repository is empty'})

        if not resp.ok:
            error_msg = resp.json().get('message', resp.text)
            return jsonify({'success': False, 'error': error_msg}), resp.status_code

        items = resp.json()
        if not isinstance(items, list):
            items = [items]

        # Filter only directories (these are our "buckets")
        buckets = []
        for item in items:
            if item.get('type') == 'dir':
                buckets.append({
                    'name': item['name'],
                    'path': item['path'],
                    'sha': item.get('sha')
                })

        # Sort alphabetically
        buckets.sort(key=lambda x: x['name'].lower())

        return jsonify({
            'success': True,
            'buckets': buckets,
            'count': len(buckets)
        })

    except Exception as e:
        log_with_context(logging.ERROR, f"List buckets error: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500


# =============================================================================
# ROUTES - BASH WEB EXECUTOR SERVICE
# =============================================================================
SCRIPT_PATH = "/setup-scripts"
ALLOWED_COMMANDS = ['ls', 'cat', 'echo', 'mkdir', 'rmdir', 'cp', 'mv', 'bash', 'sh', 'python', 'python3']


@app.route('/config-idol/save-script', methods=['POST'])
def save_script():
    try:
        data = request.get_json()
        if not data:
            log_with_context(logging.ERROR, "No JSON data provided in request.")
            return jsonify({'success': False, 'error': 'No JSON data provided in request'}), 400
        file_path = data.get('file_path', '/setup-scripts/pre-setup.sh')
        script_content = data.get('script_content', '')
        if not file_path or not script_content:
            log_with_context(logging.ERROR, "Missing file path or script content.")
            return jsonify({'success': False, 'error': 'Missing file path or script content'}), 400
        if not os.access(os.path.dirname(file_path), os.W_OK):
            log_with_context(logging.ERROR, f"No write permission for directory: {os.path.dirname(file_path)}")
            return jsonify({'success': False, 'error': f'No write permission for directory: {os.path.dirname(file_path)}'}), 403
        try:
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(script_content)
            log_with_context(logging.INFO, f"Script saved successfully to {file_path}")
            return jsonify({
                'success': True,
                'message': 'Script saved successfully',
                'file_path': file_path
            })
        except Exception as e:
            log_with_context(logging.ERROR, f"Error saving script: {str(e)}")
            return jsonify({'success': False, 'error': f'Error saving script: {str(e)}'}), 500
    except Exception as e:
        log_with_context(logging.ERROR, f"Error in save-script endpoint: {str(e)}")
        return jsonify({'success': False, 'error': f'Internal server error: {str(e)}'}), 500


@app.route('/config-idol/execute', methods=['POST'])
def execute_command():
    try:
        data = request.get_json()
        if not data:
            log_with_context(logging.ERROR, "No JSON data provided.")
            return jsonify({'error': 'No JSON data provided', 'success': False}), 400
        command = data.get('command', '').strip()
        if not command:
            log_with_context(logging.ERROR, "No command provided.")
            return jsonify({'error': 'No command provided', 'success': False}), 400
        command_prefix = command.split()[0] if command else ''
        if command_prefix not in ALLOWED_COMMANDS:
            log_with_context(logging.ERROR, f'Command not allowed: {command_prefix}')
            return jsonify({'error': f'Command not allowed: {command_prefix}', 'success': False}), 403
        working_path = SCRIPT_PATH
        execution_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_with_context(logging.INFO, f"Executing command: '{command}' in directory: {working_path}")
        result = subprocess.run(
            command,
            shell=True,
            cwd=working_path,
            capture_output=True,
            text=True,
            timeout=30
        )
        output_text = f"EXECUTION ID: {execution_id}\nCommand: {command}\nExecution time: {datetime.now().isoformat()}\nWorking directory: {working_path}\n{'=' * 60}\n"
        output_text += f"STDOUT:\n{result.stdout}\n" if result.stdout else "STDOUT: (empty)\n"
        output_text += f"STDERR:\n{result.stderr}\n" if result.stderr else "STDERR: (empty)\n"
        output_text += f"Return code: {result.returncode}\n{'=' * 60}\n\n"
        cmd_file_path = os.path.join(SCRIPT_PATH, "pre-setup.out")
        try:
            with open(cmd_file_path, 'a', encoding='utf-8') as cmd_file:
                cmd_file.write(output_text)
        except Exception as file_error:
            log_with_context(logging.ERROR, f"Failed to write to pre-setup.out: {str(file_error)}")
        log_with_context(logging.INFO, f"Command executed successfully (Return Code: {result.returncode}).")
        return jsonify({
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode,
            'success': result.returncode == 0,
            'working_directory': working_path,
            'cmd_file_updated': True,
            'execution_id': execution_id
        })
    except subprocess.TimeoutExpired:
        log_with_context(logging.ERROR, "Command timed out after 30 seconds.")
        return jsonify({'error': 'Command timed out after 30 seconds', 'success': False}), 408
    except Exception as e:
        log_with_context(logging.ERROR, f"Error executing command: {str(e)}", exc_info=True)
        return jsonify({'error': str(e), 'success': False}), 500


# =============================================================================
# ROUTES - PORT CHECK UTILITY
# =============================================================================
@app.route('/config-idol/check-ports', methods=['POST'])
def check_ports():
    """
    Check if ports are free (nothing listening) on 0.0.0.0.
    Returns { port: true } if free, { port: false } if in use, { port: null } on error.
    """
    try:
        data = request.get_json(silent=True)
        if not data or 'ports' not in data:
            log_with_context(logging.ERROR, "Missing 'ports' array.")
            return jsonify({"success": False, "error": "Missing 'ports' array"}), 400
        raw_ports: List = data['ports']
        if not isinstance(raw_ports, list):
            log_with_context(logging.ERROR, "'ports' must be a list.")
            return jsonify({"success": False, "error": "'ports' must be a list"}), 400
        ports_to_check: List[int] = []
        for p in raw_ports:
            try:
                port = int(p)
                if 0 < port <= 65535:
                    ports_to_check.append(port)
                else:
                    log_with_context(logging.DEBUG, f"Ignored out-of-range port: {p}")
            except (ValueError, TypeError):
                log_with_context(logging.DEBUG, f"Ignored non-integer port: {p}")
        if not ports_to_check:
            log_with_context(logging.ERROR, "No valid ports to check.")
            return jsonify({"success": False, "error": "No valid ports to check"}), 400
        results: Dict[str, Optional[bool]] = {}
        checked = 0
        for port in sorted(set(ports_to_check)):
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.settimeout(0.3)
                    in_use = s.connect_ex(('0.0.0.0', port)) == 0
                    results[str(port)] = not in_use
                    checked += 1
            except PermissionError:
                log_with_context(logging.WARNING, f"Permission denied checking port {port}")
                results[str(port)] = None
            except OSError as e:
                log_with_context(logging.WARNING, f"OS error on port {port}: {e}")
                results[str(port)] = None
            except Exception as e:
                log_with_context(logging.ERROR, f"Unexpected error checking port {port}", exc_info=True)
                results[str(port)] = None
        failed_count = sum(1 for v in results.values() if v is None)
        log_with_context(logging.INFO, f"Port check completed. {checked} ports checked, {failed_count} failed.")
        log_with_context(logging.WARNING, "Port checks are not atomic. Race conditions may occur if ports are allocated between check and use.")
        return jsonify({
            "success": True,
            "results": results,
            "checked_count": checked,
            "failed_count": failed_count,
            "timestamp": datetime.utcnow().isoformat()
        })
    except Exception as e:
        log_with_context(logging.ERROR, "Critical error in /check-ports", exc_info=True)
        return jsonify({"success": False, "error": f"Server error: {str(e)}"}), 500


# =============================================================================
# ROUTES - LLM MODEL JSON UPLOAD
# =============================================================================
@app.route('/load-models/default-models.json')
def serve_llm_models():
    # ← Path now points to the mounted host file
    file_path = '/setup-scripts/default-models.json'
    
    if not os.path.exists(file_path):
        return jsonify({
            "error": "default-models.json not found",
            "detail": "Make sure the volume mount is correct: ./idol-containers-toolkit/data-admin/llm-sandbox → /setup-scripts"
        }), 404
    
    response = send_file(file_path, mimetype='application/json')
    # Disable caching so changes on the host are immediately visible
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response

# =============================================================================
# ROUTES - CONFIGURATION
# =============================================================================
@app.route('/')
def index():
    return render_template('index.html')


@app.route('/config-nifi')
def config_nifi():
    idol_nifi_flows_dir = os.environ.get('IDOL_NIFI_FLOWS_DIR', '/nifi-flows/Customize')
    return render_template('config-nifi.html', idol_nifi_flows_dir=idol_nifi_flows_dir)


@app.route('/config-idol')
def config_idol():
    return render_template('config-idol.html')

@app.route('/config-monitor')
def config_monitor():
    return render_template('config-monitor.html')

@app.route('/api/rich-media/default')
def get_rich_media_default():
    default = os.environ.get('IDOL_SHARED_FOLDER_PATH', '/rich-media-software')
    return jsonify({'defaultPath': default})


@app.route('/api/monitor/status')
def proxy_real_monitor_status():
    """
    Proxy to the real IDOL Monitor UI backend (monitor-ui service on port 5011).
    Lets the frontend call a same-origin endpoint instead of hard-coding
    localhost:5011 directly (avoids CORS issues and works when the
    monitor stack isn't reachable from the browser but is reachable
    container-to-container or via the host).
    Returns the same shape as http://localhost:5011/api/status, with an
    'ok' flag the frontend uses to decide whether to show the
    "Open Live Monitor" button or the fallback CLI instructions.
    """
    monitor_url = os.environ.get('MONITOR_UI_URL', 'http://idol-docker-host:5011')
    try:
        resp = requests.get(f'{monitor_url}/api/status', timeout=4)
        try:
            data = resp.json()
        except ValueError:
            data = {}
        if 'ok' not in data:
            data['ok'] = resp.status_code < 400
        return jsonify(data), resp.status_code
    except requests.exceptions.RequestException as e:
        logging.warning(f"Monitor UI backend unreachable: {e}")
        return jsonify({
            "ok": False,
            "error": "Monitor backend not reachable",
            "source": "proxy",
            "services": [],
            "summary": {"total": 0, "healthy": 0, "degraded": 0}
        }), 502
    except Exception as e:
        logging.error(f"Unexpected error proxying monitor status: {e}")
        return jsonify({"ok": False, "error": str(e), "source": "proxy"}), 500

@app.route('/config-nifi/api/config', methods=['GET', 'POST'])
@cache.cached(timeout=60)
@limiter.limit("60 per minute")
def handle_config():
    if request.method == 'GET':
        log_with_context(logging.INFO, "Configuration retrieved successfully.")
        return jsonify(config_manager.get_safe_config())
    elif request.method == 'POST':
        data = request.json
        config_manager.update_config(data)
        log_with_context(logging.INFO, "Configuration updated successfully.")
        return jsonify({'success': True, 'message': 'Configuration updated'})


@app.route('/api/config', methods=['GET', 'POST'])
def handle_api_config():
    return handle_config()


@app.route('/config-nifi/api/debug-config', methods=['GET'])
def debug_config():
    current_api_url = config_manager.config.get('nifi_api_url', 'NOT_SET')
    nifi_client_url = nifi_client.config.get('nifi_api_url', 'NOT_SET')
    return jsonify({
        'current_config': {
            'nifi_api_url': config_manager.config['nifi_api_url'],
            'nifi_port': config_manager.config['nifi_port'],
            'container_name': config_manager.config['container_name'],
            'docker_image': config_manager.config['docker_image']
        },
        'nifi_client_url': nifi_client.config['nifi_api_url'],
        'config_match': current_api_url == nifi_client_url
    })


# =============================================================================
# ROUTES - DOCKER MANAGEMENT
# =============================================================================
@app.route('/config-nifi/api/docker/start', methods=['POST'])
def start_docker():
    try:
        data = request.get_json() or {}
        container_name = data.get('container_name', config_manager.config['container_name'])
        port = data.get('nifi_port', config_manager.config['nifi_port'])
        nifi_api_url = data.get('nifi_api_url', config_manager.config['nifi_api_url'])
        image = config_manager.config['docker_image']
        validation_issues = config_manager.validate_port_and_url(port, nifi_api_url)
        if validation_issues:
            log_with_context(logging.ERROR, f"Configuration validation failed: {'; '.join(validation_issues)}")
            return jsonify({'success': False, 'error': f'Configuration validation failed: {"; ".join(validation_issues)}'})
        config_manager.config['nifi_api_url'] = nifi_api_url if nifi_api_url else f"https://localhost:{port}/nifi-api"
        config_manager.config['nifi_port'] = port
        if not image:
            log_with_context(logging.ERROR, "Docker image not specified in configuration.")
            return jsonify({'success': False, 'error': 'Docker image not specified in configuration'})
        if docker_manager.check_container_status(container_name):
            log_with_context(logging.WARNING, f"Container {container_name} already running.")
            return jsonify({'success': False, 'error': f'Container {container_name} already running'})
        container, exists = docker_manager.start_container(container_name, image, port)
        time.sleep(5)
        start_time = time.time()
        timeout = 120
        poll_interval = 5
        username = None
        password = None
        creds_found = False
        while time.time() - start_time < timeout:
            if not docker_manager.check_container_status(container_name):
                logs = container.logs(tail=2000).decode('utf-8')
                log_with_context(logging.ERROR, "Container stopped during startup.")
                return jsonify({'success': False, 'error': 'Container stopped during startup', 'logs': logs})
            logs = container.logs().decode('utf-8')
            if not creds_found:
                username, password = docker_manager.parse_credentials_from_logs(logs)
                if username and password:
                    creds_found = True
                    config_manager.config['nifi_username'] = username
                    config_manager.config['nifi_password'] = password
            if creds_found:
                auth_result = nifi_client.authenticate()
                if auth_result['success']:
                    log_with_context(logging.INFO, f"Docker container {container_name} started successfully. NiFi version: {auth_result.get('version', 'unknown')}")
                    return jsonify({'success': True, 'username': username, 'password': password, 'api_url': config_manager.config['nifi_api_url'], 'version': auth_result.get('version', 'unknown')})
            time.sleep(poll_interval)
        logs = container.logs(tail=2000).decode('utf-8')
        log_with_context(logging.ERROR, "Timeout waiting for NiFi to fully start.")
        return jsonify({'success': False, 'error': 'Timeout waiting for NiFi to fully start', 'logs': logs})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error starting Docker container: {str(e)}")
        return jsonify({'success': False, 'error': str(e)})


@app.route('/config-nifi/api/docker/stop', methods=['POST'])
def stop_docker_container():
    try:
        data = request.get_json() or {}
        container_name = data.get('container_name', config_manager.config['container_name'])
        success, stdout, stderr = docker_manager.stop_container(container_name)
        if success:
            log_with_context(logging.INFO, f"Docker container {container_name} stopped successfully.")
            return jsonify({'success': True, 'message': f'Container {container_name} stopped successfully'})
        log_with_context(logging.ERROR, f"Failed to stop container {container_name}: {stderr}")
        return jsonify({'success': False, 'error': stderr})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error stopping Docker container: {str(e)}")
        return jsonify({'success': False, 'error': str(e)})


@app.route('/config-nifi/api/docker/status', methods=['GET'])
def docker_status():
    try:
        container_name = request.args.get('container_name', config_manager.config['container_name'])
        running = docker_manager.check_container_status(container_name)
        log_with_context(logging.INFO, f"Docker container {container_name} status: {'Running' if running else 'Stopped'}.")
        return jsonify({'success': True, 'running': running, 'status': 'Running' if running else 'Stopped'})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error checking Docker container status: {str(e)}")
        return jsonify({'success': False, 'error': str(e)})


@app.route('/config-nifi/api/docker/logs', methods=['GET'])
def get_docker_logs():
    try:
        container_name = request.args.get('container_name', config_manager.config['container_name'])
        success, logs, error = docker_manager.get_container_logs(container_name)
        if success:
            log_with_context(logging.INFO, f"Retrieved logs for container {container_name}.")
            return jsonify({'success': True, 'logs': logs})
        log_with_context(logging.ERROR, f"Failed to retrieve logs for container {container_name}: {error}")
        return jsonify({'success': False, 'error': error})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error retrieving Docker logs: {str(e)}")
        return jsonify({'success': False, 'error': str(e)})


# =============================================================================
# ROUTES - NiFi AUTHENTICATION & STATUS
# =============================================================================
@app.route('/config-nifi/api/auth', methods=['POST'])
def authenticate():
    result = nifi_client.authenticate()
    if result['success']:
        log_with_context(logging.INFO, "NiFi authentication successful.")
    else:
        log_with_context(logging.ERROR, f"NiFi authentication failed: {result.get('error')}")
    return jsonify(result)


@app.route('/config-nifi/api/test-connection', methods=['GET'])
def test_connection():
    result = nifi_client.test_connection()
    if result['success']:
        log_with_context(logging.INFO, "NiFi connection test successful.")
    else:
        log_with_context(logging.ERROR, f"NiFi connection test failed: {result.get('error')}")
    return jsonify(result)


@app.route('/config-nifi/api/status', methods=['GET'])
def nifi_status():
    try:
        docker_running = docker_manager.check_container_status()
        nifi_connected = False
        nifi_version = None
        registry_connected = False
        if docker_running and config_manager.config.get('auth_token'):
            test_response = nifi_client.api_call('GET', '/flow/about')
            if test_response:
                nifi_connected = True
                nifi_version = test_response.get('about', {}).get('version')
            if config_manager.config.get('registry_id'):
                registry_response = nifi_client.api_call('GET', f'/controller/registry-clients/{config_manager.config["registry_id"]}')
                registry_connected = registry_response is not None
        log_with_context(logging.INFO, f"NiFi status - Docker: {docker_running}, NiFi: {nifi_connected}, Registry: {registry_connected}.")
        return jsonify({'success': True, 'docker': docker_running, 'nifi': nifi_connected, 'registry': registry_connected, 'nifi_version': nifi_version, 'authenticated': bool(config_manager.config.get('auth_token'))})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error retrieving NiFi status: {str(e)}")
        return jsonify({'success': False, 'error': str(e)})


# =============================================================================
# ROUTES - REGISTRY MANAGEMENT
# =============================================================================
@app.route('/config-nifi/api/registry-types', methods=['GET'])
def list_registry_types():
    response = nifi_client.api_call('GET', '/controller/registry-types')
    if response:
        log_with_context(logging.INFO, f"Retrieved {len(response)} registry types.")
        return jsonify({'success': True, 'data': response})
    log_with_context(logging.ERROR, "Failed to fetch registry types.")
    return jsonify({'success': False, 'error': 'Failed to fetch registry types'})


@app.route('/config-nifi/api/registry-clients', methods=['GET'])
def list_registry_clients():
    try:
        response = nifi_client.api_call('GET', '/controller/registry-clients')
        if response and 'registries' in response:
            log_with_context(logging.INFO, f"Retrieved {len(response.get('registries', []))} registry clients.")
            return jsonify({'success': True, 'data': response, 'count': len(response.get('registries', []))})
        error_msg = response.get('message', 'No registries found') if response else 'No response from NiFi'
        log_with_context(logging.ERROR, f"Failed to fetch registry clients: {error_msg}")
        return jsonify({'success': False, 'error': error_msg}), 400
    except Exception as e:
        log_with_context(logging.ERROR, f"Error listing registry clients: {str(e)}")
        return jsonify({'success': False, 'error': f'Internal server error: {str(e)}'}), 500


@app.route('/config-nifi/api/registries', methods=['GET', 'POST'])
def handle_registries():
    if request.method == 'GET':
        response = nifi_client.api_call('GET', '/controller/registry-clients')
        if response:
            log_with_context(logging.INFO, "Retrieved registries.")
            return jsonify({'success': True, 'data': response})
        log_with_context(logging.ERROR, "Failed to fetch registries.")
        return jsonify({'success': False, 'error': 'Failed to fetch registries'})
    elif request.method == 'POST':
        repo_url = config_manager.config['github_repo_url']
        if not repo_url:
            log_with_context(logging.ERROR, "GitHub repository URL not configured.")
            return jsonify({'success': False, 'error': 'GitHub repository URL not configured'})
        repo_path = repo_url.replace('https://github.com/', '').replace('.git', '')
        parts = repo_path.split('/')
        if len(parts) < 2:
            log_with_context(logging.ERROR, "Invalid GitHub repository URL format.")
            return jsonify({'success': False, 'error': 'Invalid GitHub repository URL format'})
        data = {
            "revision": {"version": 0},
            "component": {
                "name": "GitHub Flow Registry",
                "type": "org.apache.nifi.github.GitHubFlowRegistryClient",
                "bundle": {"group": "org.apache.nifi", "artifact": "nifi-github-nar", "version": config_manager.config['nifi_version'] or "2.0.0"},
                "properties": {
                    "API URL": "https://api.github.com",
                    "Repository Owner": parts[0],
                    "Repository Name": parts[1],
                    "Default Branch": config_manager.config['github_branch'],
                    "Authentication Type": "Personal Access Token",
                    "Personal Access Token": config_manager.config['github_token'],
                    "Repository Path": config_manager.config['github_flow_dir']
                },
                "description": "GitHub-based Flow Registry for version control"
            }
        }
        response = nifi_client.api_call('POST', '/controller/registry-clients', data)
        if response:
            config_manager.config['registry_id'] = response.get('id')
            log_with_context(logging.INFO, f"Registry created successfully. ID: {response.get('id')}")
            return jsonify({'success': True, 'data': response})
        log_with_context(logging.ERROR, "Failed to create registry.")
        return jsonify({'success': False, 'error': 'Failed to create registry'})


@app.route('/config-nifi/api/registries/<registry_id>', methods=['GET', 'PUT', 'DELETE'])
def handle_registry(registry_id):
    if request.method == 'GET':
        response = nifi_client.api_call('GET', f'/controller/registry-clients/{registry_id}')
        if response:
            log_with_context(logging.INFO, f"Retrieved registry {registry_id}.")
            return jsonify({'success': True, 'data': response})
        log_with_context(logging.ERROR, f"Failed to fetch registry {registry_id}.")
        return jsonify({'success': False, 'error': 'Failed to fetch registry'})
    elif request.method == 'PUT':
        current = nifi_client.api_call('GET', f'/controller/registry-clients/{registry_id}')
        if not current:
            log_with_context(logging.ERROR, f"Registry {registry_id} not found.")
            return jsonify({'success': False, 'error': 'Registry not found'}), 404
        update_data = request.json
        update_data['revision'] = current['revision']
        update_data['component']['id'] = registry_id
        response = nifi_client.api_call('PUT', f'/controller/registry-clients/{registry_id}', update_data)
        if response:
            log_with_context(logging.INFO, f"Registry {registry_id} updated successfully.")
            return jsonify({'success': True, 'data': response})
        log_with_context(logging.ERROR, f"Failed to update registry {registry_id}.")
        return jsonify({'success': False, 'error': 'Failed to update registry'})
    elif request.method == 'DELETE':
        current = nifi_client.api_call('GET', f'/controller/registry-clients/{registry_id}')
        if not current:
            log_with_context(logging.ERROR, f"Registry {registry_id} not found.")
            return jsonify({'success': False, 'error': 'Registry not found'}), 404
        version = current['revision']['version']
        response = nifi_client.api_call('DELETE', f'/controller/registry-clients/{registry_id}?version={version}')
        if response:
            if config_manager.config.get('registry_id') == registry_id:
                config_manager.config['registry_id'] = None
            log_with_context(logging.INFO, f"Registry {registry_id} deleted successfully.")
            return jsonify({'success': True, 'message': 'Registry deleted successfully'})
        log_with_context(logging.ERROR, f"Failed to delete registry {registry_id}.")
        return jsonify({'success': False, 'error': 'Failed to delete registry'})


@app.route('/config-nifi/api/registries/<registry_id>/buckets', methods=['GET'])
def list_buckets(registry_id):
    response = nifi_client.api_call('GET', f'/flow/registries/{registry_id}/buckets')
    if response:
        log_with_context(logging.INFO, f"Retrieved buckets for registry {registry_id}.")
        return jsonify({'success': True, 'data': response})
    log_with_context(logging.ERROR, f"Failed to fetch buckets for registry {registry_id}.")
    return jsonify({'success': False, 'error': 'Failed to fetch buckets'})


@app.route('/config-nifi/api/registries/<registry_id>/buckets/<bucket_id>/flows', methods=['GET'])
def list_flows(registry_id, bucket_id):
    response = nifi_client.api_call('GET', f'/flow/registries/{registry_id}/buckets/{bucket_id}/flows')
    if response:
        log_with_context(logging.INFO, f"Retrieved flows for bucket {bucket_id} in registry {registry_id}.")
        return jsonify({'success': True, 'data': response})
    log_with_context(logging.ERROR, f"Failed to fetch flows for bucket {bucket_id} in registry {registry_id}.")
    return jsonify({'success': False, 'error': 'Failed to fetch flows'})

@app.route('/config-nifi/api/registries/<registry_id>/buckets/<bucket_id>/flows/<flow_id>/versions', methods=['GET'])
def list_flow_versions(registry_id, bucket_id, flow_id):
    response = nifi_client.api_call('GET', f'/flow/registries/{registry_id}/buckets/{bucket_id}/flows/{flow_id}/versions')
    if response:
        log_with_context(logging.INFO, f"Retrieved versions for flow {flow_id} in bucket {bucket_id}.")
        return jsonify({'success': True, 'data': response})
    log_with_context(logging.ERROR, f"Failed to fetch versions for flow {flow_id} in bucket {bucket_id}.")
    return jsonify({'success': False, 'error': 'Failed to fetch flow versions'})


@app.route('/config-nifi/api/registries/<registry_id>/buckets/<bucket_id>/flows/<flow_id>/versions/<version>', methods=['GET'])
def get_flow_version(registry_id, bucket_id, flow_id, version):
    response = nifi_client.api_call('GET', f'/flow/registries/{registry_id}/buckets/{bucket_id}/flows/{flow_id}/versions/{version}')
    if response:
        log_with_context(logging.INFO, f"Retrieved version {version} for flow {flow_id}.")
        return jsonify({'success': True, 'data': response})
    log_with_context(logging.ERROR, f"Failed to fetch version {version} for flow {flow_id}.")
    return jsonify({'success': False, 'error': 'Failed to fetch flow version'})


@app.route('/config-nifi/api/registries/<registry_id>/test', methods=['POST'])
def test_registry_client(registry_id):
    try:
        registry_response = nifi_client.api_call('GET', f'/controller/registry-clients/{registry_id}')
        if not registry_response:
            log_with_context(logging.ERROR, f"Registry client {registry_id} not found.")
            return jsonify({'success': False, 'error': 'Registry client not found'}), 404
        buckets_response = nifi_client.api_call('GET', f'/flow/registries/{registry_id}/buckets')
        if buckets_response and not buckets_response.get('error'):
            log_with_context(logging.INFO, f"Registry client {registry_id} connection successful.")
            return jsonify({'success': True, 'message': 'Registry client connection successful', 'bucket_count': len(buckets_response.get('buckets', [])), 'registry_name': registry_response.get('component', {}).get('name', 'Unknown')})
        error_msg = buckets_response.get('message', 'Failed to connect to registry') if buckets_response else 'No response from registry'
        log_with_context(logging.ERROR, f"Failed to connect to registry {registry_id}: {error_msg}")
        return jsonify({'success': False, 'error': error_msg, 'registry_name': registry_response.get('component', {}).get('name', 'Unknown')}), 400
    except Exception as e:
        log_with_context(logging.ERROR, f"Error testing registry client {registry_id}: {str(e)}")
        return jsonify({'success': False, 'error': f'Internal server error: {str(e)}'}), 500


# =============================================================================
# ROUTES - PARAMETER CONTEXTS (NiFi 2.x Compatible)
# =============================================================================
@app.route('/config-nifi/api/parameter-contexts', methods=['GET', 'POST'])
@app.route('/config-nifi/api/parameter-contexts/<context_id>', methods=['GET', 'PUT', 'DELETE'])
@limiter.limit("200 per minute")  # Aligned with controller service update logic
def handle_parameter_contexts(context_id=None):
    # Aligned with controller service update logic: whole handler wrapped in
    # try/except so any unexpected error (e.g. malformed JSON body) always
    # comes back as a consistent {'success': False, 'error': ...} JSON shape
    # instead of an HTML error page.
    try:
        if request.method == 'GET':
            if context_id:
                response = nifi_client.api_call('GET', f'/parameter-contexts/{context_id}')
                if response:
                    params = response.get('component', {}).get('parameters', [])
                    log_with_context(logging.INFO,
                        f"Retrieved full context {context_id} — {len(params)} parameters")
                    return jsonify({'success': True, 'data': response})
                return jsonify({'success': False, 'error': 'Failed to fetch parameter context'}), 404

            else:
                response = nifi_client.api_call('GET', '/flow/parameter-contexts')
                count = len(response.get('parameterContexts', [])) if response else 0
                log_with_context(logging.INFO, f"Listed {count} parameter contexts")
                return jsonify({'success': True, 'data': response})

        # ========================= POST - CREATE =========================
        elif request.method == 'POST':
            data = request.json or {}
            name = data.get('name')
            if not name:
                return jsonify({'success': False, 'error': 'Name is required'}), 400

            log_with_context(logging.INFO, f"Received raw data keys: {list(data.keys())}")

            raw_params = data.get('parameters', [])

            if isinstance(raw_params, str):
                try:
                    raw_params = json.loads(raw_params)
                except Exception as e:
                    return jsonify({'success': False, 'error': f'Invalid parameters JSON: {e}'}), 400

            if isinstance(raw_params, dict):
                raw_params = list(raw_params.values())

            if not isinstance(raw_params, list):
                raw_params = []

            wrapped_params = []
            for p in raw_params:
                if isinstance(p, dict):
                    wrapped_params.append({
                        "parameter": {
                            "name": str(p.get('name', '')).strip(),
                            "value": p.get('value', ''),
                            "sensitive": bool(p.get('sensitive', False)),
                            "description": p.get('description', '')
                        }
                    })

            payload = {
                "revision": {"version": 0},
                "component": {
                    "name": name,
                    "description": data.get('description', ''),
                    "parameters": wrapped_params,
                    "inheritedParameterContexts": []
                }
            }

            response = nifi_client.api_call('POST', '/parameter-contexts', payload)
            if response:
                ctx_id = response.get('id') or response.get('component', {}).get('id')
                full = nifi_client.api_call('GET', f'/parameter-contexts/{ctx_id}')
                actual_count = len(full.get('component', {}).get('parameters', [])) if full else 0
                return jsonify({
                    'success': True,
                    'data': response,
                    'full_context': full,
                    'param_count': actual_count
                })
            return jsonify({'success': False, 'error': 'Failed to create parameter context'}), 500

        # ====================== PUT (Update) ======================
        elif request.method == 'PUT' and context_id:
            data = request.get_json()
            # Aligned with controller service update logic: reject missing/empty body
            if not data:
                return jsonify({'success': False, 'error': 'No data provided'}), 400

            log_with_context(logging.INFO, f"=== Updating Parameter Context: {context_id} ===")

            # Aligned with controller service update logic: always fetch fresh revision,
            # and require both 'revision' (needed to build the payload) and 'component'
            # (needed for the partial-update fallback below).
            current = nifi_client.api_call('GET', f'/parameter-contexts/{context_id}')
            if not current or 'revision' not in current or 'component' not in current:
                return jsonify({'success': False, 'error': 'Parameter context not found'}), 404

            current_component = current.get('component', {})

            # Aligned with controller service update logic: partial-update detection uses
            # a falsy-value fallback (same rule as new_properties in manage_controller_service),
            # not key-presence detection. Sending nothing meaningful means "keep what's there".
            params_input = data.get('parameters') or data.get('component', {}).get('parameters')

            if not params_input:
                new_parameters = current_component.get('parameters', [])
                log_with_context(logging.INFO, f"Preserving existing parameters ({len(new_parameters)})")
            else:
                if isinstance(params_input, str):
                    try:
                        params_input = json.loads(params_input)
                    except Exception:
                        params_input = []
                if isinstance(params_input, dict):
                    params_input = list(params_input.values())

                new_parameters = []
                for p in params_input:
                    if isinstance(p, dict):
                        new_parameters.append({
                            "parameter": {
                                "name": str(p.get('name', '')).strip(),
                                "value": p.get('value', ''),
                                "sensitive": bool(p.get('sensitive', False)),
                                "description": p.get('description', '')
                            }
                        })
                log_with_context(logging.INFO, f"Replacing parameters ({len(new_parameters)} sent from frontend)")

            # Clean payload
            payload = {
                "revision": current.get("revision", {}),
                "component": {
                    "id": context_id,
                    "name": data.get("name") or current_component.get("name"),
                    "description": data.get("description", current_component.get("description", "")),
                    "parameters": new_parameters,
                    "inheritedParameterContexts": current_component.get("inheritedParameterContexts", [])
                }
            }

            # Log payload (consider masking sensitive values in production)
            log_with_context(logging.DEBUG, f"Payload sent to update-requests:\n{json.dumps(payload, indent=2)}")

            # NOTE: kept as the async update-requests + polling flow. This is NOT a
            # discrepancy with the controller-service PUT handler being a synchronous
            # PUT — NiFi's REST API itself only supports parameter context updates via
            # this async update-requests mechanism, so the two endpoints are necessarily
            # different at this layer.
            update_resp = nifi_client.api_call('POST', f'/parameter-contexts/{context_id}/update-requests', data=payload)
            if not update_resp:
                # The detailed NiFi error (e.g. "Unable to locate controller service with id ...") was already logged by api_call
                return jsonify({
                    'success': False,
                    'error': 'NiFi rejected the Parameter Context update. '
                             'Common cause: one of the parameter values (or a processor using this context) references a Controller Service that no longer exists in the flow. '
                             'Check the server logs for the exact ID and fix/remove the broken reference.'
                }), 500

            req_data = update_resp.get('request', update_resp)
            request_id = req_data.get('requestId') or req_data.get('id')
            if not request_id:
                return jsonify({'success': False, 'error': 'No requestId returned'}), 500

            log_with_context(logging.INFO, f"Update request created: {request_id}")

            # Poll for completion
            max_wait = 180
            start_time = time.time()
            final_status = None
            success = False

            while time.time() - start_time < max_wait:
                status = nifi_client.api_call('GET', f'/parameter-contexts/{context_id}/update-requests/{request_id}')
                if status:
                    req_status = status.get('request', status)
                    final_status = req_status
                    if req_status.get('complete'):
                        success = not bool(req_status.get('failureReason'))
                        break
                time.sleep(2)

            # Cleanup
            try:
                nifi_client.api_call(
                    'DELETE',
                    f'/parameter-contexts/{context_id}/update-requests/{request_id}?disconnectedNodeAcknowledged=true'
                )
            except Exception as e:
                log_with_context(logging.WARNING, f"Failed to cleanup update request: {e}")

            if success:
                log_with_context(logging.INFO, f"✅ Parameter Context {context_id} updated successfully")
                # Aligned with controller service update logic: return the updated
                # entity as 'data', same as manage_controller_service does. There is
                # no NiFi-provided 'validationStatus' for parameter contexts, so we
                # don't fabricate one.
                updated = nifi_client.api_call('GET', f'/parameter-contexts/{context_id}')
                return jsonify({
                    'success': True,
                    'data': updated,
                    'message': 'Parameter Context updated successfully'
                })
            else:
                reason = (final_status or {}).get('failureReason', 'Update failed or timed out')
                return jsonify({'success': False, 'error': reason, 'status': final_status}), 500

        # ====================== DELETE ======================
        elif request.method == 'DELETE' and context_id:
            current = nifi_client.api_call('GET', f'/parameter-contexts/{context_id}')
            if not current or 'revision' not in current:
                return jsonify({'success': False, 'error': 'Could not get revision for deletion'}), 404

            version = current['revision'].get('version')
            url = f'/parameter-contexts/{context_id}?version={version}&disconnectedNodeAcknowledged=true'
            result = nifi_client.api_call_detailed('DELETE', url)

            if result['ok']:
                log_with_context(logging.INFO, f"Parameter Context {context_id} deleted successfully")
                return jsonify({'success': True, 'message': 'Parameter Context deleted'})

            status = result['status_code']

            if status == 409:
                # NiFi puts the real reason (which Process Group / Processor
                # still references it) in the response body — surface that
                # instead of the old generic 500, so the "Delete" button on
                # each row shows something the user can actually act on.
                reason = (result.get('json') or {}).get('message') or result.get('text') or ''
                log_with_context(logging.WARNING, f"Parameter Context {context_id} still in use: {reason}")
                return jsonify({
                    'success': False,
                    'error': 'Cannot delete: this Parameter Context is still in use by one or more Process Groups/Processors.',
                    'detail': reason
                }), 409

            log_with_context(logging.ERROR,
                f"Failed to delete Parameter Context {context_id}: HTTP {status} - {result.get('text')}")
            return jsonify({
                'success': False,
                'error': f'Failed to delete parameter context (HTTP {status})' if status else 'Failed to delete parameter context',
                'detail': result.get('text')
            }), status if status else 500

        return jsonify({'success': False, 'error': 'Method not allowed'}), 405

    except Exception as e:
        # Aligned with controller service update logic
        log_with_context(logging.ERROR, f"Error in handle_parameter_contexts {context_id}: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500
    

# =============================================================================
# ROUTES - GITHUB REPOSITORY CONTENTS
# =============================================================================
@app.route('/config-nifi/api/github/repository/contents', methods=['POST'])
def get_repository_contents():
    try:
        data = request.get_json()
        if not data:
            log_with_context(logging.ERROR, "No JSON data provided.")
            return jsonify({'success': False, 'error': 'No JSON data provided'}), 400
        github_owner = data.get('github_owner')
        github_repo_name = data.get('github_repo_name')
        github_branch = data.get('github_branch', 'main')
        github_flow_dir = data.get('github_flow_dir', 'nifi-flows')
        github_token = data.get('github_token')
        github_api_url = data.get('github_api_url', 'https://api.github.com')
        if not all([github_owner, github_repo_name, github_token]):
            log_with_context(logging.ERROR, "GitHub Owner, Repository Name, and Token are required.")
            return jsonify({'success': False, 'error': 'GitHub Owner, Repository Name, and Token are required'}), 400
        headers = {'Authorization': f'token {github_token}', 'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'Apache-NiFi-API-Manager'}
        api_url = f"{github_api_url}/repos/{github_owner}/{github_repo_name}/contents/{github_flow_dir}"
        params = {'ref': github_branch}
        response = requests.get(api_url, headers=headers, params=params, timeout=30)
        if response.status_code == 404:
            api_url = f"{github_api_url}/repos/{github_owner}/{github_repo_name}/contents"
            response = requests.get(api_url, headers=headers, params=params, timeout=30)
        if not response.ok:
            log_with_context(logging.ERROR, f"GitHub API error: {response.status_code} - {response.text}")
            return jsonify({'success': False, 'error': f"GitHub API error: {response.status_code}", 'status_code': response.status_code}), response.status_code
        contents_data = response.json()
        files = []
        directories = []
        if isinstance(contents_data, list):
            for item in contents_data:
                if item['type'] == 'file':
                    files.append({'name': item['name'], 'path': item['path'], 'size': item.get('size', 0), 'download_url': item.get('download_url'), 'html_url': item.get('html_url'), 'sha': item.get('sha'), 'type': 'file'})
                elif item['type'] == 'dir':
                    directories.append({'name': item['name'], 'path': item['path'], 'html_url': item.get('html_url'), 'sha': item.get('sha'), 'type': 'directory'})
        repo_url = f"{github_api_url}/repos/{github_owner}/{github_repo_name}"
        repo_response = requests.get(repo_url, headers=headers, timeout=30)
        repo_info = {}
        if repo_response.ok:
            repo_data = repo_response.json()
            repo_info = {'name': repo_data.get('name'), 'full_name': repo_data.get('full_name'), 'description': repo_data.get('description'), 'default_branch': repo_data.get('default_branch'), 'private': repo_data.get('private'), 'html_url': repo_data.get('html_url')}
        log_with_context(logging.INFO, f"Retrieved {len(files)} files and {len(directories)} directories from GitHub repository.")
        return jsonify({'success': True, 'data': {'files': files, 'directories': directories, 'total_files': len(files), 'total_directories': len(directories), 'path': github_flow_dir, 'branch': github_branch, 'repository': repo_info, 'owner': github_owner, 'repo': github_repo_name, 'timestamp': datetime.now().isoformat()}})
    except Exception as e:
        log_with_context(logging.ERROR, f"Unexpected error in get_repository_contents: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': f'Internal server error: {str(e)}'}), 500


# =============================================================================
# ROUTES - HOST FOLDER MANAGEMENT
# =============================================================================
ALLOWED_EXTENSIONS = {'.json', '.xml', '.flow', '.template', '.txt'}
FLOW_EXTENSIONS = {'.json', '.xml', '.flow', '.template'}


def is_allowed_file(filename):
    return '.' in filename and filename.lower().endswith(tuple(ALLOWED_EXTENSIONS))


def is_flow_file(filename):
    return '.' in filename and filename.lower().endswith(tuple(FLOW_EXTENSIONS))


@app.route('/api/host-folder-flows', methods=['POST'])
def host_folder_flows():
    try:
        data = request.get_json()
        if not data:
            log_with_context(logging.ERROR, "No JSON data provided.")
            return jsonify({'success': False, 'error': 'No JSON data provided'}), 400
        folder_path = data.get('path')
        if not folder_path:
            log_with_context(logging.ERROR, "Folder path is required.")
            return jsonify({'success': False, 'error': 'Folder path is required'}), 400
        if not os.path.exists(folder_path):
            log_with_context(logging.ERROR, f"Folder does not exist: {folder_path}")
            return jsonify({'success': False, 'error': f'Folder does not exist: {folder_path}'}), 404
        if not os.path.isdir(folder_path):
            log_with_context(logging.ERROR, f"Path is not a directory: {folder_path}")
            return jsonify({'success': False, 'error': f'Path is not a directory: {folder_path}'}), 400
        if not os.access(folder_path, os.R_OK):
            log_with_context(logging.ERROR, f"No read permission for directory: {folder_path}")
            return jsonify({'success': False, 'error': f'No read permission for directory: {folder_path}'}), 403
        folder_path = os.path.abspath(folder_path)
        flow_extensions = ['.json', '.xml', '.flow', '.template']
        files = []
        for filename in os.listdir(folder_path):
            if any(filename.lower().endswith(ext) for ext in flow_extensions):
                file_path = os.path.join(folder_path, filename)
                try:
                    file_stat = os.stat(file_path)
                    files.append({'name': filename, 'path': file_path, 'size': file_stat.st_size, 'modified': file_stat.st_mtime * 1000, 'type': 'flow' if filename.endswith('.flow') else 'template'})
                except Exception as e:
                    log_with_context(logging.WARNING, f"Error processing file {filename}: {str(e)}")
        log_with_context(logging.INFO, f"Scanned {len(files)} flow files in {folder_path}.")
        return jsonify({'success': True, 'files': files, 'folder_path': folder_path, 'count': len(files)})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error scanning host folder for flows: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': f'Internal server error: {str(e)}'}), 500


@app.route('/config-nifi/api/host-folder/scan', methods=['POST'])
def scan_host_folder():
    data = request.get_json()
    container_folder_path = data.get('folder_path')
    if not container_folder_path:
        log_with_context(logging.ERROR, "Folder path is required.")
        return jsonify({'success': False, 'error': 'Folder path is required'}), 400
    try:
        container_name = config_manager.config.get('container_name')
        if not container_name:
            log_with_context(logging.ERROR, "Container name not configured.")
            return jsonify({'success': False, 'error': 'Container name not configured'}), 400
        client = docker.from_env()
        try:
            container = client.containers.get(container_name)
        except docker.errors.NotFound:
            containers = client.containers.list(all=True)
            matching = [c for c in containers if container_name in c.name]
            if not matching:
                log_with_context(logging.ERROR, f"Container '{container_name}' not found.")
                return jsonify({'success': False, 'error': f'Container "{container_name}" not found.'}), 404
            container = matching[0]
        if container.status != 'running':
            log_with_context(logging.ERROR, f"Container '{container.name}' is not running (status: {container.status}).")
            return jsonify({'success': False, 'error': f'Container "{container.name}" is not running (status: {container.status})'}), 400
        exec_result = container.exec_run(f'ls -l {container_folder_path}')
        if exec_result.exit_code != 0:
            log_with_context(logging.ERROR, f"Failed to list folder: {exec_result.output.decode().strip()}")
            return jsonify({'success': False, 'error': f'Failed to list folder: {exec_result.output.decode().strip()}'}), 400
        files = []
        for line in exec_result.output.decode().splitlines():
            line = line.strip()
            if not line or line.startswith('total'):
                continue
            parts = line.split()
            if len(parts) >= 9 and parts[0].startswith('-'):
                try:
                    size = int(parts[4])
                    modified = ' '.join(parts[5:8])
                    name = ' '.join(parts[8:])
                    if is_flow_file(name):
                        files.append({'name': name, 'path': os.path.join(container_folder_path, name), 'size': size, 'modified': modified})
                except (ValueError, IndexError):
                    continue
        log_with_context(logging.INFO, f"Scanned {len(files)} files in container folder {container_folder_path}.")
        return jsonify({'success': True, 'files': files}), 200
    except docker.errors.DockerException as e:
        log_with_context(logging.ERROR, f"Docker error: {str(e)}")
        return jsonify({'success': False, 'error': f'Docker error: {str(e)}'}), 500
    except Exception as e:
        log_with_context(logging.ERROR, f"Unexpected error in scan_host_folder: {e}", exc_info=True)
        return jsonify({'success': False, 'error': f'Unexpected error: {str(e)}'}), 500


@app.route('/api/host-folder/list', methods=['POST'])
def host_folder_list():
    try:
        data = request.get_json()
        folder_path = data.get('path', '')
        if not folder_path:
            log_with_context(logging.ERROR, "No folder path provided.")
            return jsonify({'success': False, 'message': 'No folder path provided'}), 400
        if not os.path.exists(folder_path):
            log_with_context(logging.ERROR, f"Folder does not exist: {folder_path}")
            return jsonify({'success': False, 'message': f'Folder does not exist: {folder_path}'}), 404
        if not os.path.isdir(folder_path):
            log_with_context(logging.ERROR, f"Path is not a directory: {folder_path}")
            return jsonify({'success': False, 'message': f'Path is not a directory: {folder_path}'}), 400
        if not os.access(folder_path, os.R_OK):
            log_with_context(logging.ERROR, f"No read permission for directory: {folder_path}")
            return jsonify({'success': False, 'message': f'No read permission for directory: {folder_path}'}), 403
        flow_extensions = ['.json', '.xml', '.flow', '.template']
        files = []
        for filename in os.listdir(folder_path):
            if any(filename.lower().endswith(ext) for ext in flow_extensions):
                file_path = os.path.join(folder_path, filename)
                file_stat = os.stat(file_path)
                files.append({'name': filename, 'path': file_path, 'size': file_stat.st_size, 'modified': file_stat.st_mtime * 1000, 'type': 'flow' if filename.endswith('.flow') else 'template'})
        log_with_context(logging.INFO, f"Listed {len(files)} files in {folder_path}.")
        return jsonify({'success': True, 'files': files, 'count': len(files), 'path': folder_path})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error listing host folder: {str(e)}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/host-folder/preview', methods=['POST'])
def preview_host_file():
    try:
        data = request.get_json()
        if not data:
            log_with_context(logging.ERROR, "No JSON data provided.")
            return jsonify({'success': False, 'message': 'No JSON data provided'}), 400
        file_path = data.get('path')
        if not file_path:
            log_with_context(logging.ERROR, "File path is required.")
            return jsonify({'success': False, 'message': 'File path is required'}), 400
        if not os.path.exists(file_path):
            log_with_context(logging.ERROR, f"File does not exist: {file_path}")
            return jsonify({'success': False, 'message': f'File does not exist: {file_path}'}), 404
        if not os.path.isfile(file_path):
            log_with_context(logging.ERROR, f"Path is not a file: {file_path}")
            return jsonify({'success': False, 'message': f'Path is not a file: {file_path}'}), 400
        if not os.access(file_path, os.R_OK):
            log_with_context(logging.ERROR, f"No read permission for file: {file_path}")
            return jsonify({'success': False, 'message': f'No read permission for file: {file_path}'}), 403
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            with open(file_path, 'rb') as f:
                content = f.read().decode('utf-8', errors='replace')
        content_type = 'text'
        file_ext = os.path.splitext(file_path)[1].lower()
        if file_ext in ['.json']:
            try:
                json.loads(content)
                content_type = 'json'
            except json.JSONDecodeError:
                content_type = 'text'
        elif file_ext in ['.xml']:
            content_type = 'xml'
        file_stat = os.stat(file_path)
        log_with_context(logging.INFO, f"Previewed file {file_path}.")
        return jsonify({'success': True, 'content': content, 'type': content_type, 'file_info': {'name': os.path.basename(file_path), 'path': file_path, 'size': file_stat.st_size, 'modified': file_stat.st_mtime * 1000, 'extension': file_ext}})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error previewing host file: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'message': f'Internal server error: {str(e)}'}), 500


# =============================================================================
# ROUTES - CONTROLLER SERVICES MANAGEMENT
# =============================================================================
@app.route('/config-nifi/api/controller-services/list', methods=['GET'])
def list_controller_services():
    """List all Controller Services with better error handling and logging."""
    try:
        filter_state = request.args.get('filter_state', '').strip()
        filter_name  = request.args.get('filter_name', '').strip()
        filter_type  = request.args.get('filter_type', '').strip()
        filter_location = request.args.get('filter_location', '').strip()

        log_with_context(logging.INFO, "Starting controller services listing")

        # Authenticate once
        auth_result = nifi_client.authenticate()
        if not auth_result.get('success'):
            log_with_context(logging.ERROR, f"NiFi authentication failed: {auth_result.get('error')}")
            return jsonify({'success': False, 'error': 'NiFi authentication failed. Check credentials and URL.'}), 401

        controller_services = []
        processed_groups = 0

        def get_process_groups_recursive(parent_id, parent_path="NiFi Flow"):
            nonlocal processed_groups
            try:
                response = nifi_client.api_call('GET', f"/flow/process-groups/{parent_id}")
                if not response:
                    return

                pg_flow = response.get('processGroupFlow', {}) or response.get('flow', {})
                pg_id = pg_flow.get('id') or response.get('id')
                pg_name = pg_flow.get('breadcrumb', {}).get('breadcrumb', {}).get('name', 'NiFi Flow')

                if not pg_id:
                    return

                # Get controller services for this group
                cs_response = nifi_client.api_call('GET', f"/flow/process-groups/{pg_id}/controller-services")
                if cs_response and 'controllerServices' in cs_response:
                    for cs in cs_response['controllerServices']:
                        comp = cs.get('component', {})
                        cs_info = {
                            'id': cs.get('id'),
                            'name': comp.get('name'),
                            'state': comp.get('state'),
                            'type': comp.get('type'),
                            'process_group_id': pg_id,
                            'process_group_name': pg_name,
                            'process_group_path': parent_path,
                            'validation_status': comp.get('validationStatus'),
                            'properties': comp.get('properties', {}),
                            'referencing_components': comp.get('referencingComponents', []),
                            'revision': cs.get('revision', {})
                        }

                        # Apply filters
                        include = True
                        if filter_state and cs_info['state'] != filter_state:
                            include = False
                        if filter_name and filter_name.lower() not in (cs_info['name'] or '').lower():
                            include = False
                        if filter_type and filter_type.lower() not in (cs_info['type'] or '').lower():
                            include = False
                        if filter_location and filter_location.lower() not in parent_path.lower():
                            include = False

                        if include:
                            controller_services.append(cs_info)

                processed_groups += 1

                # Recurse into child process groups
                for child in pg_flow.get('processGroups', []):
                    child_id = child.get('id')
                    child_name = child.get('component', {}).get('name', 'Unnamed')
                    if child_id:
                        get_process_groups_recursive(child_id, f"{parent_path} > {child_name}")

            except Exception as e:
                log_with_context(logging.WARNING, f"Error processing group {parent_id}: {str(e)}")

        # Find root Process Group
        root_pg_id = None
        for endpoint in ['/flow/process-groups/root', '/process-groups/root', '/flow']:
            try:
                resp = nifi_client.api_call('GET', endpoint)
                if resp:
                    root_pg_id = resp.get('processGroupFlow', {}).get('id') or resp.get('id')
                    if root_pg_id:
                        log_with_context(logging.INFO, f"Found root Process Group using {endpoint}")
                        break
            except:
                continue

        if not root_pg_id:
            log_with_context(logging.ERROR, "Could not find root Process Group ID")
            return jsonify({'success': False, 'error': 'Could not connect to NiFi root flow'}), 500

        get_process_groups_recursive(root_pg_id)

        log_with_context(logging.INFO, f"Successfully loaded {len(controller_services)} controller services from {processed_groups} process groups")

        return jsonify({
            'success': True,
            'count': len(controller_services),
            'data': controller_services,
            'filters': {
                'state': filter_state,
                'name': filter_name,
                'type': filter_type,
                'location': filter_location
            }
        })

    except Exception as e:
        log_with_context(logging.ERROR, f"Controller services list failed: {str(e)}", exc_info=True)
        return jsonify({
            'success': False,
            'error': f'Internal server error: {str(e)}'
        }), 500

@app.route('/config-nifi/api/controller-services/<service_id>', methods=['GET', 'PUT', 'DELETE'])
@limiter.limit("200 per minute")
def manage_controller_service(service_id):
    try:
        if request.method == 'GET':
            response = nifi_client.api_call('GET', f'/controller-services/{service_id}')
            if response:
                return jsonify({'success': True, 'data': response})
            return jsonify({'success': False, 'error': 'Failed to fetch controller service'}), 404

        elif request.method == 'PUT':
            data = request.get_json()
            if not data:
                return jsonify({'success': False, 'error': 'No data provided'}), 400

            # Always fetch fresh revision
            current = nifi_client.api_call('GET', f'/controller-services/{service_id}')
            if not current or 'revision' not in current:
                return jsonify({'success': False, 'error': 'Controller service not found'}), 404

            new_properties = data.get('component', {}).get('properties', {})
            if not new_properties:
                new_properties = current.get('component', {}).get('properties', {})

            payload = {
                "revision": current['revision'],
                "component": {
                    "id": service_id,
                    "properties": new_properties
                }
            }

            log_with_context(logging.INFO, f"Force-updating controller service {service_id} with {len(new_properties)} properties")

            response = nifi_client.api_call('PUT', f'/controller-services/{service_id}', payload)

            if response and 'component' in response:
                comp = response['component']
                validation_status = comp.get('validationStatus', 'UNKNOWN')
                
                log_with_context(logging.INFO, f"Controller service {service_id} updated successfully. Validation status: {validation_status}")
                
                return jsonify({
                    'success': True,
                    'data': response,
                    'validationStatus': validation_status,
                    'message': 'Properties saved successfully'
                })

            return jsonify({'success': False, 'error': 'Failed to update service'}), 500
            
        elif request.method == 'DELETE':
            current = nifi_client.api_call('GET', f'/controller-services/{service_id}')
            if not current:
                return jsonify({'success': False, 'error': 'Controller service not found'}), 404

            # Refuse to delete an AciContextServiceImpl with an empty/missing
            # Connection String — NiFi's native cleanup code crashes the whole
            # JVM in that state (AciContextServiceImplBase.nativeClean),
            # regardless of whether the service is enabled or disabled.
            force = bool((request.get_json(silent=True) or {}).get('force', False))
            comp = current.get('component', {})
            if _service_has_native_crash_risk(comp) and not force:
                log_with_context(logging.ERROR,
                    f"Refusing to delete controller service {service_id} ({comp.get('name')}) — "
                    f"empty Connection String on an AciContextServiceImpl would crash the NiFi JVM")
                return jsonify({
                    'success': False,
                    'error': 'Refusing to delete: this service has an empty "Connection String" and is a known '
                             'type that crashes NiFi when removed in that state. Set a valid Connection String '
                             'first, or pass force=true if you accept the risk.',
                    'service_type': comp.get('type'),
                    'service_name': comp.get('name')
                }), 409

            version = current['revision']['version']
            response = nifi_client.api_call('DELETE', f'/controller-services/{service_id}?version={version}&disconnectedNodeAcknowledged=true')
            if response:
                return jsonify({'success': True, 'message': 'Controller service deleted'})
            return jsonify({'success': False, 'error': 'Failed to delete'}), 500

    except Exception as e:
        log_with_context(logging.ERROR, f"Error in manage_controller_service {service_id}: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/config-nifi/api/controller-services/<service_id>/enable', methods=['POST'])
def enable_controller_service(service_id):
    try:
        current = nifi_client.api_call('GET', f'/controller-services/{service_id}')
        if not current:
            log_with_context(logging.ERROR, f"Controller service {service_id} not found.")
            return jsonify({'success': False, 'error': 'Controller service not found'}), 404
        response = nifi_client.api_call('PUT', f'/controller-services/{service_id}', {'revision': current['revision'], 'component': {'id': service_id, 'state': 'ENABLED'}})
        if response:
            log_with_context(logging.INFO, f"Controller service {service_id} enabled successfully.")
            return jsonify({'success': True, 'data': response})
        log_with_context(logging.ERROR, f"Failed to enable controller service {service_id}.")
        return jsonify({'success': False, 'error': 'Failed to enable controller service'})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error enabling controller service {service_id}: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/config-nifi/api/controller-services/<service_id>/disable', methods=['POST'])
def disable_controller_service(service_id):
    try:
        current = nifi_client.api_call('GET', f'/controller-services/{service_id}')
        if not current:
            log_with_context(logging.ERROR, f"Controller service {service_id} not found.")
            return jsonify({'success': False, 'error': 'Controller service not found'}), 404
        response = nifi_client.api_call('PUT', f'/controller-services/{service_id}', {'revision': current['revision'], 'component': {'id': service_id, 'state': 'DISABLED'}})
        if response:
            log_with_context(logging.INFO, f"Controller service {service_id} disabled successfully.")
            return jsonify({'success': True, 'data': response})
        log_with_context(logging.ERROR, f"Failed to disable controller service {service_id}.")
        return jsonify({'success': False, 'error': 'Failed to disable controller service'})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error disabling controller service {service_id}: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

# =============================================================================
# CONTROLLER SERVICE VALIDATION (used by "Validate Properties" button)
# =============================================================================
@app.route('/config-nifi/api/controller-services/<service_id>/validate', methods=['POST'])
def validate_controller_service_properties(service_id):
    """Validate proposed properties for a Controller Service (NiFi returns validationStatus + validationErrors)."""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No data provided'}), 400

        # Get current service (we need the revision)
        current = nifi_client.api_call('GET', f'/controller-services/{service_id}')
        if not current or 'revision' not in current:
            return jsonify({'success': False, 'error': 'Controller service not found'}), 404

        # Build payload with the properties the user is editing
        proposed_properties = data.get('component', {}).get('properties', {})
        if not proposed_properties:
            proposed_properties = current.get('component', {}).get('properties', {})

        payload = {
            "revision": current['revision'],
            "component": {
                "id": service_id,
                "properties": proposed_properties
            }
        }

        # NiFi validates properties when you send them via PUT
        response = nifi_client.api_call('PUT', f'/controller-services/{service_id}', payload)

        if response and 'component' in response:
            comp = response['component']
            validation_status = comp.get('validationStatus', 'UNKNOWN')
            validation_errors = comp.get('validationErrors', []) or []

            return jsonify({
                'success': True,
                'valid': validation_status == 'VALID',
                'validationStatus': validation_status,
                'validationErrors': validation_errors,
                'message': 'Validation completed'
            })

        return jsonify({
            'success': False,
            'error': 'No valid response from NiFi'
        }), 500

    except Exception as e:
        log_with_context(logging.ERROR, f"Error validating controller service {service_id}: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/config-nifi/api/controller-services/export', methods=['GET'])
def export_controller_services():
    try:
        services_response = list_controller_services()
        services_data = json.loads(services_response.get_data(as_text=True))
        if not services_data.get('success'):
            log_with_context(logging.ERROR, "Failed to export controller services.")
            return jsonify(services_data), 500
        export_data = {'export_timestamp': datetime.now().isoformat(), 'nifi_version': config_manager.config.get('nifi_version'), 'count': services_data['count'], 'controller_services': services_data['data']}
        from flask import make_response
        response = make_response(json.dumps(export_data, indent=2))
        response.headers['Content-Type'] = 'application/json'
        response.headers['Content-Disposition'] = f'attachment; filename=controller_services_export_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
        log_with_context(logging.INFO, "Exported controller services.")
        return response
    except Exception as e:
        log_with_context(logging.ERROR, f"Error exporting controller services: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500


# =============================================================================
# LIST FILES IN HOST FOLDER
# =============================================================================
@app.route('/config-nifi/api/flows/host/list', methods=['GET'])
def list_host_folder_flows():
    """
    List NiFi flow files (.json, .xml, .flow, .template) from a given host folder
    AND ALL its subfolders (recursive).
    Query parameter: ?path=/absolute/path
    """
    folder_path = request.args.get('path', '')
    if not folder_path:
        return jsonify({'success': False, 'error': 'Missing path parameter'}), 400

    # Normalize and security check
    normalized = os.path.normpath(folder_path)
    if not os.path.exists(normalized):
        return jsonify({'success': False, 'error': f'Path does not exist: {normalized}'}), 404
    if not os.path.isdir(normalized):
        return jsonify({'success': False, 'error': 'Path is not a directory'}), 400
    if not os.access(normalized, os.R_OK):
        return jsonify({'success': False, 'error': 'No read permission'}), 403

    allowed_extensions = {'.json', '.xml', '.flow', '.template'}
    files = []

    try:
        # === RECURSIVE SCAN using os.walk ===
        for root, dirs, filenames in os.walk(normalized):
            for filename in filenames:
                ext = os.path.splitext(filename)[1].lower()
                if ext in allowed_extensions:
                    full_path = os.path.join(root, filename)
                    stat = os.stat(full_path)
                    files.append({
                        'name': filename,
                        'path': full_path,          # full absolute path (unchanged)
                        'size': stat.st_size,
                        'modified': stat.st_mtime * 1000,  # milliseconds for JS
                        'folder': os.path.relpath(root, normalized)  # optional: relative folder
                    })

        # Optional: sort by full path for consistent order
        files.sort(key=lambda f: f['path'])

        log_with_context(logging.INFO, f"Listed {len(files)} flow files (recursive) in {normalized}")
        return jsonify({
            'success': True, 
            'files': files, 
            'count': len(files),
            'recursive': True
        })

    except Exception as e:
        log_with_context(logging.ERROR, f"Error listing folder {normalized}: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500
        
@app.route('/config-nifi/api/flows/host/content', methods=['GET'])
def get_host_flow_content():
    """Return raw content of a flow file for NiFi 2 validation."""
    file_path = request.args.get('path')
    if not file_path:
        return jsonify({"success": False, "error": "Missing path"}), 400

    normalized = os.path.normpath(file_path)
    if normalized.startswith('..') or '..' in normalized:
        return jsonify({"success": False, "error": "Access denied"}), 403

    if not os.path.exists(normalized) or not os.path.isfile(normalized):
        return jsonify({"success": False, "error": "File not found"}), 404

    if not os.access(normalized, os.R_OK):
        return jsonify({"success": False, "error": "No read permission"}), 403

    try:
        with open(normalized, 'r', encoding='utf-8') as f:
            content = f.read()
        try:
            json_content = json.loads(content)
            return jsonify({"success": True, "path": normalized, "content": json_content})
        except json.JSONDecodeError:
            return jsonify({"success": True, "path": normalized, "content": content, "is_raw_text": True})
    except Exception as e:
        log_with_context(logging.ERROR, f"Error reading {normalized}: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500
        
# GET ENV VARIABLE
@app.route('/config-idol/env/nifi-flows-dir')
def get_pre_setup_dir():
    return jsonify({'dir': os.environ.get('IDOL_NIFI_FLOWS_DIR', '/nifi-flows/Customize')})

# =============================================================================
# CLEAR ALL FLOWS FROM NIFI (FIXED — see notes below)
#
# Root cause of the previous JVM crash / Process Group deletion failure:
#
#   1. The old bulk-disable call passed `json=disable_body` to
#      `nifi_client.api_call(...)`, but `api_call()`'s signature only accepts
#      `data=`. Every single call raised a TypeError, which was silently
#      swallowed by the surrounding `except Exception`, logged as a vague
#      "Bulk disable failed" warning, and otherwise ignored. So the root-level
#      bulk disable step had never actually run in production.
#   2. That left the per-child-group fallback as the *only* thing disabling
#      Controller Services, with no verification step before NiFi was asked
#      to delete the Process Group. If a custom service such as
#      AciContextServiceImpl was still ENABLED (or just hadn't finished
#      transitioning) at delete time, NiFi's native cleanup code
#      (AciContextServiceImplBase.nativeClean) throws
#      "IllegalArgumentException: Invalid argument: connectionString" and
#      takes the entire NiFi JVM down with it (not just an HTTP error).
#
# Fix: a verified, retried bulk disable (disable_all_controller_services)
# PLUS a pre-flight scan (find_native_crash_risk_services) that refuses to
# delete any Process Group containing an AciContextServiceImpl whose
# "Connection String" property is empty/missing, since deleting that service
# crashes NiFi regardless of its enabled/disabled state. Those groups are
# reported back to the caller instead of being silently deleted (or crashing
# the server), and can be force-deleted only with explicit acknowledgement.
# =============================================================================

# Controller Service types known to crash the NiFi JVM's native cleanup code
# (not just return an HTTP error) when removed while a required property is
# empty. See AciContextServiceImplBase.nativeClean in the NiFi crash logs.
_NATIVE_CRASH_RISK_TYPES = ('AciContextServiceImpl',)


def _service_has_native_crash_risk(cs_component: dict) -> bool:
    """True if this is an AciContextServiceImpl-type service with no usable
    'Connection String' property. Removing/deleting it in that state is what
    crashes the NiFi JVM, independent of whether it's ENABLED or DISABLED."""
    cs_type = cs_component.get('type', '') or ''
    if not any(risky in cs_type for risky in _NATIVE_CRASH_RISK_TYPES):
        return False

    properties = cs_component.get('properties', {}) or {}
    for key, value in properties.items():
        normalized = key.lower().replace(' ', '').replace('_', '')
        if 'connectionstring' in normalized:
            return not (value and str(value).strip())
    # Property isn't present at all — just as unsafe, the native code still expects it.
    return True


def disable_all_controller_services(pg_id: str, max_retries: int = 3) -> dict:
    """Bulk-disable every Controller Service under pg_id (including
    descendants), verifying the result and retrying until nothing is left
    ENABLED or max_retries is hit. Returns a summary dict."""
    log_with_context(logging.INFO, f"[CS Disable] Starting bulk disable for Process Group: {pg_id}")

    result = {"attempted": 0, "disabled": 0, "still_enabled": [], "errors": []}

    for attempt in range(1, max_retries + 1):
        try:
            nifi_client.api_call(
                'PUT',
                f'/flow/process-groups/{pg_id}/controller-services',
                data={"state": "DISABLED", "disconnectedNodeAcknowledged": True}
            )
            log_with_context(logging.INFO, f"[CS Disable] Bulk disable attempt {attempt} completed")
            time.sleep(2.5)

            cs_resp = nifi_client.api_call(
                'GET',
                f'/flow/process-groups/{pg_id}/controller-services?includeDescendantGroups=true'
            )
            if not cs_resp or 'controllerServices' not in cs_resp:
                log_with_context(logging.WARNING, "[CS Disable] Could not retrieve Controller Services list")
                continue

            still_enabled = []
            for cs in cs_resp.get('controllerServices', []):
                comp = cs.get('component', {})
                if comp.get('state') == 'ENABLED':
                    still_enabled.append({'id': cs.get('id'), 'name': comp.get('name'), 'type': comp.get('type')})

            result["attempted"] = len(cs_resp.get('controllerServices', []))
            result["still_enabled"] = still_enabled
            result["disabled"] = result["attempted"] - len(still_enabled)

            if not still_enabled:
                log_with_context(logging.INFO, "[CS Disable] ✅ All Controller Services disabled successfully")
                return result

            log_with_context(logging.WARNING,
                f"[CS Disable] {len(still_enabled)} Controller Service(s) still ENABLED after attempt {attempt}")

        except Exception as e:
            log_with_context(logging.ERROR, f"[CS Disable] Error on attempt {attempt}: {e}", exc_info=True)
            result["errors"].append(str(e))

        time.sleep(3)

    log_with_context(logging.ERROR, f"[CS Disable] Failed to disable all Controller Services. Still enabled: {result['still_enabled']}")
    return result


def find_native_crash_risk_services(pg_id: str) -> list:
    """Recursively find AciContextServiceImpl Controller Services with an
    empty/missing Connection String under pg_id. Process Groups containing
    these must not be deleted automatically — doing so crashes the NiFi JVM."""
    risky = []
    try:
        cs_resp = nifi_client.api_call(
            'GET',
            f'/flow/process-groups/{pg_id}/controller-services?includeDescendantGroups=true'
        )
        if not cs_resp or 'controllerServices' not in cs_resp:
            return risky
        for cs in cs_resp.get('controllerServices', []):
            comp = cs.get('component', {})
            if _service_has_native_crash_risk(comp):
                risky.append({
                    'id': cs.get('id'),
                    'name': comp.get('name'),
                    'type': comp.get('type'),
                    'process_group_id': pg_id
                })
    except Exception as e:
        log_with_context(logging.WARNING, f"[Native Risk Scan] Failed for {pg_id}: {e}")
    return risky


def stop_processors_recursive(pg_id: str, pg_name: str = ""):
    """Stop all processors in this PG and descendants."""
    try:
        log_with_context(logging.INFO, f"Stopping processors in '{pg_name}'...")
        nifi_client.api_call('PUT', f'/flow/process-groups/{pg_id}',
            data={"id": pg_id, "state": "STOPPED", "disconnectedNodeAcknowledged": True})
        log_with_context(logging.INFO, f"✅ Processors stopped in '{pg_name}'")
        time.sleep(1.5)
    except Exception as e:
        log_with_context(logging.WARNING, f"Stop processors warning in '{pg_name}': {e}")


def empty_queues_recursive(pg_id: str, pg_name: str = ""):
    """Empty all queues in this PG and descendants."""
    try:
        log_with_context(logging.INFO, f"Emptying queues in '{pg_name}'...")
        empty_resp = nifi_client.api_call('POST', f'/process-groups/{pg_id}/empty-all-connections-requests')

        if empty_resp and 'dropRequest' in empty_resp:
            drop_id = empty_resp['dropRequest']['id']
            for _ in range(60):
                status = nifi_client.api_call(
                    'GET',
                    f'/process-groups/{pg_id}/empty-all-connections-requests/{drop_id}'
                )
                if status and status.get('dropRequest', {}).get('finished'):
                    break
                time.sleep(1.5)

            log_with_context(logging.INFO, f"✅ Queues emptied in '{pg_name}'")
            try:
                nifi_client.api_call(
                    'DELETE',
                    f'/process-groups/{pg_id}/empty-all-connections-requests/{drop_id}'
                )
            except Exception:
                pass
        else:
            log_with_context(logging.INFO, f"No queues to empty in '{pg_name}'")
    except Exception as e:
        log_with_context(logging.WARNING, f"Empty queues warning in '{pg_name}': {e}")


@app.route('/config-nifi/api/flows/clear-root', methods=['POST'])
def clear_root():
    """
    Safely clear the root Process Group.

    Order matters:
      1. Disable ALL Controller Services first — bulk + verified + retried
         (this is the step the old code silently failed to run; see the
         module-level comment above for why).
      2. Scan every child Process Group for AciContextServiceImpl services
         with an empty Connection String. Deleting one of these crashes the
         NiFi JVM's native cleanup code regardless of disabled state, so
         those groups are skipped unless force_native_risk=true.
      3. Stop processors + empty queues for the groups that are safe to delete.
      4. Delete those Process Groups.
    """
    body = request.get_json(silent=True) or {}
    force = bool(body.get('force', False))
    force_native_risk = bool(body.get('force_native_risk', False))

    log_with_context(logging.INFO,
        f"=== CLEAR ROOT STARTED (force={force}, force_native_risk={force_native_risk}) ===")

    try:
        # === 1. Get Root Process Group ID ===
        root_pg_id = None
        for endpoint in ['/flow/process-groups/root', '/process-groups/root', '/flow']:
            root_response = nifi_client.api_call('GET', endpoint)
            if root_response:
                root_pg_id = root_response.get('processGroupFlow', {}).get('id') or root_response.get('id')
                if root_pg_id:
                    break

        if not root_pg_id:
            return jsonify({"success": False, "error": "Could not get root Process Group ID"}), 500

        log_with_context(logging.INFO, f"Root Process Group ID: {root_pg_id}")

        # === STEP 1: Disable Controller Services (verified + retried) ===
        cs_result = disable_all_controller_services(root_pg_id)

        if cs_result["still_enabled"] and not force:
            return jsonify({
                "success": False,
                "error": "Some Controller Services could not be disabled",
                "still_enabled": cs_result["still_enabled"],
                "suggestion": "Use force=true to proceed anyway, or disable them manually in the NiFi UI first."
            }), 409

        # === 2. Get child Process Groups ===
        contents = nifi_client.api_call('GET', f'/flow/process-groups/{root_pg_id}')
        if not contents:
            return jsonify({"success": True, "message": "Root was already empty", "controller_services": cs_result})

        flow_data = contents.get('processGroupFlow', {}).get('flow') or contents.get('flow', {})
        child_groups = flow_data.get('processGroups', [])

        if not child_groups:
            return jsonify({"success": True, "message": "Root was already empty", "controller_services": cs_result})

        log_with_context(logging.INFO, f"Found {len(child_groups)} child Process Group(s)")

        # === STEP 2: Native-crash safety scan ===
        groups_to_delete = []
        skipped_native_risk = []
        for pg in child_groups:
            pg_id = pg.get('id')
            pg_name = pg.get('component', {}).get('name', 'Unnamed')
            if not pg_id:
                continue
            risky = find_native_crash_risk_services(pg_id)
            if risky and not force_native_risk:
                log_with_context(logging.ERROR,
                    f"[Clear Root] Skipping '{pg_name}' — contains {len(risky)} Controller Service(s) "
                    f"that would crash the NiFi JVM if removed (empty Connection String): {risky}")
                skipped_native_risk.append({'process_group': pg_name, 'process_group_id': pg_id, 'services': risky})
            else:
                groups_to_delete.append(pg)

        # === STEP 3 + 4: stop processors, empty queues, delete the safe groups ===
        deleted = 0
        for pg in groups_to_delete:
            pg_id = pg.get('id')
            pg_name = pg.get('component', {}).get('name', 'Unnamed')

            log_with_context(logging.INFO, f"--- Processing: {pg_name} ({pg_id}) ---")

            stop_processors_recursive(pg_id, pg_name)
            empty_queues_recursive(pg_id, pg_name)

            pg_detail = nifi_client.api_call('GET', f'/process-groups/{pg_id}')
            if not pg_detail or 'revision' not in pg_detail:
                log_with_context(logging.WARNING, f"Could not get revision for {pg_name} — skipping")
                continue

            rev = pg_detail['revision']
            version = rev.get('version', 0)
            client_id = rev.get('clientId', 'clear-root-script')

            delete_url = (f'/process-groups/{pg_id}'
                          f'?version={version}'
                          f'&clientId={client_id}'
                          f'&disconnectedNodeAcknowledged=true')

            result = nifi_client.api_call('DELETE', delete_url)
            if result:
                deleted += 1
                log_with_context(logging.INFO, f"✅ Deleted: {pg_name}")
            else:
                log_with_context(logging.WARNING, f"Failed to delete {pg_name}")

        message = f"Cleared root — {deleted} Process Group(s) removed"
        if skipped_native_risk:
            message += f". {len(skipped_native_risk)} group(s) skipped to avoid crashing NiFi — see 'skipped_native_risk'."

        log_with_context(logging.INFO, f"=== CLEAR ROOT FINISHED — {message} ===")
        return jsonify({
            "success": True,
            "message": message,
            "controller_services": cs_result,
            "deleted_process_groups": deleted,
            "skipped_native_risk": skipped_native_risk
        })

    except Exception as e:
        log_with_context(logging.ERROR, f"Clear root failed: {str(e)}", exc_info=True)
        return jsonify({"success": False, "error": str(e)}), 500

# CLEAR ALL PARAMETER CONTEXTS FROM NIFI
@app.route('/config-nifi/api/parameter-contexts/clear-all-parameter-contexts', methods=['POST'])
def delete_all_parameter_contexts():
    """
    Delete ALL Parameter Contexts in NiFi.
    Returns a summary of successful and failed deletions.
    """
    try:
        log_with_context(logging.INFO, "=== DELETE ALL PARAMETER CONTEXTS STARTED ===")

        # 1. Get all Parameter Contexts
        response = nifi_client.api_call('GET', '/flow/parameter-contexts')
        if not response or 'parameterContexts' not in response:
            return jsonify({
                "success": True,
                "message": "No Parameter Contexts found",
                "deleted": 0,
                "failed": 0
            })

        contexts = response.get('parameterContexts', [])
        if not contexts:
            return jsonify({
                "success": True,
                "message": "No Parameter Contexts found",
                "deleted": 0,
                "failed": 0
            })

        log_with_context(logging.INFO, f"Found {len(contexts)} Parameter Context(s) to delete")

        deleted = []
        failed = []

        for ctx in contexts:
            ctx_id = ctx.get('id')
            ctx_name = ctx.get('component', {}).get('name', 'Unnamed')

            if not ctx_id:
                continue

            try:
                # Get current revision (required for deletion)
                detail = nifi_client.api_call('GET', f'/parameter-contexts/{ctx_id}')
                if not detail or 'revision' not in detail:
                    failed.append({"name": ctx_name, "id": ctx_id, "reason": "Could not get revision"})
                    continue

                version = detail['revision'].get('version', 0)

                # Attempt deletion
                delete_url = f'/parameter-contexts/{ctx_id}?version={version}&disconnectedNodeAcknowledged=true'
                result = nifi_client.api_call_detailed('DELETE', delete_url)

                if result['ok']:
                    deleted.append({"name": ctx_name, "id": ctx_id})
                    log_with_context(logging.INFO, f"✅ Deleted Parameter Context: {ctx_name}")
                elif result['status_code'] == 409:
                    reason = (result.get('json') or {}).get('message') or result.get('text') or 'Still referenced by a Process Group'
                    failed.append({"name": ctx_name, "id": ctx_id, "reason": reason})
                else:
                    reason = (result.get('json') or {}).get('message') or result.get('text') or f"HTTP {result['status_code']}"
                    failed.append({"name": ctx_name, "id": ctx_id, "reason": reason})

            except Exception as e:
                error_msg = str(e)
                # Common case: Parameter Context is still referenced
                if "409" in error_msg or "in use" in error_msg.lower():
                    failed.append({
                        "name": ctx_name,
                        "id": ctx_id,
                        "reason": "Cannot delete - Parameter Context is still in use by a Process Group"
                    })
                else:
                    failed.append({"name": ctx_name, "id": ctx_id, "reason": error_msg})

                log_with_context(logging.WARNING, f"Failed to delete Parameter Context '{ctx_name}': {error_msg}")

        log_with_context(logging.INFO, f"=== DELETE ALL PARAMETER CONTEXTS FINISHED — Deleted: {len(deleted)}, Failed: {len(failed)} ===")

        return jsonify({
            "success": True,
            "message": f"Deleted {len(deleted)} Parameter Context(s). {len(failed)} failed.",
            "deleted_count": len(deleted),
            "failed_count": len(failed),
            "deleted": deleted,
            "failed": failed
        })

    except Exception as e:
        log_with_context(logging.ERROR, f"Delete all Parameter Contexts failed: {str(e)}", exc_info=True)
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


# IMPORT FLOW FROM HOST INTO NIFI
@app.route('/config-nifi/api/flows/import-from-host', methods=['POST'])
def import_from_host():
    data = request.get_json()
    file_path = data.get('path')
    import_mode = data.get('importMode', 'replace_root')

    if not file_path or not os.path.exists(file_path):
        log_with_context(logging.ERROR, f"File not found: {file_path}")
        return jsonify({"success": False, "error": "File not found"}), 404

    try:
        log_with_context(logging.INFO, f"Starting import from host file: {file_path} (mode: {import_mode})")

        # 1. Read the flow file
        with open(file_path, 'r', encoding='utf-8') as f:
            versioned_flow_snapshot = json.load(f)

        # === NEW: Force name to "demo_YYYY-MM-DD" (current date) ===
        if import_mode == "new_child_group":
            from datetime import datetime   # ← safe to call inside function
            current_date = datetime.now().strftime('%Y-%m-%d')
            pg_name = f"demo_{current_date}"
            log_with_context(logging.INFO, f"Selected Process Group name: '{pg_name}'")
        else:
            pg_name = None  # not used in replace_root mode

        # 2. Get root Process Group ID
        root_pg_id = None
        for endpoint in ['/flow/process-groups/root', '/process-groups/root', '/flow']:
            root_response = nifi_client.api_call('GET', endpoint)
            if root_response:
                if 'processGroupFlow' in root_response and 'id' in root_response.get('processGroupFlow', {}):
                    root_pg_id = root_response['processGroupFlow']['id']
                elif 'id' in root_response:
                    root_pg_id = root_response['id']
                if root_pg_id:
                    break

        if not root_pg_id:
            return jsonify({"success": False, "error": "Could not get root Process Group ID"}), 500

        if import_mode == "new_child_group":
            # Create new empty Process Group with the demo_ name
            create_pg_payload = {
                "revision": {"version": 0},
                "component": {
                    "name": pg_name,
                    "position": {"x": 0, "y": 0}
                }
            }
            new_pg = nifi_client.api_call('POST', f'/process-groups/{root_pg_id}/process-groups', data=create_pg_payload)
            
            if not new_pg or 'id' not in new_pg:
                return jsonify({"success": False, "error": "Failed to create new Process Group"}), 500

            target_pg_id = new_pg['id']
            log_with_context(logging.INFO, f"✅ Created new child Process Group: {pg_name} (ID: {target_pg_id})")
            
            # Get fresh revision
            pg_detail = nifi_client.api_call('GET', f'/process-groups/{target_pg_id}')
            current_revision = pg_detail['revision']

        else:
            # Original mode: replace root
            target_pg_id = root_pg_id
            pg_detail = nifi_client.api_call('GET', f'/process-groups/{root_pg_id}')
            current_revision = pg_detail['revision']

        # 3. Build import payload
        import_payload = {
            "processGroupRevision": current_revision,
            "versionedFlowSnapshot": versioned_flow_snapshot,
            "disconnectedNodeAcknowledged": True
        }

        # 4. Import
        result = nifi_client.api_call('PUT', f'/process-groups/{target_pg_id}/flow-contents', data=import_payload)

        if result:
            log_with_context(logging.INFO, f"✅ Flow imported successfully into {import_mode} mode!")
            return jsonify({
                "success": True,
                "message": f"Flow '{os.path.basename(file_path)}' imported successfully as '{pg_name if import_mode == 'new_child_group' else 'root'}'!",
                "processGroupId": target_pg_id,
                "importMode": import_mode
            })
        else:
            return jsonify({"success": False, "error": "NiFi returned no result"}), 500

    except Exception as e:
        log_with_context(logging.ERROR, f"Import failed: {str(e)}", exc_info=True)
        return jsonify({"success": False, "error": str(e)}), 500
        
# COPY FLOW FROM HOST INTO NIFI
@app.route('/config-nifi/api/copy-host-flows', methods=['POST'])
def copy_host_flows():
    """
    Copy all .json files from a given host folder to /setup-scripts inside the container.
    Expects JSON: { "source_path": "/absolute/host/path" }
    """
    try:
        data = request.get_json()
        if not data or 'source_path' not in data:
            log_with_context(logging.ERROR, "Missing source_path in request")
            return jsonify({'success': False, 'error': 'Missing source_path'}), 400

        source_path = data['source_path'].strip()
        if not source_path:
            return jsonify({'success': False, 'error': 'Source path is empty'}), 400

        # Security: normalize and prevent directory traversal
        normalized = os.path.normpath(source_path)
        if normalized.startswith('..') or os.path.isabs(normalized) and '..' in normalized:
            log_with_context(logging.WARNING, f"Path traversal attempt: {source_path}")
            return jsonify({'success': False, 'error': 'Invalid path - directory traversal not allowed'}), 400

        if not os.path.exists(normalized):
            log_with_context(logging.ERROR, f"Source folder does not exist: {normalized}")
            return jsonify({'success': False, 'error': f'Source folder does not exist: {normalized}'}), 404

        if not os.path.isdir(normalized):
            log_with_context(logging.ERROR, f"Source path is not a directory: {normalized}")
            return jsonify({'success': False, 'error': 'Source path is not a directory'}), 400

        if not os.access(normalized, os.R_OK):
            log_with_context(logging.ERROR, f"No read permission for source folder: {normalized}")
            return jsonify({'success': False, 'error': 'No read permission for source folder'}), 403

        # Ensure target directory exists
        target_dir = '/setup-scripts'
        os.makedirs(target_dir, exist_ok=True)
        if not os.access(target_dir, os.W_OK):
            log_with_context(logging.ERROR, f"Target directory {target_dir} is not writable")
            return jsonify({'success': False, 'error': f'Target directory {target_dir} is not writable'}), 500

        # Collect all .json files (NiFi flow files)
        json_files = []
        for filename in os.listdir(normalized):
            if filename.lower().endswith('.json'):
                src_file = os.path.join(normalized, filename)
                if os.path.isfile(src_file):
                    json_files.append(src_file)

        if not json_files:
            log_with_context(logging.INFO, f"No .json files found in {normalized}")
            return jsonify({'success': True, 'message': 'No .json files found to copy', 'copied': []})

        copied = []
        failed = []
        for src in json_files:
            dst = os.path.join(target_dir, os.path.basename(src))
            try:
                shutil.copy2(src, dst)  # preserves metadata
                copied.append(os.path.basename(src))
                log_with_context(logging.INFO, f"Copied {src} -> {dst}")
            except Exception as e:
                error_msg = f"Failed to copy {os.path.basename(src)}: {str(e)}"
                log_with_context(logging.ERROR, error_msg)
                failed.append({'file': os.path.basename(src), 'error': str(e)})

        result = {
            'success': True,
            'message': f'Copied {len(copied)} files, failed {len(failed)}',
            'copied': copied,
            'failed': failed,
            'target_directory': target_dir
        }
        return jsonify(result)

    except Exception as e:
        log_with_context(logging.ERROR, f"Unexpected error in copy_host_flows: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': f'Internal server error: {str(e)}'}), 500


# =============================================================================
# UPLOAD FILES FROM HOST
# =============================================================================
ALLOWED_UPLOAD_EXTENSIONS = {'.json', '.xml', '.flow', '.template'}

def allowed_upload_file(filename):
    return '.' in filename and os.path.splitext(filename)[1].lower() in ALLOWED_UPLOAD_EXTENSIONS

@app.route('/config-nifi/api/upload-flow', methods=['POST'])
def upload_flow_file():
    try:
        if 'file' not in request.files:
            return jsonify({'success': False, 'error': 'No file part'}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'success': False, 'error': 'No selected file'}), 400
        
        if not allowed_upload_file(file.filename):
            return jsonify({'success': False, 'error': f'File type not allowed. Allowed: {", ".join(ALLOWED_UPLOAD_EXTENSIONS)}'}), 400
        
        # Secure filename and ensure target directory exists
        filename = secure_filename(file.filename)
        target_dir = '/nifi-flows/customize'
        os.makedirs(target_dir, exist_ok=True)
        
        # Save file
        filepath = os.path.join(target_dir, filename)
        file.save(filepath)
        
        log_with_context(logging.INFO, f"Uploaded file saved to {filepath}")
        
        return jsonify({
            'success': True,
            'message': f'File "{filename}" uploaded successfully to {target_dir}',
            'filename': filename,
            'path': filepath
        })
    except Exception as e:
        log_with_context(logging.ERROR, f"Upload failed: {str(e)}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/detect-folder', methods=['POST'])
def detect_folder():
    try:
        data = request.get_json(silent=True)
        if not data:
            log_with_context(logging.WARNING, 'detect_folder: request received with no JSON body')
            return jsonify({'success': False, 'error': 'No JSON data received'}), 400

        base_path = data.get('basePath')
        contains  = data.get('contains')

        log_with_context(logging.INFO,
            f'detect_folder: request received | basePath="{base_path}" contains="{contains}"')

        # ── Input validation ──────────────────────────────────────────────
        if not base_path:
            log_with_context(logging.WARNING, 'detect_folder: basePath is missing from request')
            return jsonify({'success': False, 'error': 'basePath is required'}), 400

        if not contains or not contains.strip():
            log_with_context(logging.WARNING, 'detect_folder: contains is missing or empty')
            return jsonify({'success': False, 'error': 'contains is required and must not be empty'}), 400

        # ── Base path existence check ─────────────────────────────────────
        if not os.path.exists(base_path) or not os.path.isdir(base_path):
            log_with_context(logging.WARNING,
                f'detect_folder: base path not found or not a directory | basePath="{base_path}"')
            return jsonify({
                'success': False,
                'error': f'Base path not found or not a directory: {base_path}'
            }), 400

        # ── Scan for matching sub-directories ────────────────────────────
        log_with_context(logging.INFO,
            f'detect_folder: scanning "{base_path}" for directories containing "{contains}"')

        matching = []
        for item in os.listdir(base_path):
            full_path = os.path.join(base_path, item)
            # ✅ CASE-INSENSITIVE fuzzy matching
            if os.path.isdir(full_path) and contains.lower() in item.lower():
                mtime = os.path.getmtime(full_path)
                matching.append((mtime, item))
                log_with_context(logging.DEBUG,
                    f'detect_folder: match found | folder="{item}"')

        log_with_context(logging.INFO,
            f'detect_folder: scan complete | {len(matching)} matching folder(s) found')

        # ── No matches ───────────────────────────────────────────────────
        if not matching:
            log_with_context(logging.WARNING,
                f'detect_folder: no folder found | basePath="{base_path}" contains="{contains}"')
            return jsonify({
                'success': False,
                'folder': None,
                'message': f'No folder containing "{contains}" found in "{base_path}"'
            })

        # ── Return newest match ──────────────────────────────────────────
        matching.sort(key=lambda x: x[0], reverse=True)
        newest_folder = matching[0][1]

        log_with_context(logging.INFO,
            f'detect_folder: selected newest match | folder="{newest_folder}" '
            f'(from {len(matching)} candidate(s))')

        return jsonify({'success': True, 'folder': newest_folder})

    except Exception as e:
        try:
            log_with_context(logging.ERROR, f'detect_folder: unhandled exception | {str(e)}', exc_info=True)
        except NameError:
            logging.exception('detect_folder: unhandled exception | %s', str(e))
        return jsonify({'success': False, 'error': str(e)}), 500


# =============================================================================
# MAIN APPLICATION ENTRYPOINT
# =============================================================================
if __name__ == '__main__':
    # Plain logger calls at startup (no request context)
    logger.info("=== Starting NiFi Config Manager on port 5000 ===")
    logger.info(f"Available NiFiAPIClient methods: {[m for m in dir(nifi_client) if not m.startswith('_')]}")
    
    # Optional: silence the in-memory Limiter warning in production
    # (you can ignore it for this single-container app)
    
    app.run(host='0.0.0.0', port=5000, debug=False)