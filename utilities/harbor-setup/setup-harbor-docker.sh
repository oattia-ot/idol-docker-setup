#!/bin/bash

# ============================================================
# setup-harbor-docker.sh
# Installs Harbor 2.15.1 via the official online installer.
# Handles Docker / Docker Compose prerequisites, harbor.yml
# configuration, and HTTPS setup.
#
# Config priority (highest → lowest):
#   1. CLI flags
#   2. Environment variables
#   3. Interactive prompt
#   4. Built-in default
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
RED=$'\033[0;31m';    GREEN=$'\033[0;32m';   YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m';   BLUE=$'\033[0;34m';    MAGENTA=$'\033[0;35m'
WHITE=$'\033[1;37m';  GRAY=$'\033[0;90m';    BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'; DIM=$'\033[2m';        RESET=$'\033[0m'

# --- Defaults ---
HARBOR_VERSION="${HARBOR_VERSION:-v2.15.1}"
HARBOR_INSTALL_DIR="${HARBOR_INSTALL_DIR:-/opt/harbor}"
HARBOR_HTTP_PORT="${HARBOR_HTTP_PORT:-5050}"
HARBOR_HTTPS_PORT="${HARBOR_HTTPS_PORT:-5443}"
HARBOR_SSL_DIR="${HARBOR_SSL_DIR:-}"
AUTO_YES=false

# ============================================================
# Help
# ============================================================

usage() {
    cat <<EOF

${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗
║               setup-harbor-docker.sh  —  Help                    ║
╚══════════════════════════════════════════════════════════════════╝${RESET}

${BOLD}${UNDERLINE}DESCRIPTION${RESET}
  Installs ${CYAN}Harbor${RESET} ${HARBOR_VERSION} using the official online installer.
  Configures ${CYAN}harbor.yml${RESET}, installs Docker and Docker Compose if needed,
  and starts all Harbor services.

  Configuration is resolved in this priority order:
    ${GREEN}1. CLI flag${RESET}  →  ${YELLOW}2. Env variable${RESET}  →  ${BLUE}3. Interactive prompt${RESET}  →  ${GRAY}4. Default${RESET}

${BOLD}${UNDERLINE}USAGE${RESET}
  ${WHITE}$(basename "$0")${RESET} ${GRAY}[OPTIONS]${RESET}
  ${WHITE}$(basename "$0")${RESET} ${CYAN}-d${RESET} | ${CYAN}--delete${RESET} ${GRAY}[--installed-folder <path>]${RESET}

${BOLD}${UNDERLINE}OPTIONS${RESET}

  ${CYAN}${BOLD}-H${RESET}, ${CYAN}${BOLD}--hostname${RESET} ${YELLOW}<hostname>${RESET}
        Hostname or IP address for the Harbor registry.
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_HOSTNAME${RESET}

  ${CYAN}${BOLD}--http-port${RESET} ${YELLOW}<port>${RESET}
        HTTP port for the Harbor web UI and API.
        ${DIM}Default${RESET}  : ${GRAY}5050${RESET}
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_HTTP_PORT${RESET}

  ${CYAN}${BOLD}--https-port${RESET} ${YELLOW}<port>${RESET}
        HTTPS port for the Harbor web UI and API.
        ${DIM}Default${RESET}  : ${GRAY}5443${RESET}
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_HTTPS_PORT${RESET}

  ${CYAN}${BOLD}--https${RESET}
        Enable HTTPS. Requires either ${CYAN}--ssl-dir${RESET} or ${CYAN}--cert${RESET}/${CYAN}--key${RESET}.
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_ENABLE_HTTPS=true${RESET}

  ${CYAN}${BOLD}--ssl-dir${RESET} ${YELLOW}<path>${RESET}
        Directory containing default certificate and key files.
        Default filenames: ${GRAY}idol-docker-host-fullchain.cert.pem${RESET} and ${GRAY}idol-docker-host.key.pem${RESET}
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_SSL_DIR${RESET}

  ${CYAN}${BOLD}--cert${RESET} ${YELLOW}<path>${RESET}
        Full path to the TLS certificate file (.crt / .pem).
        Overrides ${CYAN}--ssl-dir${RESET} if both are given.
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_CERT_PATH${RESET}

  ${CYAN}${BOLD}--key${RESET} ${YELLOW}<path>${RESET}
        Full path to the TLS private key file (.key).
        Overrides ${CYAN}--ssl-dir${RESET} if both are given.
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_KEY_PATH${RESET}

  ${CYAN}${BOLD}-v${RESET}, ${CYAN}${BOLD}--version${RESET} ${YELLOW}<version>${RESET}
        Harbor version tag to install.
        ${DIM}Default${RESET}  : ${GRAY}v2.15.1${RESET}
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_VERSION${RESET}

  ${CYAN}${BOLD}-f${RESET}, ${CYAN}${BOLD}--installed-folder${RESET} ${YELLOW}<path>${RESET}
        Directory where Harbor will be installed.
        ${DIM}Default${RESET}  : ${GRAY}/opt/harbor${RESET}
        ${DIM}Env var${RESET}  : ${YELLOW}HARBOR_INSTALL_DIR${RESET}

  ${CYAN}${BOLD}-y${RESET}, ${CYAN}${BOLD}--yes${RESET}
        Automatically confirm all prompts (non‑interactive).

  ${CYAN}${BOLD}-d${RESET}, ${CYAN}${BOLD}--delete${RESET}
        Delete the existing Harbor deployment (stops containers and removes volumes).
        Runs ${CYAN}docker compose down -v${RESET} in the Harbor installation directory.
        Use with ${CYAN}--installed-folder${RESET} to specify a non‑default installation path.

  ${CYAN}${BOLD}-h${RESET}, ${CYAN}${BOLD}--help${RESET}
        Show this help message and exit.

${BOLD}${UNDERLINE}ENVIRONMENT VARIABLES${RESET}
  ${YELLOW}HARBOR_HOSTNAME${RESET}        Registry hostname or IP        ${GRAY}(same as --hostname)${RESET}
  ${YELLOW}HARBOR_HTTP_PORT${RESET}       HTTP port                      ${GRAY}(same as --http-port)${RESET}
  ${YELLOW}HARBOR_HTTPS_PORT${RESET}      HTTPS port                     ${GRAY}(same as --https-port)${RESET}
  ${YELLOW}HARBOR_ENABLE_HTTPS${RESET}    Set to ${CYAN}true${RESET} to enable HTTPS       ${GRAY}(same as --https)${RESET}
  ${YELLOW}HARBOR_SSL_DIR${RESET}         Directory with default cert/key ${GRAY}(same as --ssl-dir)${RESET}
  ${YELLOW}HARBOR_CERT_PATH${RESET}       Path to TLS certificate        ${GRAY}(same as --cert)${RESET}
  ${YELLOW}HARBOR_KEY_PATH${RESET}        Path to TLS private key        ${GRAY}(same as --key)${RESET}
  ${YELLOW}HARBOR_VERSION${RESET}         Harbor image version tag       ${GRAY}(same as --version)${RESET}
  ${YELLOW}HARBOR_INSTALL_DIR${RESET}     Installation directory         ${GRAY}(same as --installed-folder)${RESET}

${BOLD}${UNDERLINE}EXAMPLES${RESET}
  ${GRAY}# Interactive install (will prompt for each value)${RESET}
  ${WHITE}$(basename "$0")${RESET}

  ${GRAY}# Non-interactive HTTP install with custom ports${RESET}
  ${WHITE}$(basename "$0")${RESET} ${CYAN}--hostname${RESET} ${GREEN}192.168.1.50${RESET} ${CYAN}--http-port${RESET} ${GREEN}9080${RESET} ${CYAN}--yes${RESET}

  ${GRAY}# HTTPS using SSL directory (default filenames)${RESET}
  ${WHITE}$(basename "$0")${RESET} ${CYAN}--hostname${RESET} ${GREEN}registry.mycompany.com${RESET} ${CYAN}--https${RESET} \\
    ${CYAN}--ssl-dir${RESET} ${GREEN}/etc/ssl/harbor${RESET} ${CYAN}--https-port${RESET} ${GREEN}443${RESET}

  ${GRAY}# Via environment variables${RESET}
  ${YELLOW}HARBOR_HOSTNAME${RESET}=registry.example.com ${YELLOW}HARBOR_ENABLE_HTTPS${RESET}=true \\
  ${YELLOW}HARBOR_SSL_DIR${RESET}=./ssl ${YELLOW}HARBOR_HTTP_PORT${RESET}=80 ${YELLOW}HARBOR_HTTPS_PORT${RESET}=443 \\
  ${WHITE}$(basename "$0")${RESET} ${CYAN}--yes${RESET}

  ${GRAY}# Delete an existing Harbor deployment${RESET}
  ${WHITE}$(basename "$0")${RESET} ${CYAN}--delete${RESET}
  ${WHITE}$(basename "$0")${RESET} ${CYAN}--delete --installed-folder${RESET} ${GREEN}/custom/harbor${RESET}

EOF
    exit 0
}

# ============================================================
# Argument Parsing
# ============================================================

HOSTNAME_ARG=""
HTTP_PORT_ARG=""
HTTPS_PORT_ARG=""
ENABLE_HTTPS_ARG=""
SSL_DIR_ARG=""
CERT_PATH_ARG=""
KEY_PATH_ARG=""
VERSION_ARG=""
INSTALLED_FOLDER_ARG=""
YES_ARG=false
DELETE_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)        usage ;;
        -H|--hostname)    HOSTNAME_ARG="$2";      shift 2 ;;
        --http-port)      HTTP_PORT_ARG="$2";     shift 2 ;;
        --https-port)     HTTPS_PORT_ARG="$2";    shift 2 ;;
        --https)          ENABLE_HTTPS_ARG="true"; shift 1 ;;
        --ssl-dir)        SSL_DIR_ARG="$2";       shift 2 ;;
        --cert)           CERT_PATH_ARG="$2";     shift 2 ;;
        --key)            KEY_PATH_ARG="$2";      shift 2 ;;
        -v|--version)     VERSION_ARG="$2";       shift 2 ;;
        -f|--installed-folder) INSTALLED_FOLDER_ARG="$2"; shift 2 ;;
        -y|--yes)         YES_ARG=true;           shift 1 ;;
        -d|--delete)      DELETE_MODE=true;       shift 1 ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${RESET}"
            echo "   Run '$(basename "$0") --help' for usage."
            exit 1 ;;
    esac
