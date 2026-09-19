#!/usr/bin/env bash
# =============================================================================
# module/os-compat.sh
# Host OS detection + portable helpers for Ubuntu/Linux and macOS.
#
# Sourced by host scripts (and injected into other .sh files). Safe to source
# more than once. Does not require bash 4+ so it works with macOS /bin/bash 3.2.
#
# Exports:
#   IDOL_HOST_OS      ubuntu | debian | linux | macos | unknown
#   IDOL_OS_FAMILY    linux | macos | unknown
#   IDOL_OS_PRETTY    human-readable name
#   IDOL_PKG_MGR      apt | brew | none
#   IDOL_ARCH         uname -m (x86_64, arm64, aarch64, ...)
# =============================================================================

# Idempotent
if [ -n "${IDOL_OS_COMPAT_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
IDOL_OS_COMPAT_LOADED=1

# -----------------------------------------------------------------------------
# Detection
# -----------------------------------------------------------------------------
idol_detect_host_os() {
    local uname_s
    uname_s="$(uname -s 2>/dev/null || echo unknown)"
    IDOL_ARCH="$(uname -m 2>/dev/null || echo unknown)"
    IDOL_HOST_OS="unknown"
    IDOL_OS_FAMILY="unknown"
    IDOL_OS_PRETTY="$uname_s"
    IDOL_PKG_MGR="none"

    case "$uname_s" in
        Darwin)
            IDOL_HOST_OS="macos"
            IDOL_OS_FAMILY="macos"
            IDOL_PKG_MGR="brew"
            if command -v sw_vers >/dev/null 2>&1; then
                IDOL_OS_PRETTY="macOS $(sw_vers -productVersion 2>/dev/null)"
            else
                IDOL_OS_PRETTY="macOS"
            fi
            ;;
        Linux)
            IDOL_OS_FAMILY="linux"
            IDOL_HOST_OS="linux"
            IDOL_PKG_MGR="apt"
            if [ -f /etc/os-release ]; then
                # shellcheck disable=SC1091
                . /etc/os-release
                IDOL_OS_PRETTY="${PRETTY_NAME:-Linux}"
                case "${ID:-}" in
                    ubuntu) IDOL_HOST_OS="ubuntu" ;;
                    debian) IDOL_HOST_OS="debian" ;;
                    *)      IDOL_HOST_OS="linux" ;;
                esac
            elif command -v lsb_release >/dev/null 2>&1; then
                IDOL_OS_PRETTY="$(lsb_release -ds 2>/dev/null | tr -d '"')"
                case "$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')" in
                    ubuntu) IDOL_HOST_OS="ubuntu" ;;
                    debian) IDOL_HOST_OS="debian" ;;
                esac
            fi
            if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
                IDOL_PKG_MGR="apt"
            elif command -v brew >/dev/null 2>&1; then
                IDOL_PKG_MGR="brew"
            else
                IDOL_PKG_MGR="none"
            fi
            ;;
        *)
            IDOL_HOST_OS="unknown"
            IDOL_OS_FAMILY="unknown"
            IDOL_OS_PRETTY="$uname_s"
            ;;
    esac

    export IDOL_HOST_OS IDOL_OS_FAMILY IDOL_OS_PRETTY IDOL_PKG_MGR IDOL_ARCH
}

idol_detect_host_os

idol_is_macos() { [ "${IDOL_OS_FAMILY}" = "macos" ]; }
idol_is_linux() { [ "${IDOL_OS_FAMILY}" = "linux" ]; }
idol_is_ubuntu() { [ "${IDOL_HOST_OS}" = "ubuntu" ] || [ "${IDOL_HOST_OS}" = "debian" ]; }

idol_os_banner() {
    printf '[OS] Detected host: %s (%s / %s, pkg=%s)\n' \
        "${IDOL_OS_PRETTY}" "${IDOL_HOST_OS}" "${IDOL_ARCH}" "${IDOL_PKG_MGR}"
}

# -----------------------------------------------------------------------------
# String / path helpers (bash 3.2 safe)
# -----------------------------------------------------------------------------
idol_to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

idol_realpath() {
    local target="${1:-.}"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$target" 2>/dev/null && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target" 2>/dev/null && return 0
    fi
    # Fallback: resolve relative path from CWD
    if [ -d "$target" ]; then
        (cd "$target" 2>/dev/null && pwd)
    elif [ -e "$target" ]; then
        local dir base
        dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd)"
        base="$(basename "$target")"
        printf '%s/%s\n' "$dir" "$base"
    else
        printf '%s\n' "$target"
        return 1
    fi
}

