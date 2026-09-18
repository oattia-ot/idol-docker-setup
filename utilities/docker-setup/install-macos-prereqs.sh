#!/usr/bin/env bash
# =============================================================================
# install-macos-prereqs.sh
# Install every host prerequisite required by idol-docker-setup on macOS.
#
# Replaces README Phase 2 (apt + systemd) with Homebrew + Docker Desktop.
# Required: Docker Desktop, OpenJDK 21, OpenSSL, jq, git, curl, bash 5, python3
#
# Usage:
#   ./install-macos-prereqs.sh
#   ./install-macos-prereqs.sh --with-optional   # helm, kubectl, minikube, ghostscript
#   ./install-macos-prereqs.sh --verify-only
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

WITH_OPTIONAL=0
VERIFY_ONLY=0

usage() {
    cat <<EOF
${BOLD}install-macos-prereqs.sh${NC} — macOS host prerequisites for idol-docker-setup

USAGE
  $0 [--with-optional] [--verify-only]

OPTIONS
  --with-optional   Also install helm, kubectl, minikube, ghostscript
  --verify-only     Only check tools; do not install
  -h, --help        Show this help

Do NOT run the Ubuntu apt / systemctl Phase 2 commands on a Mac.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --with-optional) WITH_OPTIONAL=1; shift ;;
        --verify-only)   VERIFY_ONLY=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

uname_s="$(uname -s 2>/dev/null || echo unknown)"
if [ "$uname_s" != "Darwin" ]; then
    error "This script is for macOS. Detected: $uname_s"
    error "Use utilities/docker-setup/install-ubuntu-prereqs.sh on Ubuntu."
    exit 1
fi

info "Host: macOS $(sw_vers -productVersion 2>/dev/null || echo unknown) ($(uname -m))"

have() { command -v "$1" >/dev/null 2>&1; }

ensure_brew_shellenv() {
    if have brew; then
        return 0
    fi
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

java_home_hint() {
    if have brew; then
        local p
        p="$(brew --prefix openjdk@21 2>/dev/null || true)"
        if [ -n "$p" ] && [ -x "${p}/bin/java" ]; then
            export PATH="${p}/bin:${PATH}"
            export JAVA_HOME="$p"
        fi
    fi
}

verify() {
    echo ""
    echo -e "${BOLD}Prerequisite check${NC}"
    java_home_hint
    local missing=0
    for cmd in docker git curl jq openssl python3; do
        if have "$cmd"; then
            ok "$cmd → $(command -v "$cmd")"
        else
            error "missing: $cmd"
            missing=1
        fi
    done
    if have java; then
        ok "java → $(java -version 2>&1 | head -1)"
    else
        error "missing: java (openjdk@21)"
        missing=1
    fi
    if docker compose version >/dev/null 2>&1 || have docker-compose; then
        ok "docker compose → $(docker compose version 2>/dev/null || docker-compose --version)"
    else
        error "missing: docker compose (start Docker Desktop)"
        missing=1
    fi
    if docker info >/dev/null 2>&1; then
        ok "Docker engine is running"
    else
        warn "Docker CLI found but engine is not running — open Docker Desktop"
        missing=1
    fi
    if have bash; then
        bash_major="$(bash -c 'echo $BASH_VERSINFO' 2>/dev/null || echo 0)"
        ok "bash → $(command -v bash) (major ${bash_major})"
        [ "${bash_major:-0}" -lt 4 ] && warn "System bash is 3.x; Homebrew bash is recommended for some utilities"
    fi
    if [ "$missing" -eq 0 ]; then
        ok "All required Phase 2 tools are present."
        return 0
    fi
    return 1
}

if [ "$VERIFY_ONLY" -eq 1 ]; then
    ensure_brew_shellenv
    verify
    exit $?
fi

# ----- Homebrew -----
ensure_brew_shellenv
if ! have brew; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ensure_brew_shellenv
fi
if ! have brew; then
    error "Homebrew is not on PATH. Add it to your shell profile and re-run."
    echo '  eval "$(/opt/homebrew/bin/brew shellenv)"   # Apple silicon'
    echo '  eval "$(/usr/local/bin/brew shellenv)"      # Intel'
    exit 1
fi
ok "Homebrew → $(command -v brew)"
brew update

# ----- Docker Desktop -----
if [ -d /Applications/Docker.app ]; then
    ok "Docker Desktop app is installed"
else
    info "Installing Docker Desktop (cask)..."
    brew install --cask docker
fi
open -a Docker
info "Waiting for Docker engine (up to ~3 minutes)..."
ready=0
i=0
while [ "$i" -lt 90 ]; do
    if have docker && docker info >/dev/null 2>&1; then
        ready=1
        break
    fi
    i=$((i + 1))
    sleep 2
done
if [ "$ready" -eq 1 ]; then
    ok "Docker engine is ready: $(docker --version)"
else
    warn "Docker Desktop was launched but the engine is not ready yet."
    warn "Wait until the menu-bar whale is idle, then re-run: $0 --verify-only"
fi

# ----- CLI tools -----
info "Installing CLI tools: bash git curl wget jq openssl python@3 coreutils gnu-sed..."
brew install bash git curl wget jq openssl python@3 coreutils gnu-sed

# ----- Java 21 -----
info "Installing OpenJDK 21..."
brew install openjdk@21
JDK="$(brew --prefix openjdk@21)"
if [ -d "${JDK}/libexec/openjdk.jdk" ]; then
    sudo ln -sfn "${JDK}/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk-21.jdk || \
        warn "Could not link JVM into /Library/Java/JavaVirtualMachines (sudo required)"
fi
export PATH="${JDK}/bin:${PATH}"
export JAVA_HOME="${JDK}"

PROFILE=""
if [ -n "${ZSH_VERSION:-}" ] || [ -f "${HOME}/.zprofile" ]; then
    PROFILE="${HOME}/.zprofile"
elif [ -f "${HOME}/.bash_profile" ]; then
    PROFILE="${HOME}/.bash_profile"
else
    PROFILE="${HOME}/.zprofile"
fi
if [ -n "$PROFILE" ] && ! grep -q 'openjdk@21' "$PROFILE" 2>/dev/null; then
    {
        echo ""
        echo "# idol-docker-setup Java 21"
        echo "export PATH=\"$(brew --prefix openjdk@21)/bin:\$PATH\""
        echo "export JAVA_HOME=\"$(brew --prefix openjdk@21)\""
    } >> "$PROFILE"
    ok "Wrote JAVA_HOME to $PROFILE"
fi

if [ "$WITH_OPTIONAL" -eq 1 ]; then
    info "Installing optional tools: helm kubectl minikube ghostscript..."
    brew install helm kubectl minikube ghostscript || true
fi

echo ""
verify || true
echo ""
ok "macOS prerequisites installed."
echo -e "${YELLOW}Apple silicon:${NC} IDOL images are typically linux/amd64 — enable Rosetta in Docker Desktop"
echo -e "                or pull with: docker pull --platform linux/amd64 <image>"
echo ""
echo -e "Next:"
echo -e "  ${CYAN}export IDOL_BASE_PATH=/path/to/idol-docker-setup${NC}"
echo -e "  ${CYAN}./utilities/ui-config/deploy-setup-manager-ui.sh --deploy${NC}"
echo -e "  ${CYAN}./prepare-env.sh --setup-prerequisites${NC}"
echo -e "  ${CYAN}./init-setup.sh${NC}"