done

AUTO_YES="$YES_ARG"

# ============================================================
# Helper Functions
# ============================================================

# Always prompt for a value (interactive) – shows current value as default
prompt_with_default() {
    local var_name="$1"
    local prompt_msg="$2"
    local default_val="$3"
    local secret="${4:-false}"
    local current_val="${!var_name:-$default_val}"
    
    if [ "$AUTO_YES" = true ]; then
        printf -v "$var_name" '%s' "$current_val"
        return
    fi
    
    if [ -t 0 ]; then
        if [ "$secret" = "true" ]; then
            read -rsp "$(echo -e "${CYAN}${prompt_msg}${RESET} [${BOLD}${current_val}${RESET}]: ")" input; echo ""
        else
            read -rp "$(echo -e "${CYAN}${prompt_msg}${RESET} [${BOLD}${current_val}${RESET}]: ")" input
        fi
        printf -v "$var_name" '%s' "${input:-$current_val}"
    else
        printf -v "$var_name" '%s' "$current_val"
    fi
}

prompt_yn() {
    local var_name="$1"
    local prompt_msg="$2"
    local default_val="${3:-n}"
    local current_val="${!var_name:-}"
    
    if [ "$AUTO_YES" = true ]; then
        if [ -n "$current_val" ]; then
            return
        else
            printf -v "$var_name" '%s' "$([[ "$default_val" =~ ^[Yy]$ ]] && echo "true" || echo "false")"
            return
        fi
    fi
    
    if [ -z "$current_val" ]; then
        if [ -t 0 ]; then
            read -rp "$(echo -e "${CYAN}${prompt_msg}${RESET} [${BOLD}y/N${RESET}]: ")" input
            input="${input:-$default_val}"
        else
            input="$default_val"
        fi
        if [[ "$input" =~ ^[Yy]$ ]]; then
            printf -v "$var_name" '%s' "true"
        else
            printf -v "$var_name" '%s' "false"
        fi
    fi
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Prompt for port with validation
prompt_port() {
    local var_name="$1"
    local prompt_msg="$2"
    local default_val="$3"
    
    while true; do
        prompt_with_default "$var_name" "$prompt_msg" "$default_val"
        local port="${!var_name}"
        if validate_port "$port"; then
            break
        else
            echo -e "${RED}❌ Invalid port number. Please enter a number between 1 and 65535.${RESET}"
        fi
    done
}

confirm_config() {
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    echo ""
    read -rp "$(echo -e "${CYAN}Proceed with this configuration and install Harbor? [y/N]: ${RESET}")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ Installation cancelled by user.${RESET}"
        exit 0
    fi
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}❌ This script must be ${BOLD}${UNDERLINE}run as root or with sudo.${RESET}"
        echo ""
        exit 1
    fi
}