idol_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        echo "sha256-unavailable"
        return 1
    fi
}

idol_stat_owner() {
    local path="$1"
    if stat -c '%U:%G' "$path" >/dev/null 2>&1; then
        stat -c '%U:%G' "$path"
    else
        # macOS / BSD
        printf '%s:%s\n' "$(stat -f '%Su' "$path" 2>/dev/null)" "$(stat -f '%Sg' "$path" 2>/dev/null)"
    fi
}

idol_nproc() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif [ "$IDOL_OS_FAMILY" = "macos" ]; then
        sysctl -n hw.ncpu 2>/dev/null || echo 1
    else
        getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
    fi
}

idol_mem_info() {
    if command -v free >/dev/null 2>&1; then
        free -h | grep "^Mem:" || free -h
    elif [ "$IDOL_OS_FAMILY" = "macos" ]; then
        local bytes gb
        bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
        if command -v awk >/dev/null 2>&1; then
            gb="$(awk -v b="$bytes" 'BEGIN { printf "%.1f" , b/1024/1024/1024 }')"
        else
            gb="$bytes"
        fi
        printf 'Mem: %s GB (hw.memsize)\n' "$gb"
        vm_stat 2>/dev/null | head -n 8 || true
    else
        echo "memory info unavailable"
    fi
}

idol_host_ip() {
    local ip=""
    if command -v hostname >/dev/null 2>&1; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    if [ -z "$ip" ] && [ "$IDOL_OS_FAMILY" = "macos" ]; then
        ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
        [ -z "$ip" ] && ip="$(ipconfig getifaddr en1 2>/dev/null || true)"
        if [ -z "$ip" ]; then
            ip="$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')"
        fi
    fi
    if [ -z "$ip" ]; then
        ip="$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')"
    fi
    printf '%s\n' "${ip:-127.0.0.1}"
}

# Portable in-place sed. First argument is the sed program; remaining are files.
# Extra -e / -E flags may be passed before the program if they start with '-'.
idol_sed_inplace() {
    local sed_args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -e|-E|-r)
                sed_args+=("$1")
                shift
                if [ $# -gt 0 ]; then
                    sed_args+=("$1")
                    shift
                fi
                ;;
            *)
                break
                ;;
        esac
    done
    if [ $# -lt 2 ]; then
        echo "idol_sed_inplace: usage: idol_sed_inplace [-E] 'expr' file [file...]" >&2
        return 1
    fi
    local expr="$1"
    shift
    local f tmp
    for f in "$@"; do
        [ -f "$f" ] || continue
        tmp="${f}.idolsed.$$"
        if sed "${sed_args[@]}" "$expr" "$f" > "$tmp"; then
            mv "$tmp" "$f"
        else
            rm -f "$tmp"
            return 1
        fi
    done
}

# -----------------------------------------------------------------------------
# Package / service helpers
# -----------------------------------------------------------------------------
idol_ensure_homebrew() {
    if [ "$IDOL_OS_FAMILY" != "macos" ]; then
        return 0
    fi
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi
    echo "[OS] Homebrew is required on macOS. Install from https://brew.sh" >&2
    echo "     /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" >&2
    return 1
}

# Translate a Debian package name to a Homebrew formula when they differ.
idol_brew_formula() {
    case "$1" in
        openjdk-21-jdk|openjdk-21-jre|openjdk-21*) echo "openjdk@21" ;;
        python3-pip) echo "python@3" ;;
        python3) echo "python@3" ;;
        ghostscript) echo "ghostscript" ;;
        containerd.io|docker-ce|docker-ce-cli|docker.io|docker-engine) echo "docker" ;;
        docker-compose-plugin|docker-compose) echo "docker-compose" ;;
        docker-buildx-plugin) echo "docker-buildx" ;;
        apt-transport-https|ca-certificates|gnupg-agent|lsb-release|software-properties-common) echo "" ;;
        *) echo "$1" ;;
    esac
}

idol_pkg_update() {
    case "$IDOL_PKG_MGR" in
        apt)
            sudo apt-get update -y
            ;;
        brew)
            idol_ensure_homebrew || return 1
            brew update || true
            ;;
        *)
            echo "[OS] No package manager detected; skipping update." >&2
            return 1
            ;;
    esac
}

