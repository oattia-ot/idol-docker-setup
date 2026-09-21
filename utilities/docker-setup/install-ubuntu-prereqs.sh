#!/usr/bin/env bash
# =============================================================================
# install-ubuntu-prereqs.sh
# Install every host prerequisite required by idol-docker-setup on Ubuntu/Debian.
#
# Covers README Phase 2:
#   Docker Engine + Compose plugin, OpenJDK 21, OpenSSL, jq, git, curl, gnupg
#
# Usage:
#   sudo ./install-ubuntu-prereqs.sh
#   sudo ./install-ubuntu-prereqs.sh --with-optional   # helm, kubectl, minikube, ghostscript
#   ./install-ubuntu-prereqs.sh --verify-only
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

WITH_OPTIONAL=0
VERIFY_ONLY=0
DOCKER_USER="${SUDO_USER:-${USER:-$(id -un)}}"

usage() {
    cat <<EOF
${BOLD}install-ubuntu-prereqs.sh${NC} — Ubuntu/Debian host prerequisites for idol-docker-setup

USAGE
  sudo $0 [--with-optional] [--verify-only] [--user NAME]

OPTIONS
  --with-optional   Also install helm, kubectl, minikube, ghostscript
  --verify-only     Only check tools; do not install
  --user NAME       User to add to the docker group (default: ${DOCKER_USER})
  -h, --help        Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --with-optional) WITH_OPTIONAL=1; shift ;;
        --verify-only)   VERIFY_ONLY=1; shift ;;
        --user)          DOCKER_USER="$2"; shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

uname_s="$(uname -s 2>/dev/null || echo unknown)"
if [ "$uname_s" != "Linux" ]; then
    error "This script is for Ubuntu/Debian. Detected: $uname_s"
    error "Use utilities/docker-setup/install-macos-prereqs.sh on macOS."
    exit 1
fi

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    info "Host: ${PRETTY_NAME:-Linux}"
    case "${ID:-}" in
        ubuntu|debian) ;;
        *) warn "Untested distro '${ID:-unknown}'. Continuing with apt anyway." ;;
    esac
fi

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Run as root or with sudo:  sudo $0"
        exit 1
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

verify() {
    echo ""
    echo -e "${BOLD}Prerequisite check${NC}"
    local missing=0
    for cmd in docker java openssl jq git curl; do
        if have "$cmd"; then
            ok "$cmd → $(command -v "$cmd")"
        else
            error "missing: $cmd"
            missing=1
        fi
    done
    if docker compose version >/dev/null 2>&1 || have docker-compose; then
        ok "docker compose → $(docker compose version 2>/dev/null || docker-compose --version)"
    else
        error "missing: docker compose"
        missing=1
    fi
    have python3 && ok "python3 → $(python3 --version 2>&1)" || warn "python3 not found (only needed if you run the UI backend on the host)"
    if [ "$missing" -eq 0 ]; then
        ok "All required Phase 2 tools are present."
        return 0
    fi
    return 1
}

if [ "$VERIFY_ONLY" -eq 1 ]; then
    verify
    exit $?
fi

need_root

info "Updating apt package lists..."
apt-get update -y

info "Installing base tools (ca-certificates, curl, gnupg, git, jq, openssl, python3)..."
apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    git jq openssl python3 python3-pip \
    apt-transport-https software-properties-common

# ----- Docker Engine -----
if have docker && docker compose version >/dev/null 2>&1; then
    ok "Docker already installed: $(docker --version)"
else
    info "Installing Docker Engine + Compose plugin from Docker's official repo..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker
    systemctl enable --now containerd 2>/dev/null || true
fi

if id "$DOCKER_USER" >/dev/null 2>&1; then
    groupadd -f docker
    usermod -aG docker "$DOCKER_USER"
    ok "Added ${DOCKER_USER} to docker group (log out/in or run: newgrp docker)"
else
    warn "User ${DOCKER_USER} not found; skip docker group."
fi

# ----- Java 21 -----
if have java; then
    ok "Java already installed: $(java -version 2>&1 | head -1)"
else
    info "Installing OpenJDK 21..."
    apt-get install -y openjdk-21-jdk
fi

if [ "$WITH_OPTIONAL" -eq 1 ]; then
    info "Installing optional tools: helm, kubectl, minikube, ghostscript..."
    apt-get install -y ghostscript
    if ! have kubectl; then
        ver="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
        arch="amd64"
        case "$(uname -m)" in aarch64|arm64) arch="arm64" ;; esac
        curl -fsSL -o /tmp/kubectl "https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl"
        install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
        rm -f /tmp/kubectl
    fi
    if ! have helm; then
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    if ! have minikube; then
        arch="amd64"
        case "$(uname -m)" in aarch64|arm64) arch="arm64" ;; esac
        curl -fsSL -o /tmp/minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}"
        install -m 0755 /tmp/minikube /usr/local/bin/minikube
        rm -f /tmp/minikube
    fi
fi

echo ""
verify
echo ""
ok "Ubuntu prerequisites installed."
echo -e "Next:"
echo -e "  ${CYAN}export IDOL_BASE_PATH=/path/to/idol-docker-setup${NC}"
echo -e "  ${CYAN}./utilities/ui-config/deploy-setup-manager-ui.sh --deploy${NC}"
echo -e "  ${CYAN}./prepare-env.sh --setup-prerequisites${NC}"
echo -e "  ${CYAN}./init-setup.sh${NC}"