install_prerequisites() {
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD} Installing Prerequisites${RESET}"
    echo -e "${BOLD}${CYAN}============================================${RESET}"

    echo -e "  📦 Updating package lists and installing base tools ..."
    apt-get update -y -qq
    apt-get install -y -qq curl wget tar ca-certificates python3 openssl
    echo -e "  ${GREEN}✅ Base tools + Python3 + OpenSSL ready${RESET}"

    if command -v docker &>/dev/null; then
        echo -e "  ${GREEN}✅ docker${RESET}  $(command -v docker)  ${GRAY}(already installed)${RESET}"
    else
        echo -e "  🐳 Installing Docker ..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
        echo -e "  ${GREEN}✅ Docker installed and started${RESET}"
    fi

    if command -v docker-compose &>/dev/null; then
        echo -e "  ${GREEN}✅ docker-compose${RESET}  $(command -v docker-compose)  ${GRAY}(already installed)${RESET}"
    else
        local compose_version="v2.29.1"
        echo -e "  📦 Installing Docker Compose ${compose_version} ..."
        curl -fsSL \
            "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo -e "  ${GREEN}✅ Docker Compose installed${RESET}"
    fi

    echo ""
}

generate_self_signed_cert() {
    local cert_path="$1"
    local key_path="$2"
    local hostname="$3"

    echo -e "${YELLOW}⚠️  SSL files missing. Do you want to generate self-signed certificates?${RESET}"
    if ! prompt_yn GENERATE_CERT "Generate self-signed certificate and key?" "n"; then
        echo -e "${RED}❌ SSL certificate and key are required for HTTPS. Exiting.${RESET}"
        exit 1
    fi

    local cert_dir="$(dirname "$cert_path")"
    mkdir -p "$cert_dir"

    echo -e "  🔐 Generating self-signed certificate for ${CYAN}${hostname}${RESET} ..."
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$key_path" \
        -out "$cert_path" \
        -days 365 \
        -subj "/CN=${hostname}" \
        -addext "subjectAltName=DNS:${hostname}"

    chmod 644 "$cert_path"
    chmod 600 "$key_path"
    echo -e "  ${GREEN}✅ Self-signed certificate generated:${RESET}"
    echo -e "     📜 ${cert_path}"
    echo -e "     🔑 ${key_path}"
}