idol_pkg_install() {
    local pkg brew_pkg
    if [ $# -eq 0 ]; then
        return 0
    fi
    case "$IDOL_PKG_MGR" in
        apt)
            sudo apt-get install -y "$@"
            ;;
        brew)
            idol_ensure_homebrew || return 1
            for pkg in "$@"; do
                brew_pkg="$(idol_brew_formula "$pkg")"
                [ -z "$brew_pkg" ] && continue
                if brew list --formula "$brew_pkg" >/dev/null 2>&1 || brew list --cask "$brew_pkg" >/dev/null 2>&1; then
                    continue
                fi
                brew install "$brew_pkg" || brew install --cask "$brew_pkg" || true
            done
            ;;
        *)
            echo "[OS] Cannot install packages ($*) — no package manager." >&2
            return 1
            ;;
    esac
}

idol_pkg_remove() {
    local pkg brew_pkg
    case "$IDOL_PKG_MGR" in
        apt)
            sudo apt-get remove -y "$@" >/dev/null 2>&1 || true
            ;;
        brew)
            for pkg in "$@"; do
                brew_pkg="$(idol_brew_formula "$pkg")"
                [ -z "$brew_pkg" ] && continue
                brew uninstall "$brew_pkg" >/dev/null 2>&1 || true
            done
            ;;
    esac
}

# systemctl-like wrappers. On macOS Docker Desktop is an app, not systemd.
idol_has_systemd() {
    [ "$IDOL_OS_FAMILY" = "linux" ] && command -v systemctl >/dev/null 2>&1
}

idol_service_enable() {
    local svc="$1"
    if idol_has_systemd; then
        sudo systemctl enable "$svc"
        return $?
    fi
    if [ "$IDOL_OS_FAMILY" = "macos" ]; then
        echo "[OS] macOS: '$svc' is not a systemd unit; skip enable."
        return 0
    fi
    return 1
}

idol_service_start() {
    local svc="$1"
    if idol_has_systemd; then
        sudo systemctl start "$svc"
        return $?
    fi
    if [ "$IDOL_OS_FAMILY" = "macos" ]; then
        case "$svc" in
            docker|docker.service|docker.socket)
                if command -v open >/dev/null 2>&1 && [ -d /Applications/Docker.app ]; then
                    open -a Docker
                    echo "[OS] Launching Docker Desktop..."
                    return 0
                fi
                if command -v brew >/dev/null 2>&1; then
                    brew services start docker >/dev/null 2>&1 || true
                fi
                return 0
                ;;
            *)
                echo "[OS] macOS: no systemd service named '$svc'."
                return 0
                ;;
        esac
    fi
    return 1
}

idol_service_stop() {
    local svc="$1"
    if idol_has_systemd; then
        sudo systemctl stop "$svc" 2>/dev/null || true
        return 0
    fi
    return 0
}

idol_service_status() {
    local svc="$1"
    if idol_has_systemd; then
        sudo systemctl status "$svc" --no-pager --lines="${2:-10}" || true
        return 0
    fi
    if [ "$IDOL_OS_FAMILY" = "macos" ] && [ "$svc" = "docker" -o "$svc" = "docker.service" ]; then
        if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
            echo "[OS] Docker Desktop / engine is running."
            docker version 2>/dev/null || true
        else
            echo "[OS] Docker does not appear to be running. Open Docker Desktop."
        fi
        return 0
    fi
    echo "[OS] Service status for '$svc' is not available on ${IDOL_HOST_OS}."
}

idol_service_restart() {
    local svc="$1"
    if idol_has_systemd; then
        sudo systemctl restart "$svc"
        return $?
    fi
    idol_service_stop "$svc"
    idol_service_start "$svc"
}

# -----------------------------------------------------------------------------
# Docker / Java installers
# -----------------------------------------------------------------------------
idol_docker_socket() {
    if [ -S /var/run/docker.sock ]; then
        echo /var/run/docker.sock
    elif [ -S "${HOME}/.docker/run/docker.sock" ]; then
        echo "${HOME}/.docker/run/docker.sock"
    else
        echo /var/run/docker.sock
    fi
}

idol_fix_docker_socket_perms() {
    local sock
    sock="$(idol_docker_socket)"
    if [ -S "$sock" ] && [ "$IDOL_OS_FAMILY" = "linux" ]; then
        sudo chmod 666 "$sock" 2>/dev/null || true
    fi
}