resolve_path() {
    local path="$1"
    # If path is empty or already absolute, return as is
    if [[ -z "$path" ]] || [[ "$path" =~ ^/ ]]; then
        echo "$path"
    else
        # Resolve relative path from current working directory
        (cd "$(pwd)" && cd "$path" 2>/dev/null && pwd) || echo "$path"
    fi
}

# ── Patch the host Docker daemon so it can reach the insecure registry ──
# Adds the Harbor registry (with appropriate port) to insecure-registries
# so that the host's Docker client can push/pull without TLS verification
# (required for self-signed certificates or HTTP-only mode).
update_docker_daemon_json() {
    local registry_host="$1"
    local port="$2"

    if [ -z "$registry_host" ]; then
        return 0
    fi

    local reg_entry="${registry_host}"
    [ -n "$port" ] && reg_entry="${registry_host}:${port}"

    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD} Patching Docker daemon for insecure registry${RESET}"
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "  Registry entry: ${CYAN}${reg_entry}${RESET}"

    python3 - <<PYEOF
import json
import os
daemon_file = '/etc/docker/daemon.json'
reg = '${reg_entry}'

if os.path.exists(daemon_file):
    with open(daemon_file, 'r') as f:
        try:
            config = json.load(f)
        except:
            config = {}
else:
    config = {}

if 'insecure-registries' not in config or not isinstance(config.get('insecure-registries'), list):
    config['insecure-registries'] = []

if reg not in config['insecure-registries']:
    config['insecure-registries'].append(reg)
    print(f"✅ Added {reg} to insecure-registries")
else:
    print(f"ℹ️  {reg} already in insecure-registries")

with open(daemon_file, 'w') as f:
    json.dump(config, f, indent=2)
PYEOF

    echo -e "  ${GREEN}✅ /etc/docker/daemon.json updated${RESET}"
    echo -e "  🔄 Restarting Docker daemon..."
    if systemctl restart docker; then
        echo -e "  ${GREEN}✅ Docker daemon restarted${RESET}"
    else
        echo -e "  ${YELLOW}⚠️  Failed to restart Docker. Please restart manually.${RESET}"
    fi
    echo ""
}

download_harbor() {
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD} Downloading Harbor ${HARBOR_VERSION}${RESET}"
    echo -e "${BOLD}${CYAN}============================================${RESET}"

    mkdir -p "${HARBOR_INSTALL_DIR}"
    cd "${HARBOR_INSTALL_DIR}"

    local tarball="harbor-online-installer-${HARBOR_VERSION}.tgz"
    local url="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${tarball}"

    echo -e "  ⬇️  Downloading ${CYAN}${url}${RESET} ..."
    wget --show-progress -q "$url"

    echo -e "  📂 Extracting ..."
    tar xzf "$tarball"

    echo -e "  🔧 Setting permissions ..."
    chmod -R a+rX "${HARBOR_INSTALL_DIR}/harbor"

    echo -e "  ${GREEN}✅ Harbor ${HARBOR_VERSION} extracted to ${HARBOR_INSTALL_DIR}/harbor${RESET}"
    echo ""
}

configure_harbor_yml() {
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD} Configuring harbor.yml${RESET}"
    echo -e "${BOLD}${CYAN}============================================${RESET}"

    local harbor_dir="${HARBOR_INSTALL_DIR}/harbor"
    local yml="${harbor_dir}/harbor.yml"
    local yml_tmpl="${harbor_dir}/harbor.yml.tmpl"

    # If harbor.yml does not exist, copy from template
    if [ ! -f "$yml" ]; then
        if [ -f "$yml_tmpl" ]; then
            echo -e "  ${GRAY}ℹ️  harbor.yml not found, copying from template...${RESET}"
            cp "$yml_tmpl" "$yml"
        else
            echo -e "${RED}❌ Neither harbor.yml nor harbor.yml.tmpl found in ${harbor_dir}${RESET}"
            exit 1
        fi
    fi

    # Backup original
    cp -n "${yml}" "${yml}.bak" 2>/dev/null \
        && echo -e "  ${GRAY}ℹ️  Original backed up → harbor.yml.bak${RESET}" \
        || echo -e "  ${GRAY}ℹ️  Backup already exists, skipping${RESET}"

    # Set hostname
    sed -i "s|^hostname: .*|hostname: ${HARBOR_HOSTNAME}|" "$yml"
    echo -e "  ${GREEN}✅ hostname    → ${CYAN}${HARBOR_HOSTNAME}${RESET}"

    # Robust Python patching for HTTP/HTTPS
    python3 <<PYEOF
import re

yml_path = '${yml}'
http_port = '${HARBOR_HTTP_PORT}'
enable_https = '${HARBOR_ENABLE_HTTPS}' == 'true'
https_port = '${HARBOR_HTTPS_PORT}'
cert_path = '${HARBOR_CERT_PATH}'
key_path = '${HARBOR_KEY_PATH}'

with open(yml_path, 'r') as f:
    lines = f.readlines()

out_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.lstrip()
    indent = line[:len(line)-len(stripped)]

    # Detect start of HTTPS section (may be commented)
    if re.match(r'^#?\s*https:', stripped):
        # If HTTPS is disabled, comment out the whole block
        if not enable_https:
            out_lines.append('#' + line if not line.startswith('#') else line)
            i += 1
            # Comment out all indented lines that follow
            while i < len(lines) and (lines[i].startswith(' ') or lines[i].startswith('\t')):
                out_lines.append('#' + lines[i] if not lines[i].startswith('#') else lines[i])
                i += 1
            continue
        else:
            # Uncomment the https: line
            if line.startswith('#'):
                line = line.lstrip('#').lstrip()
            out_lines.append(line)
            i += 1
            # Process indented lines
            while i < len(lines) and (lines[i].startswith(' ') or lines[i].startswith('\t')):
                sub_line = lines[i]
                sub_stripped = sub_line.lstrip()
                sub_indent = sub_line[:len(sub_line)-len(sub_stripped)]
                # Uncomment if needed
                if sub_line.startswith('#'):
                    sub_line = sub_line.lstrip('#').lstrip()
                    sub_stripped = sub_line.lstrip()
                    sub_indent = sub_line[:len(sub_line)-len(sub_stripped)]
                # Replace port, certificate, private_key
                if re.match(r'port:', sub_stripped):
                    out_lines.append(sub_indent + 'port: ' + https_port + '\n')
                elif re.match(r'certificate:', sub_stripped):
                    out_lines.append(sub_indent + 'certificate: ' + cert_path + '\n')
                elif re.match(r'private_key:', sub_stripped):
                    out_lines.append(sub_indent + 'private_key: ' + key_path + '\n')
                else:
                    out_lines.append(sub_line)
                i += 1
            continue

    # Handle HTTP port
    if re.match(r'^http:', stripped):
        out_lines.append(line)
        i += 1
        while i < len(lines) and (lines[i].startswith(' ') or lines[i].startswith('\t')):
            sub_line = lines[i]
            sub_stripped = sub_line.lstrip()
            sub_indent = sub_line[:len(sub_line)-len(sub_stripped)]
            if re.match(r'port:', sub_stripped):
                out_lines.append(sub_indent + 'port: ' + http_port + '\n')
            else:
                out_lines.append(sub_line)
            i += 1
        continue

    # All other lines
    out_lines.append(line)
    i += 1