idol_install_docker() {
    echo "[OS] Installing Docker for ${IDOL_HOST_OS}..."
    if [ "$IDOL_OS_FAMILY" = "macos" ]; then
        idol_ensure_homebrew || return 1
        if [ -d /Applications/Docker.app ]; then
            echo "[OS] Docker Desktop already present."
        else
            echo "[OS] Installing Docker Desktop via Homebrew cask..."
            brew install --cask docker || {
                echo "[OS] brew cask docker failed. Install Docker Desktop from https://docs.docker.com/desktop/setup/install/mac-install/" >&2
                return 1
            }
        fi
        open -a Docker 2>/dev/null || true
        echo "[OS] Waiting for Docker Desktop engine..."
        local i
        i=0
        while [ "$i" -lt 60 ]; do
            if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
                echo "[OS] Docker engine is ready."
                return 0
            fi
            sleep 2
            i=$((i + 1))
        done
        echo "[OS] Docker Desktop was launched but the engine is not ready yet. Open Docker Desktop and re-run." >&2
        return 1
    fi

    # Ubuntu / Debian
    sudo apt-get update -y
    sudo apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common
    sudo mkdir -p /etc/apt/keyrings
    sudo chmod 755 /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    idol_fix_docker_socket_perms
    idol_service_stop docker.socket
    idol_service_stop docker.service
    if idol_service_start docker; then
        echo "[OS] Docker service started."
    else
        echo "[OS] Docker service failed to start." >&2
        return 1
    fi
    sudo groupadd -f docker 2>/dev/null || true
    local mainuser
    if [ -n "${SUDO_USER:-}" ]; then
        mainuser="$SUDO_USER"
    else
        mainuser="$(logname 2>/dev/null || echo "${USER:-root}")"
    fi
    sudo usermod -aG docker "$mainuser" 2>/dev/null || true
    echo "[OS] Docker installed for user $mainuser."
}

idol_install_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        echo "[OS] Docker Compose plugin already installed."
        return 0
    fi
    if [ "$IDOL_OS_FAMILY" = "macos" ]; then
        idol_ensure_homebrew || return 1
        brew install docker-compose || true
        if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
            return 0
        fi
    fi
    local ver
    ver="$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"
    [ -z "$ver" ] && ver="v2.29.7"
    sudo mkdir -p /usr/local/bin
    sudo curl -L "https://github.com/docker/compose/releases/download/${ver}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    if [ "$IDOL_OS_FAMILY" = "linux" ]; then
        sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true
    fi
    docker-compose --version >/dev/null 2>&1
}

idol_install_java21() {
    echo "[OS] Installing Java 21 on ${IDOL_HOST_OS}..."
    if [ "$IDOL_OS_FAMILY" = "macos" ]; then
        idol_ensure_homebrew || return 1
        brew install openjdk@21
        local brew_prefix
        brew_prefix="$(brew --prefix openjdk@21 2>/dev/null || true)"
        if [ -n "$brew_prefix" ]; then
            sudo ln -sfn "${brew_prefix}/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk-21.jdk 2>/dev/null || true
            export PATH="${brew_prefix}/bin:${PATH}"
            export JAVA_HOME="${brew_prefix}"
        fi
        return 0
    fi
    sudo apt-get update -y
    sudo apt-get install -y openjdk-21-jdk
}

idol_install_kubectl() {
    if [ "$IDOL_OS_FAMILY" = "macos" ]; then
        idol_ensure_homebrew || return 1
        brew install kubectl
        return $?
    fi
    local version
    version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
    local arch="amd64"
    case "$(uname -m)" in
        aarch64|arm64) arch="arm64" ;;
    esac
    curl -LO "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl"
    chmod +x kubectl
    sudo install -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
}

idol_install_minikube() {
    if [ "$IDOL_OS_FAMILY" = "macos" ]; then
        idol_ensure_homebrew || return 1
        brew install minikube
        return $?
    fi
    local arch="amd64"
    case "$(uname -m)" in
        aarch64|arm64) arch="arm64" ;;
    esac
    curl -LO "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}"
    sudo install minikube-linux-${arch} /usr/local/bin/minikube
    rm -f "minikube-linux-${arch}"
}

idol_install_hint() {
    local pkg="$1"
    if [ "$IDOL_OS_FAMILY" = "macos" ]; then
        printf 'macOS: brew install %s\n' "$(idol_brew_formula "$pkg")"
    else
        printf 'Ubuntu/Debian: sudo apt-get install -y %s\n' "$pkg"
    fi
}

# Aliases used by older scripts
sed_inplace() { idol_sed_inplace "$@"; }
pkg_install() { idol_pkg_install "$@"; }