with open(yml_path, 'w') as f:
    f.writelines(out_lines)

print("harbor.yml patched successfully")
PYEOF

    if [ "$HARBOR_ENABLE_HTTPS" = "true" ]; then
        echo -e "  ${GREEN}✅ http.port   → ${CYAN}${HARBOR_HTTP_PORT}${RESET}"
        echo -e "  ${GREEN}✅ https.port  → ${CYAN}${HARBOR_HTTPS_PORT}${RESET}"
        echo -e "  ${GREEN}✅ certificate → ${CYAN}${HARBOR_CERT_PATH}${RESET}"
        echo -e "  ${GREEN}✅ private_key → ${CYAN}${HARBOR_KEY_PATH}${RESET}"
    else
        echo -e "  ${GREEN}✅ http.port   → ${CYAN}${HARBOR_HTTP_PORT}${RESET}"
        echo -e "  ${YELLOW}⚠️  HTTPS disabled${RESET}  ${GRAY}(HTTP-only mode)${RESET}"
    fi

    echo ""
}

run_installer() {
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD} Running Harbor Installer${RESET}"
    echo -e "${BOLD}${CYAN}============================================${RESET}"

    cd "${HARBOR_INSTALL_DIR}/harbor"

    echo -e "  🚀 Running ${CYAN}./prepare${RESET} ..."
    ./prepare

    echo ""
    echo -e "  🔥 Running ${CYAN}./install.sh${RESET} ${GRAY}(pulling images — may take 5–15 minutes)${RESET} ..."
    ./install.sh

    echo ""
}

print_summary() {
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD}${GREEN} ✅ Harbor ${HARBOR_VERSION} installed successfully!${RESET}"
    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo ""

    if [ "$HARBOR_ENABLE_HTTPS" = "true" ]; then
        echo -e "  🌐 Web UI  : ${CYAN}https://${HARBOR_HOSTNAME}:${HARBOR_HTTPS_PORT}${RESET}"
        echo -e "  🐳 Login   : ${CYAN}docker login ${HARBOR_HOSTNAME}:${HARBOR_HTTPS_PORT}${RESET}"
    else
        echo -e "  🌐 Web UI  : ${CYAN}http://${HARBOR_HOSTNAME}:${HARBOR_HTTP_PORT}${RESET}"
        echo -e "  🐳 Login   : ${CYAN}docker login ${HARBOR_HOSTNAME}:${HARBOR_HTTP_PORT}${RESET}"
    fi
    echo -e "                ${CYAN}Or${RESET}"
    echo -e "  🐳 Login   : ${CYAN}docker login localhost:${HARBOR_HTTP_PORT}${RESET}"

    echo -e "  👤 Username: ${GREEN}admin${RESET}"
    echo -e "  🔑 Password: ${GREEN}Harbor12345${RESET}"
    echo ""

    echo -e "${BOLD}${UNDERLINE}Useful commands${RESET}"
    echo -e "  ${CYAN}cd ${HARBOR_INSTALL_DIR}/harbor${RESET}"
    echo -e "  ${GRAY}docker-compose ps               ${RESET}# status"
    echo -e "  ${GRAY}docker-compose logs -f          ${RESET}# tail logs"
    echo -e "  ${GRAY}docker-compose down             ${RESET}# stop"
    echo -e "  ${GRAY}docker-compose up -d            ${RESET}# restart"
    echo ""

    echo -e "${BOLD}${UNDERLINE}To change ports later${RESET}"
    echo -e "  ${GRAY}1. Edit ${HARBOR_INSTALL_DIR}/harbor/harbor.yml${RESET}"
    echo -e "  ${GRAY}2. Run  ./prepare${RESET}"
    echo -e "  ${GRAY}3. Run  docker-compose down && docker-compose up -d${RESET}"
    echo ""
}

# ============================================================
# Delete Mode
# ============================================================

delete_harbor() {
    # Resolve installation directory using CLI/env/default
    local install_dir="${INSTALLED_FOLDER_ARG:-${HARBOR_INSTALL_DIR}}"
    local harbor_dir="${install_dir}/harbor"

    echo -e "${BOLD}${CYAN}============================================${RESET}"
    echo -e "${BOLD} Deleting Harbor Deployment${RESET}"
    echo -e "${BOLD}${CYAN}============================================${RESET}"

    if [ ! -d "$harbor_dir" ]; then
        echo -e "${RED}❌ Harbor directory not found: ${harbor_dir}${RESET}"
        echo -e "   No deployment to delete."
        exit 1
    fi

    if [ ! -f "${harbor_dir}/docker-compose.yml" ]; then
        echo -e "${RED}❌ docker-compose.yml not found in ${harbor_dir}${RESET}"
        echo -e "   This does not appear to be a valid Harbor installation."
        exit 1
    fi

    cd "$harbor_dir"
    echo -e "  🛑 Stopping containers and removing volumes..."
    if command -v docker-compose &>/dev/null; then
        docker-compose down -v
    else
        docker compose down -v
    fi

    echo -e "  ${GREEN}✅ Harbor containers stopped and volumes removed.${RESET}"
    echo ""
    echo -e "  ${YELLOW}⚠️  The installation directory (${harbor_dir}) still contains configuration files."
    echo -e "     To completely remove it, run: ${CYAN}${BOLD}sudo rm -rf ${harbor_dir}${RESET}"
    echo ""
    exit 0
}

# ============================================================
# Main
# ============================================================

# If delete mode is requested, perform deletion and exit
if [ "$DELETE_MODE" = true ]; then
    check_root
    delete_harbor
fi

# Otherwise proceed with normal installation
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║       Harbor Registry  —  Docker Compose Installer       ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

check_root

# --- Resolve all config values ---
[ -n "$VERSION_ARG"     ] && HARBOR_VERSION="$VERSION_ARG"
[ -n "$INSTALLED_FOLDER_ARG" ] && HARBOR_INSTALL_DIR="$INSTALLED_FOLDER_ARG"

# Hostname
HARBOR_HOSTNAME="${HOSTNAME_ARG:-${HARBOR_HOSTNAME:-}}"
prompt_with_default HARBOR_HOSTNAME "🌐 Harbor hostname or IP" "idol-docker-host"

# HTTP port - always prompt with current value
HARBOR_HTTP_PORT="${HTTP_PORT_ARG:-${HARBOR_HTTP_PORT:-5050}}"
prompt_port HARBOR_HTTP_PORT "🌍 HTTP port" "$HARBOR_HTTP_PORT"

# HTTPS enable
HARBOR_ENABLE_HTTPS="${ENABLE_HTTPS_ARG:-${HARBOR_ENABLE_HTTPS:-}}"
prompt_yn HARBOR_ENABLE_HTTPS "🔒 Enable HTTPS?" "n"

if [ "$HARBOR_ENABLE_HTTPS" = "true" ]; then
    # HTTPS port - always prompt with current value
    HARBOR_HTTPS_PORT="${HTTPS_PORT_ARG:-${HARBOR_HTTPS_PORT:-5443}}"
    prompt_port HARBOR_HTTPS_PORT "🌍 HTTPS port" "$HARBOR_HTTPS_PORT"
    # SSL directory
    HARBOR_SSL_DIR="${SSL_DIR_ARG:-${HARBOR_SSL_DIR:-}}"
    # Compute absolute path of the default relative path "../generate-ssl-certs/ssl/intermediate/certs/"
    DEFAULT_SSL_ABS="$(resolve_path "../generate-ssl-certs/ssl/intermediate/certs")"
    # Show the absolute default in the prompt, but keep the original relative string as the default value
    prompt_with_default HARBOR_SSL_DIR "📂 SSL certificate & key directory " "${DEFAULT_SSL_ABS}"

    DEFAULT_CERT_PATH="${HARBOR_SSL_DIR}/idol-docker-host-fullchain.cert.pem"
    DEFAULT_KEY_PATH="${HARBOR_SSL_DIR}/idol-docker-host.key.pem"

    HARBOR_CERT_PATH="${CERT_PATH_ARG:-${HARBOR_CERT_PATH:-${DEFAULT_CERT_PATH}}}"
    HARBOR_KEY_PATH="${KEY_PATH_ARG:-${HARBOR_KEY_PATH:-${DEFAULT_KEY_PATH}}}"

    prompt_with_default HARBOR_CERT_PATH "📄 SSL certificate file (.pem)" "${DEFAULT_CERT_PATH}"
    prompt_with_default HARBOR_KEY_PATH "🔑 Private key file (.key)" "${DEFAULT_KEY_PATH}"

    # Check existence
    CERT_MISSING=false
    KEY_MISSING=false
    [ ! -f "$HARBOR_CERT_PATH" ] && CERT_MISSING=true
    [ ! -f "$HARBOR_KEY_PATH" ] && KEY_MISSING=true

    if [ "$CERT_MISSING" = true ] || [ "$KEY_MISSING" = true ]; then
        if [ "$CERT_MISSING" = true ] && [ "$KEY_MISSING" = true ]; then
            echo -e "${YELLOW}⚠️  Both certificate and key files are missing.${RESET}"
            generate_self_signed_cert "$HARBOR_CERT_PATH" "$HARBOR_KEY_PATH" "$HARBOR_HOSTNAME"
        else
            echo -e "${RED}❌ Inconsistent state: one SSL file exists, the other does not.${RESET}"
            echo -e "${RED}   Certificate: ${HARBOR_CERT_PATH} $([ -f "$HARBOR_CERT_PATH" ] && echo "(exists)" || echo "(missing)")${RESET}"
            echo -e "${RED}   Private key: ${HARBOR_KEY_PATH} $([ -f "$HARBOR_KEY_PATH" ] && echo "(exists)" || echo "(missing)")${RESET}"
            echo -e "${RED}   Please provide both or remove the existing one. Exiting.${RESET}"
            exit 1
        fi
    fi
else
    HARBOR_HTTPS_PORT="${HTTPS_PORT_ARG:-${HARBOR_HTTPS_PORT:-5443}}"
    HARBOR_CERT_PATH=""
    HARBOR_KEY_PATH=""
    HARBOR_SSL_DIR=""
fi

# --- Show configuration and ask for confirmation ---
echo ""
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "${BOLD} Configuration Summary${RESET}"
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "  🏷️  Harbor version   : ${CYAN}${HARBOR_VERSION}${RESET}"
echo -e "  📁 Install directory : ${CYAN}${HARBOR_INSTALL_DIR}${RESET}"
echo -e "  🌐 Hostname          : ${CYAN}${HARBOR_HOSTNAME}${RESET}"
echo -e "  🔌 HTTP port         : ${CYAN}${HARBOR_HTTP_PORT}${RESET}"
if [ "$HARBOR_ENABLE_HTTPS" = "true" ]; then
    echo -e "  🔒 HTTPS port        : ${CYAN}${HARBOR_HTTPS_PORT}${RESET}"
    echo -e "  📂 SSL directory     : ${CYAN}${HARBOR_SSL_DIR}${RESET}"
    echo -e "  📜 Certificate       : ${CYAN}${HARBOR_CERT_PATH}${RESET}"
    echo -e "  🔑 Private key       : ${CYAN}${HARBOR_KEY_PATH}${RESET}"
else
    echo -e "  🔒 HTTPS             : ${YELLOW}disabled${RESET}"
fi

# Ask for confirmation
confirm_config

# --- Run installation steps ---
install_prerequisites
download_harbor
configure_harbor_yml
run_installer

# ── Patch the host Docker daemon so it can reach the insecure registry ──
# Uses: DOCKER_INSECURE_REGISTRY (bare hostname) and the appropriate port
DOCKER_INSECURE_REGISTRY="${HARBOR_HOSTNAME}"
if [ "${HARBOR_ENABLE_HTTPS:-false}" = "true" ]; then
    update_docker_daemon_json "$DOCKER_INSECURE_REGISTRY" "$HARBOR_HTTPS_PORT"
else
    update_docker_daemon_json "$DOCKER_INSECURE_REGISTRY" "$HARBOR_HTTP_PORT"
fi

print_summary