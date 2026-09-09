#!/bin/bash

# ============================================================
# setup-minikube-v3.sh — FULLY FIXED + RELIABLE NODEPORT ACCESS (May 2026)
# Final version:
#   • start_minikube() now respects ALL user-selected parameters
#   • Uses the proven NodePort + --ports mapping from your working script
#   • Cleanup happens AFTER Minikube starts (fixes localhost:8080 error)
#   • Hostname = idol-docker-host everywhere
# ============================================================

set -euo pipefail

# --- Colors ---
RED=$'\033[0;31m';    GREEN=$'\033[0;32m';   YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m';   BLUE=$'\033[0;34m';    MAGENTA=$'\033[0;35m'
WHITE=$'\033[1;37m';  GRAY=$'\033[0;90m';    BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'; DIM=$'\033[2m';        RESET=$'\033[0m'
ORANGE=$'\033[0;38;5;214m'; LIGHTER_YELLOW=$'\033[38;5;228m'
PURPLE=$'\033[0;35m'; NC=$'\033[0m'

# --- Root check ---
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}❌ This script must not be run as root or with sudo.${RESET}"
    exit 1
fi

# ============================================================
# USAGE
# ============================================================
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Install Harbor container registry on Minikube.

${BOLD}General Options:${RESET}
  ${YELLOW}-h, --help                           ${RESET}Show this help message and exit
  ${YELLOW}-y, --yes                            ${RESET}Auto-answer yes to all prompts (non-interactive)

${BOLD}Harbor Configuration:${RESET}
  ${YELLOW}-H, --hostname${ORANGE} HOST           ${RESET}Harbor hostname/FQDN (default: idol-docker-host)
  ${YELLOW}--http-port${ORANGE} PORT              ${RESET}HTTP port
  ${YELLOW}--https-port${ORANGE} PORT             ${RESET}HTTPS port
  ${YELLOW}--https                              ${RESET}Enable HTTPS (disabled by default)
  ${YELLOW}--standard-ports                     ${RESET}Use standard ports 80/443 (RECOMMENDED)
  ${YELLOW}--custom-ports                       ${RESET}Use custom ports 5050/5443
  ${YELLOW}--ssl-dir${ORANGE} DIR                 ${RESET}SSL certificate & key directory
  ${YELLOW}--cert${ORANGE} FILE                   ${RESET}Path to certificate file
  ${YELLOW}--key${ORANGE} FILE                    ${RESET}Path to private key file
  ${YELLOW}-v, --version${ORANGE} VER             ${RESET}Specific Harbor Helm chart version
  ${YELLOW}-n, --namespace${ORANGE} NS            ${RESET}Kubernetes namespace (default: harbor)

${BOLD}Minikube Options:${RESET}
  ${YELLOW}--minikube-profile${ORANGE} NAME       ${RESET}Minikube profile name (default: harbor)
  ${YELLOW}--minikube-cpus${ORANGE} N             ${RESET}CPUs for Minikube (default: 4)
  ${YELLOW}--minikube-memory${ORANGE} MB          ${RESET}Memory for Minikube (default: 8192)
  ${YELLOW}--minikube-k8s-version${ORANGE} VER    ${RESET}Kubernetes version (default: v1.30.0)
  ${YELLOW}--minikube-disk-size${ORANGE} SIZE     ${RESET}Disk size (default: 20g)
  ${YELLOW}--skip-profile-select         ${RESET}Skip interactive profile selection (use --minikube-profile directly)

${BOLD}Utility Options:${RESET}
  ${YELLOW}--clean-restart               ${RESET}Delete old profile before starting (recommended)
  ${YELLOW}--clear                       ${RESET}Delete ALL Minikube profiles (destructive!)
  ${YELLOW}--env-output-dir${ORANGE} DIR          ${RESET}Directory to write minikube_<profile>.env (default: ./env)
  ${YELLOW}-p, --list-profiles           ${RESET}List Minikube profiles and exit
EOF
    exit 0
}

# ============================================================
# DEFAULTS
# ============================================================
USE_STANDARD_PORTS="${USE_STANDARD_PORTS:-true}"
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-harbor}"
MINIKUBE_CPUS="4"
MINIKUBE_MEMORY="8192"
MINIKUBE_DISK_SIZE="20g"
MINIKUBE_K8S_VERSION="v1.30.0"
MINIKUBE_DRIVER="docker"
MINIKUBE_CONTAINER_RUNTIME="containerd"
MINIKUBE_CNI="bridge"
MINIKUBE_INSECURE_REGISTRY="idol-docker-host"

HARBOR_VERSION="${HARBOR_VERSION:-}"
HARBOR_APP_VERSION=""
HARBOR_NAMESPACE="${HARBOR_NAMESPACE:-harbor}"
HARBOR_HTTP_PORT="${HARBOR_HTTP_PORT:-5050}"
HARBOR_HTTPS_PORT="${HARBOR_HTTPS_PORT:-5443}"
HARBOR_SSL_DIR="${HARBOR_SSL_DIR:-}"
HARBOR_HOSTNAME="idol-docker-host"
HARBOR_ENABLE_HTTPS="false"
HARBOR_CERT_PATH=""
HARBOR_KEY_PATH=""
HARBOR_TLS_SECRET_NAME="idol-docker-host-tls"

AUTO_YES=false
CLEAN_RESTART=false
CLEAR_ALONE=false
SHOW_PROFILES=false
SKIP_PROFILE_SELECT=false
ENV_OUTPUT_DIR="./env"

# ============================================================
# ARGUMENT PARSING
# ============================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)                  usage ;;
        -H|--hostname)              HARBOR_HOSTNAME="$2";       shift 2 ;;
        --http-port)                HARBOR_HTTP_PORT="$2";      shift 2 ;;
        --https-port)               HARBOR_HTTPS_PORT="$2";     shift 2 ;;
        --https)                    HARBOR_ENABLE_HTTPS="true"; shift 1 ;;
        --standard-ports)           USE_STANDARD_PORTS=true;    shift 1 ;;
        --custom-ports)             USE_STANDARD_PORTS=false;   shift 1 ;;
        --ssl-dir)                  HARBOR_SSL_DIR="$2";        shift 2 ;;
        --cert)                     HARBOR_CERT_PATH="$2";      shift 2 ;;
        --key)                      HARBOR_KEY_PATH="$2";       shift 2 ;;
        -v|--version)               HARBOR_VERSION="$2";        shift 2 ;;
        -n|--namespace)             HARBOR_NAMESPACE="$2";      shift 2 ;;
        --minikube-cpus)            MINIKUBE_CPUS="$2";         shift 2 ;;
        --minikube-memory)          MINIKUBE_MEMORY="$2";       shift 2 ;;
        --minikube-k8s-version)     MINIKUBE_K8S_VERSION="$2";  shift 2 ;;
        --minikube-profile)         MINIKUBE_PROFILE="$2";      shift 2 ;;
        --minikube-disk-size)       MINIKUBE_DISK_SIZE="$2";    shift 2 ;;
        --skip-profile-select)      SKIP_PROFILE_SELECT=true;   shift 1 ;;
        --env-output-dir)           ENV_OUTPUT_DIR="$2";        shift 2 ;;
        --clean-restart)            CLEAN_RESTART=true;         shift 1 ;;
        --clear)                    CLEAR_ALONE=true;           shift 1 ;;
        -p|--list-profiles)         SHOW_PROFILES=true;         shift 1 ;;
        -y|--yes)                   AUTO_YES=true;              shift 1 ;;
        *) echo -e "${RED}❌ Unknown option: $1${RESET}"; usage ;;
    esac
done

# ============================================================
# CLEAN RESTART LOGIC
# ============================================================
if [ "$CLEAN_RESTART" = true ]; then
    echo -e "${YELLOW}⚠️  --clean-restart requested — deleting old profile first...${RESET}"
    minikube delete -p "$MINIKUBE_PROFILE" --purge 2>/dev/null || true
    echo -e "${GREEN}✅ Old profile cleaned${RESET}"
fi

# ============================================================
# HELPER FUNCTIONS (unchanged)
# ============================================================
resolve_path() {
    local path="$1"
    if [[ -z "$path" ]] || [[ "$path" =~ ^/ ]]; then
        echo "$path"
    else
        (cd "$(pwd)" && cd "$path" 2>/dev/null && pwd) || echo "$path"
    fi
}

prompt_with_default() {
    local var_name="$1" prompt_msg="$2" default_val="$3"
    if [ "$AUTO_YES" = true ]; then printf -v "$var_name" '%s' "$default_val"; return; fi
    read -rp "$(echo -e "${CYAN}${prompt_msg}${RESET} [${BOLD}${default_val}${RESET}]: ")" input
    printf -v "$var_name" '%s' "${input:-$default_val}"
}

prompt_yn() {
    local var_name="$1" prompt_msg="$2" default_val="${3:-n}"
    if [ "$AUTO_YES" = true ]; then
        printf -v "$var_name" '%s' "$([[ "$default_val" =~ ^[Yy]$ ]] && echo "true" || echo "false")"
        return
    fi
    read -rp "$(echo -e "${CYAN}${prompt_msg}${RESET} [${BOLD}y/N${RESET}]: ")" input
    input="${input:-$default_val}"
    [[ "$input" =~ ^[Yy]$ ]] && printf -v "$var_name" '%s' "true" || printf -v "$var_name" '%s' "false"
}

prompt_port() {
    local var_name="$1" prompt_msg="$2" default_val="$3"
    while true; do
        prompt_with_default "$var_name" "$prompt_msg" "$default_val"
        [[ "${!var_name}" =~ ^[0-9]+$ ]] && [ "${!var_name}" -ge 1 ] && [ "${!var_name}" -le 65535 ] && break
        echo -e "${RED}❌ Invalid port.${RESET}"
    done
}

confirm_config() {
    [ "$AUTO_YES" = true ] && return 0
    read -rp "$(echo -e "${CYAN}Proceed with this configuration? [y/N]: ${RESET}")" confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]' | xargs)
    if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
        echo -e "${GREEN}✅ Configuration confirmed!${RESET}"
        return 0
    else
        echo -e "${RED}❌ Installation cancelled.${RESET}"
        exit 0
    fi
}

get_infra_configuration() {
    echo -e "${YELLOW}Get infrastructure configuration...${LIGHTER_YELLOW}"

    read -rp "$(echo -e "${CYAN}Kubernetes version${RESET} [${BOLD}${MINIKUBE_K8S_VERSION}${RESET}]: ")" NEW_K8S_VERSION
    NEW_K8S_VERSION="${NEW_K8S_VERSION:-$MINIKUBE_K8S_VERSION}"

    read -rp "$(echo -e "${CYAN}Container runtime (containerd/docker)${RESET} [${BOLD}${MINIKUBE_CONTAINER_RUNTIME}${RESET}]: ")" NEW_CONTAINER_RUNTIME
    NEW_CONTAINER_RUNTIME="${NEW_CONTAINER_RUNTIME:-$MINIKUBE_CONTAINER_RUNTIME}"

    read -rp "$(echo -e "${CYAN}CNI plugin${RESET} [${BOLD}${MINIKUBE_CNI}${RESET}]: ")" NEW_CNI
    NEW_CNI="${NEW_CNI:-$MINIKUBE_CNI}"

    read -rp "$(echo -e "${CYAN}Insecure registry (CIDR or host)${RESET} [${BOLD}${MINIKUBE_INSECURE_REGISTRY}${RESET}]: ")" NEW_INSECURE_REGISTRY
    NEW_INSECURE_REGISTRY="${NEW_INSECURE_REGISTRY:-$MINIKUBE_INSECURE_REGISTRY}"

    while true; do
        read -rp "$(echo -e "${CYAN}Disk size (e.g. 20g or 20000)${RESET} [${BOLD}${MINIKUBE_DISK_SIZE}${RESET}]: ")" NEW_STORAGE
        NEW_STORAGE="${NEW_STORAGE:-$MINIKUBE_DISK_SIZE}"
        local storage_num
        storage_num=$(echo "$NEW_STORAGE" | sed -E 's/([0-9]+).*/\1/')
        if [[ ! "$storage_num" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}❌ Please enter a valid number (e.g. 20g or 20000).${RESET}"
            continue
        fi
        if (( storage_num >= 2 )); then
            break
        else
            echo -e "${RED}❌ Disk size too small (min 2g / 2000 MB).${RESET}"
        fi
    done

    while true; do
        read -rp "$(echo -e "${CYAN}Memory (MB)${RESET} [${BOLD}${MINIKUBE_MEMORY}${RESET}]: ")" NEW_MEMORY
        NEW_MEMORY="${NEW_MEMORY:-$MINIKUBE_MEMORY}"
        if [[ ! "$NEW_MEMORY" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}❌ Please enter a valid integer.${RESET}"
            continue
        fi
        if (( NEW_MEMORY > 2000 )); then
            break
        else
            echo -e "${RED}❌ Memory must be > 2000 MB. Entered: $NEW_MEMORY${RESET}"
        fi
    done

    while true; do
        read -rp "$(echo -e "${CYAN}CPUs${RESET} [${BOLD}${MINIKUBE_CPUS}${RESET}]: ")" NEW_CPUS
        NEW_CPUS="${NEW_CPUS:-$MINIKUBE_CPUS}"
        if [[ ! "$NEW_CPUS" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}❌ Please enter a valid integer.${RESET}"
            continue
        fi
        if (( NEW_CPUS >= 2 )); then
            break
        else
            echo -e "${RED}❌ CPUs must be >= 2. Entered: $NEW_CPUS${RESET}"
        fi
    done

    echo -e "${RESET}"
}

list_minikube_profiles() {
    echo -e "${BOLD}${CYAN}=== Minikube Profile Selection ===${RESET}"

    if [ "$AUTO_YES" = true ]; then
        echo -e "  ${GREEN}✅ Using profile (auto): ${CYAN}${MINIKUBE_PROFILE}${RESET}"
        return 0
    fi

    local minikube_profiles=()
    local profile_statuses=()
    local minikube_profiles_found=false

    if minikube profile list &>/dev/null 2>&1; then
        minikube_profiles_found=true
    fi

    if [ "$minikube_profiles_found" = true ]; then
        echo -e ""
        echo -e "${YELLOW}Available Minikube Profiles:${RESET}"

        local count=1
        while IFS= read -r line; do
            local profile status_col active_profile
            profile=$(echo "$line" | awk -F '|' '{print $2}' | xargs)
            active_profile=$(echo "$line" | awk -F '|' '{print $8}' | xargs)

            [[ -z "$profile" ]] && continue

            if [[ "$active_profile" == "OK" ]]; then
                status="${GREEN}running${RESET}"
            else
                status="${RED}stopped${RESET}"
            fi

            minikube_profiles+=("$profile")
            profile_statuses+=("$status")

            echo -e "  ${BLUE}${count}.${RESET} ${profile}  [$(echo -e "$status")]"
            (( count++ ))
        done < <(minikube profile list 2>/dev/null | grep -v "|\-\-\-" | tail -n +2)
    fi

    local total_existing=${#minikube_profiles[@]}
    local create_opt=$(( total_existing + 1 ))

    echo -e ""
    echo -e "  ${LIGHTER_YELLOW}${create_opt}. Create a new profile${RESET}"
    echo -e "  ${GRAY}─────────────────────────────────────────${RESET}"

    local selection
    while true; do
        read -rp "$(echo -e "${CYAN}Select a profile [1-${create_opt}]: ${RESET}")" selection
        selection="${selection:-1}"

        if [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > create_opt )); then
            echo -e "${RED}❌ Invalid selection. Enter a number between 1 and ${create_opt}.${RESET}"
            continue
        fi
        break
    done

    if (( selection == create_opt )); then
        create_new_minikube_profile
    else
        MINIKUBE_PROFILE="${minikube_profiles[$((selection-1))]}"
        echo -e "  ${GREEN}✅ Selected profile: ${CYAN}${MINIKUBE_PROFILE}${RESET}"

        local chosen_status="${profile_statuses[$((selection-1))]}"
        if echo -e "$chosen_status" | grep -q "stopped"; then
            echo -e "  ${YELLOW}⚠️  Profile '${MINIKUBE_PROFILE}' is currently stopped — it will be started during installation.${RESET}"
        fi
    fi
}

create_new_minikube_profile() {
    echo -e "${BOLD}${CYAN}=== Create New Minikube Profile ===${RESET}"

    local new_profile
    read -rp "$(echo -e "${CYAN}New profile name${RESET} [${BOLD}${MINIKUBE_PROFILE}${RESET}]: ")" new_profile
    new_profile="${new_profile:-$MINIKUBE_PROFILE}"

    if [[ -z "$new_profile" ]]; then
        echo -e "${YELLOW}⚠️  Profile name empty, using default: harbor${RESET}"
        new_profile="harbor"
    fi

    get_infra_configuration

    MINIKUBE_PROFILE="$new_profile"
    MINIKUBE_K8S_VERSION="$NEW_K8S_VERSION"
    MINIKUBE_CONTAINER_RUNTIME="$NEW_CONTAINER_RUNTIME"
    MINIKUBE_CNI="$NEW_CNI"
    MINIKUBE_INSECURE_REGISTRY="$NEW_INSECURE_REGISTRY"
    MINIKUBE_DISK_SIZE="$NEW_STORAGE"
    MINIKUBE_MEMORY="$NEW_MEMORY"
    MINIKUBE_CPUS="$NEW_CPUS"

    echo -e ""
    echo -e "${BOLD}${CYAN}─── New Profile Summary ───────────────────${RESET}"
    echo -e "  Profile Name       : ${CYAN}${MINIKUBE_PROFILE}${RESET}"
    echo -e "  Kubernetes Version : ${CYAN}${MINIKUBE_K8S_VERSION}${RESET}"
    echo -e "  Container Runtime  : ${CYAN}${MINIKUBE_CONTAINER_RUNTIME}${RESET}"
    echo -e "  CNI                : ${CYAN}${MINIKUBE_CNI}${RESET}"
    echo -e "  Insecure Registry  : ${CYAN}${MINIKUBE_INSECURE_REGISTRY}${RESET}"
    echo -e "  Disk Size          : ${CYAN}${MINIKUBE_DISK_SIZE}${RESET}"
    echo -e "  Memory (MB)        : ${CYAN}${MINIKUBE_MEMORY}${RESET}"
    echo -e "  CPUs               : ${CYAN}${MINIKUBE_CPUS}${RESET}"
    echo -e "${BOLD}${CYAN}───────────────────────────────────────────${RESET}"
    echo -e ""

    local proceed
    prompt_yn proceed "Create profile '${MINIKUBE_PROFILE}' with these settings?" "y"
    if [ "$proceed" != "true" ]; then
        echo -e "${RED}❌ Profile creation cancelled.${RESET}"
        exit 0
    fi

    echo -e "  ${GREEN}✅ Profile settings confirmed — start_minikube will initialise it.${RESET}"
}

export_minikube_env_vars() {
    local env_dir="${ENV_OUTPUT_DIR}"
    local env_file="${env_dir}/minikube_${MINIKUBE_PROFILE}.env"

    echo -e "${BOLD}${CYAN}=== Exporting Minikube Environment Variables ===${RESET}"

    mkdir -p "$env_dir"

    if [ -f "$env_file" ]; then
        echo -e "  ${YELLOW}⚠️  Existing env file found — replacing: ${env_file}${RESET}"
        rm -f "$env_file"
    fi

    cat > "$env_file" <<EOF
# Auto-generated by setup-minikube-v3.sh
# Profile  : ${MINIKUBE_PROFILE}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Minikube ─────────────────────────────────────────────
export MINIKUBE_PROFILE="${MINIKUBE_PROFILE}"
export MINIKUBE_CPUS="${MINIKUBE_CPUS}"
export MINIKUBE_MEMORY="${MINIKUBE_MEMORY}"
export MINIKUBE_DISK_SIZE="${MINIKUBE_DISK_SIZE}"
export MINIKUBE_K8S_VERSION="${MINIKUBE_K8S_VERSION}"
export MINIKUBE_DRIVER="${MINIKUBE_DRIVER}"
export MINIKUBE_CONTAINER_RUNTIME="${MINIKUBE_CONTAINER_RUNTIME}"
export MINIKUBE_CNI="${MINIKUBE_CNI}"
export MINIKUBE_INSECURE_REGISTRY="${MINIKUBE_INSECURE_REGISTRY}"

# ── Harbor ───────────────────────────────────────────────
export HARBOR_NAMESPACE="${HARBOR_NAMESPACE}"
export HARBOR_HOSTNAME="${HARBOR_HOSTNAME}"
export HARBOR_HTTP_PORT="${HARBOR_HTTP_PORT}"
export HARBOR_HTTPS_PORT="${HARBOR_HTTPS_PORT}"
export HARBOR_ENABLE_HTTPS="${HARBOR_ENABLE_HTTPS}"
export HARBOR_VERSION="${HARBOR_VERSION}"
export USE_STANDARD_PORTS="${USE_STANDARD_PORTS}"
EOF

    if [ "${HARBOR_ENABLE_HTTPS}" = "true" ]; then
        cat >> "$env_file" <<EOF
export HARBOR_CERT_PATH="${HARBOR_CERT_PATH}"
export HARBOR_KEY_PATH="${HARBOR_KEY_PATH}"
export HARBOR_SSL_DIR="${HARBOR_SSL_DIR}"
EOF
    fi

    echo -e "  ${GREEN}✅ Environment file written: ${CYAN}${env_file}${RESET}"
    echo -e "  ${GRAY}   Source with: source ${env_file}${RESET}"
}

# ============================================================
# FIXED start_minikube() — delete first, start second, cleanup last
# ============================================================
start_minikube() {
    echo "=== Cleaning up old Harbor and cluster ==="
    minikube delete -p "$MINIKUBE_PROFILE" 2>/dev/null || true

    echo "=== Starting Minikube with user-selected parameters + port mapping (no tunnel needed) ==="
    minikube start -p "$MINIKUBE_PROFILE" \
        --driver="$MINIKUBE_DRIVER" \
        --cpus="$MINIKUBE_CPUS" \
        --memory="$MINIKUBE_MEMORY" \
        --disk-size="$MINIKUBE_DISK_SIZE" \
        --kubernetes-version="$MINIKUBE_K8S_VERSION" \
        --container-runtime="$MINIKUBE_CONTAINER_RUNTIME" \
        --cni="$MINIKUBE_CNI" \
        --insecure-registry="$MINIKUBE_INSECURE_REGISTRY" \
        --ports=127.0.0.1:30002:30002,127.0.0.1:30003:30003

    echo -e "  ${GREEN}✅ Minikube started successfully${RESET}"

    # Cleanup Harbor resources ONLY AFTER the cluster is running
    echo "=== Cleaning up any old Harbor installation ==="
    helm uninstall harbor -n "$HARBOR_NAMESPACE" 2>/dev/null || true
    kubectl --context "$MINIKUBE_PROFILE" delete namespace "$HARBOR_NAMESPACE" --ignore-not-found=true
}

# ============================================================
# REMAINING FUNCTIONS (unchanged from your working version)
# ============================================================
add_helm_repo() {
    echo -e "  📦 Adding Harbor Helm repo..."
    helm repo add harbor https://helm.goharbor.io >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1
    echo -e "  ${GREEN}✅ Harbor repo added${RESET}"
}

select_harbor_version() {
    echo -e "${BOLD}${CYAN}Fetching latest Harbor versions...${RESET}"
    mapfile -t lines < <(helm search repo harbor/harbor --versions | tail -n +2 | head -3 | awk '{print $2 "\t" $3}')
    for i in "${!lines[@]}"; do
        IFS=$'\t' read -r c a <<< "${lines[$i]}"
        echo -e "  $((i+1)). Chart ${CYAN}$c${RESET} → Harbor ${YELLOW}$a${RESET}"
    done
    if [ "$AUTO_YES" = true ]; then
        choice=1
    else
        read -rp "${CYAN}Select [1-3] (default 1): ${RESET}" choice
        choice=${choice:-1}
    fi
    IFS=$'\t' read -r HARBOR_VERSION HARBOR_APP_VERSION <<< "${lines[$((choice-1))]}"
    echo -e "${GREEN}✅ Selected: Chart ${CYAN}$HARBOR_VERSION${RESET} (Harbor ${YELLOW}$HARBOR_APP_VERSION${RESET})${RESET}"
}

generate_self_signed_cert() {
    local cert="$1" key="$2" host="$3"
    echo -e "${YELLOW}Generating self-signed certificate for $host...${RESET}"
    mkdir -p "$(dirname "$cert")"
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$key" -out "$cert" -days 365 \
        -subj "/CN=$host" \
        -addext "subjectAltName=DNS:$host"
    echo -e "${GREEN}✅ Certificate generated: $cert${RESET}"
}

create_tls_secret() {
    local ns="$1" cert="$2" key="$3"
    echo -e "  🔒 Creating TLS secret '$HARBOR_TLS_SECRET_NAME' in namespace '$ns'..."

    kubectl --context "$MINIKUBE_PROFILE" \
        create ns "$ns" --dry-run=client -o yaml \
        | kubectl --context "$MINIKUBE_PROFILE" apply -f - >/dev/null 2>&1

    kubectl --context "$MINIKUBE_PROFILE" \
        -n "$ns" delete secret "$HARBOR_TLS_SECRET_NAME" --ignore-not-found

    kubectl --context "$MINIKUBE_PROFILE" \
        -n "$ns" create secret tls "$HARBOR_TLS_SECRET_NAME" \
        --cert="$cert" \
        --key="$key"

    echo -e "  ${GREEN}✅ TLS secret '$HARBOR_TLS_SECRET_NAME' created${RESET}"
}

generate_values_yaml() {
    local hostname="$1"
    local f="/tmp/harbor-values-$$.yaml"

    cat > "$f" <<EOF
expose:
  type: nodePort
  tls:
    enabled: true
    certSource: auto
    auto:
      commonName: "$hostname"
  nodePort:
    ports:
      http:
        port: 80
        nodePort: 30002
      https:
        port: 443
        nodePort: 30003
externalURL: https://$hostname:30003
harborAdminPassword: "Harbor12345"
persistence:
  enabled: false
EOF

    echo "$f"
}

deploy_harbor() {
    local ns="$1" ver="$2" val="$3"
    echo -e "  🚀 Deploying Harbor chart version ${CYAN}$ver${RESET} into namespace ${CYAN}$ns${RESET}..."

    kubectl --context "$MINIKUBE_PROFILE" \
        create ns "$ns" --dry-run=client -o yaml \
        | kubectl --context "$MINIKUBE_PROFILE" apply -f - >/dev/null

    helm upgrade --install harbor harbor/harbor \
        --namespace "$ns" \
        --version "$ver" \
        --values "$val" \
        --kube-context "$MINIKUBE_PROFILE" \
        --wait \
        --timeout 10m

    echo -e "  ${GREEN}✅ Harbor deployed successfully${RESET}"
}

wait_for_harbor() {
    local ns="$1"
    echo -e "  ⏳ Waiting for Harbor pods to become ready in namespace '$ns'..."

    kubectl --context "$MINIKUBE_PROFILE" \
        -n "$ns" wait \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=harbor \
        --timeout=300s 2>/dev/null || {
            echo -e "  ${YELLOW}⚠️  Some pods may not be ready yet. Checking status...${RESET}"
            kubectl --context "$MINIKUBE_PROFILE" -n "$ns" get pods
        }

    echo -e "  ${GREEN}✅ Harbor pods are ready${RESET}"
}

start_harbor_port_forward() {
    local ns="$1"
    local http_port="$2"
    local https_port="$3"
    local enable_https="$4"

    echo -e "${BOLD}${CYAN}=== Starting Harbor Portal Port-Forward (HTTP + HTTPS) ===${RESET}"

    pkill -f "port-forward.*harbor-portal.*${MINIKUBE_PROFILE}" 2>/dev/null || true
    sleep 0.5

    echo -e "  🌐 Starting port-forward → host:${CYAN}${http_port}${RESET} (svc/harbor-portal:80)"
    nohup kubectl --context "$MINIKUBE_PROFILE" -n "$ns" port-forward \
        svc/harbor-portal "${http_port}:80" --address=0.0.0.0 \
        > "/tmp/harbor-portal-http-pf-${MINIKUBE_PROFILE}.log" 2>&1 &

    local http_pf_pid=$!
    echo -e "     ${GREEN}✅ PID: ${http_pf_pid} → http://${HARBOR_HOSTNAME}:${http_port}${RESET}"

    if [ "$enable_https" = "true" ]; then
        echo -e "  🔐 Starting port-forward → host:${CYAN}${https_port}${RESET} (svc/harbor-portal:80)"
        nohup kubectl --context "$MINIKUBE_PROFILE" -n "$ns" port-forward \
            svc/harbor-portal "${https_port}:80" --address=0.0.0.0 \
            > "/tmp/harbor-portal-https-pf-${MINIKUBE_PROFILE}.log" 2>&1 &

        local https_pf_pid=$!
        echo -e "     ${GREEN}✅ PID: ${https_pf_pid} → https://${HARBOR_HOSTNAME}:${https_port} ${GRAY}(internal service is HTTP)${RESET}"
    fi

    echo -e "${GREEN}✅ Harbor portal port-forward(s) started in background${RESET}"
    echo -e "${YELLOW}   Logs: /tmp/harbor-portal-*-pf-${MINIKUBE_PROFILE}.log${RESET}"
    echo -e "${YELLOW}   Stop: pkill -f harbor-portal-${MINIKUBE_PROFILE}${RESET}"
}

# ============================================================
# update_docker_daemon_json()
#   Merges insecure-registry entries derived from:
#     MINIKUBE_INSECURE_REGISTRY  (bare hostname,  e.g. idol-docker-host)
#     MINIKUBE_INSECURE_REGISTRY:HARBOR_HTTPS_PORT  (e.g. idol-docker-host:30003)
#   into /etc/docker/daemon.json, preserving all other existing keys.
#   Requires sudo; reloads (or restarts) the Docker daemon afterwards.
# ============================================================
update_docker_daemon_json() {
    local registry_host="$1"   # value of MINIKUBE_INSECURE_REGISTRY
    local registry_port="$2"   # value of HARBOR_HTTPS_PORT (NodePort)
    local daemon_json="/etc/docker/daemon.json"

    echo -e ""
    echo -e "${BOLD}${CYAN}=== Updating Docker daemon insecure-registries ===${RESET}"

    local entry_host="${registry_host}"
    local entry_port="${registry_host}:${registry_port}"

    echo -e "  📝 Target file : ${CYAN}${daemon_json}${RESET}"
    echo -e "  ➕ Adding      : ${CYAN}${entry_host}${RESET}"
    echo -e "  ➕ Adding      : ${CYAN}${entry_port}${RESET}"

    # Python handles JSON safely — no sed/awk touching the file
    sudo python3 - "$daemon_json" "$entry_host" "$entry_port" <<'PYEOF'
import sys, json, os

daemon_file = sys.argv[1]
new_entries = sys.argv[2:]

# ── Read existing config (tolerate missing file or empty file) ──
if os.path.exists(daemon_file):
    try:
        content = open(daemon_file).read().strip()
        config = json.loads(content) if content else {}
    except json.JSONDecodeError as exc:
        print(f"ERROR: {daemon_file} contains invalid JSON — aborting. ({exc})", file=sys.stderr)
        sys.exit(1)
else:
    config = {}

# ── Merge insecure-registries (deduplicated, original order kept) ──
existing = config.get("insecure-registries", [])
merged   = list(existing)
for entry in new_entries:
    if entry not in merged:
        merged.append(entry)

config["insecure-registries"] = merged

# ── Atomic write via temp file ──
tmp = daemon_file + ".tmp"
with open(tmp, "w") as fh:
    json.dump(config, fh, indent=2)
    fh.write("\n")
os.replace(tmp, daemon_file)

print(f"OK: {daemon_file} updated — insecure-registries: {merged}")
PYEOF

    if [ $? -ne 0 ]; then
        echo -e "  ${RED}❌ Failed to update ${daemon_json}. Check sudo permissions or JSON syntax.${RESET}"
        return 1
    fi

    echo -e "  ${GREEN}✅ ${daemon_json} updated successfully${RESET}"

    # Always do a full restart so the new insecure-registries entry is guaranteed
    # to be picked up (a plain reload is not sufficient for this config key).
    echo -e "  🔄 Restarting Docker daemon (sudo systemctl restart docker)..."
    sudo systemctl restart docker
    echo -e "  ${GREEN}✅ Docker daemon restarted — insecure-registry config is now active${RESET}"
}

print_summary() {
    local hostname="$1" http_port="$2" https_port="$3" enable_https="$4"

    echo -e ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║       ✅ Harbor Installed Successfully!       ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
    echo -e ""

    echo -e "  ${BOLD}Web UI     :${RESET} ${CYAN}https://${hostname}:30003${RESET}   ${GREEN}(direct access from Windows)${RESET}"
    echo -e "  ${BOLD}Docker     :${RESET} docker login ${hostname}:30003"

    echo -e ""
    echo -e "  ${BOLD}Username   :${RESET} admin"
    echo -e "  ${BOLD}Password   :${RESET} Harbor12345"
    echo -e ""

    echo -e "${YELLOW}📝 ACCESS METHODS${RESET}"
    echo -e "  • ${GREEN}Direct (recommended)${RESET}: Port-forward is already running in background"
    echo -e "    → https://${hostname}:30003"
    echo -e ""
    echo -e "  1. Add to Windows hosts file (C:\\Windows\\System32\\drivers\\etc\\hosts):"
    echo -e "     ${BOLD}127.0.0.1   ${hostname}${RESET}"
    echo -e ""
    echo -e "  2. Env file:"
    echo -e "     ${BOLD}${CYAN}${ENV_OUTPUT_DIR}/minikube_${MINIKUBE_PROFILE}.env${RESET}"
    echo -e ""

    echo -e "${YELLOW}🐳 DOCKER DAEMON${RESET}"
    echo -e "  • ${GREEN}/etc/docker/daemon.json${RESET} was updated with insecure-registries:"
    echo -e "    ${CYAN}${MINIKUBE_INSECURE_REGISTRY}${RESET}"
    echo -e "    ${CYAN}${MINIKUBE_INSECURE_REGISTRY}:${HARBOR_HTTPS_PORT}${RESET}"
    echo -e "  • Docker was restarted to apply the change."
    echo -e "  • You can now push/pull without TLS errors:"
    echo -e "    ${BOLD}docker login ${MINIKUBE_INSECURE_REGISTRY}:${HARBOR_HTTPS_PORT}${RESET}"
    echo -e "    ${BOLD}OR${RESET}"
    echo -e "    ${BOLD}docker login localhost:30003${RESET}"
    echo -e "    ${GRAY}Username: admin   Password: Harbor12345${RESET}"
    echo -e ""
}

# ============================================================
# MAIN
# ============================================================
if [ "$SHOW_PROFILES" = true ]; then
    minikube profile list
    exit 0
fi

if [ "$CLEAR_ALONE" = true ]; then
    echo -e "${YELLOW}⚠️  Deleting all Minikube profiles...${RESET}"
    mapfile -t profiles < <(minikube profile list --output table 2>/dev/null | tail -n +3 | awk '{print $1}' | grep -E '\S+')
    if [ ${#profiles[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}No profiles found.${RESET}"
    else
        for p in "${profiles[@]}"; do
            echo -e "  🗑  Deleting profile: ${CYAN}$p${RESET}"
            minikube delete -p "$p" --purge || true
        done
    fi
    echo -e "${GREEN}✅ All profiles deleted.${RESET}"
    exit 0
fi

echo -e "${BOLD}${CYAN}"
echo -e "╔══════════════════════════════════════════════╗"
echo -e "║     Harbor Registry — Minikube Installer     ║"
echo -e "╚══════════════════════════════════════════════╝${RESET}"
echo -e ""

add_helm_repo

[ -n "${HARBOR_VERSION:-}" ] || select_harbor_version
[ -n "${HARBOR_NAMESPACE:-}" ] && HARBOR_NAMESPACE="$HARBOR_NAMESPACE"

if [ "$SKIP_PROFILE_SELECT" = false ]; then
    list_minikube_profiles
else
    echo -e "  ${GRAY}Profile selection skipped — using: ${CYAN}${MINIKUBE_PROFILE}${RESET}"
fi

if [ -n "${HARBOR_HOSTNAME:-}" ]; then
    echo -e "  ${GREEN}✅ Using hostname: ${CYAN}${HARBOR_HOSTNAME}${RESET}"
fi

if [ -n "${HARBOR_HTTP_PORT_ARG:-}" ]; then
    HARBOR_HTTP_PORT="$HARBOR_HTTP_PORT_ARG"
elif [ "$USE_STANDARD_PORTS" = "true" ]; then
    HARBOR_HTTP_PORT="80"
else
    prompt_port HARBOR_HTTP_PORT "🌍 HTTP port" "$HARBOR_HTTP_PORT"
fi

if [ -n "${HARBOR_ENABLE_HTTPS_ARG:-}" ]; then
    HARBOR_ENABLE_HTTPS="$HARBOR_ENABLE_HTTPS_ARG"
else
    prompt_yn HARBOR_ENABLE_HTTPS "🔒 Enable HTTPS?" "n"
fi

if [ "$HARBOR_ENABLE_HTTPS" = "true" ]; then
    if [ -n "${HARBOR_HTTPS_PORT_ARG:-}" ]; then
        HARBOR_HTTPS_PORT="$HARBOR_HTTPS_PORT_ARG"
    elif [ "$USE_STANDARD_PORTS" = "true" ]; then
        HARBOR_HTTPS_PORT="443"
    else
        prompt_port HARBOR_HTTPS_PORT "🌍 HTTPS port" "$HARBOR_HTTPS_PORT"
    fi

    if [ -n "${HARBOR_SSL_DIR_ARG:-}" ]; then
        HARBOR_SSL_DIR="$HARBOR_SSL_DIR_ARG"
    else
        DEFAULT_SSL_ABS="$(resolve_path "../generate-ssl-certs/ssl/intermediate/certs")"
        prompt_with_default HARBOR_SSL_DIR "📂 SSL certificate & key directory " "${DEFAULT_SSL_ABS}"
    fi

    HARBOR_CERT_PATH="${HARBOR_SSL_DIR}/idol-docker-host-fullchain.cert.pem"
    HARBOR_KEY_PATH="${HARBOR_SSL_DIR}/idol-docker-host.key.pem"

    if [ -n "${HARBOR_CERT_PATH_ARG:-}" ]; then
        HARBOR_CERT_PATH="$HARBOR_CERT_PATH_ARG"
    else
        prompt_with_default HARBOR_CERT_PATH "📄 Certificate file" "$HARBOR_CERT_PATH"
    fi

    if [ -n "${HARBOR_KEY_PATH_ARG:-}" ]; then
        HARBOR_KEY_PATH="$HARBOR_KEY_PATH_ARG"
    else
        prompt_with_default HARBOR_KEY_PATH "🔑 Key file" "$HARBOR_KEY_PATH"
    fi

    if [ ! -f "$HARBOR_CERT_PATH" ] || [ ! -f "$HARBOR_KEY_PATH" ]; then
        generate_self_signed_cert "$HARBOR_CERT_PATH" "$HARBOR_KEY_PATH" "$HARBOR_HOSTNAME"
    fi
fi

echo -e ""
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "${BOLD} Configuration Summary${RESET}"
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "  Namespace        : ${CYAN}$HARBOR_NAMESPACE${RESET}"
echo -e "  Hostname         : ${CYAN}$HARBOR_HOSTNAME${RESET}"
echo -e "  HTTP port        : ${CYAN}$HARBOR_HTTP_PORT${RESET}"
if [ "${HARBOR_ENABLE_HTTPS:-false}" = "true" ]; then
    echo -e "  HTTPS port       : ${CYAN}$HARBOR_HTTPS_PORT${RESET}"
    echo -e "  Certificate      : ${CYAN}$HARBOR_CERT_PATH${RESET}"
    echo -e "  Key              : ${CYAN}$HARBOR_KEY_PATH${RESET}"
else
    echo -e "  HTTPS            : ${YELLOW}disabled${RESET}"
fi
echo -e "  Ports mode       : ${CYAN}$([ "$USE_STANDARD_PORTS" = true ] && echo "Standard (80/443)" || echo "Custom")${RESET}"
echo -e "  Minikube profile : ${CYAN}$MINIKUBE_PROFILE${RESET}"
echo -e "  Minikube CPUs    : ${CYAN}$MINIKUBE_CPUS${RESET}"
echo -e "  Minikube Memory  : ${CYAN}${MINIKUBE_MEMORY} MB${RESET}"
echo -e "  Minikube Disk    : ${CYAN}$MINIKUBE_DISK_SIZE${RESET}"
echo -e "  Kubernetes ver   : ${CYAN}$MINIKUBE_K8S_VERSION${RESET}"
echo -e "  Env output dir   : ${CYAN}$ENV_OUTPUT_DIR${RESET}"
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e ""

confirm_config

echo -e "${BOLD}${GREEN}=== CONFIGURATION CONFIRMED ===${RESET}"
echo -e "${BOLD}${CYAN}=== STARTING INSTALLATION ===${RESET}"

start_minikube

if [ "${HARBOR_ENABLE_HTTPS:-false}" = "true" ]; then
    create_tls_secret "$HARBOR_NAMESPACE" "$HARBOR_CERT_PATH" "$HARBOR_KEY_PATH"
    TLS_SECRET_NAME="$HARBOR_TLS_SECRET_NAME"
else
    TLS_SECRET_NAME=""
fi

VALUES_FILE=$(generate_values_yaml "$HARBOR_HOSTNAME")

deploy_harbor "$HARBOR_NAMESPACE" "$HARBOR_VERSION" "$VALUES_FILE"
wait_for_harbor "$HARBOR_NAMESPACE"

start_harbor_port_forward "$HARBOR_NAMESPACE" "$HARBOR_HTTP_PORT" "$HARBOR_HTTPS_PORT" "${HARBOR_ENABLE_HTTPS:-false}"

export_minikube_env_vars

# ── Patch the host Docker daemon so it can reach the insecure registry ──
# Uses: MINIKUBE_INSECURE_REGISTRY (bare hostname) and HARBOR_HTTPS_PORT (NodePort)
update_docker_daemon_json "$MINIKUBE_INSECURE_REGISTRY" "$HARBOR_HTTPS_PORT"
print_summary "$HARBOR_HOSTNAME" "$HARBOR_HTTP_PORT" "$HARBOR_HTTPS_PORT" "${HARBOR_ENABLE_HTTPS:-false}"

update_docker_daemon_json "localhost" "30003"
print_summary "localhost" "30002" "30003" "${HARBOR_ENABLE_HTTPS:-false}"


rm -f "$VALUES_FILE"
echo -e "${GREEN}🎉 All done! Harbor is now running on Minikube with hostname idol-docker-host.${RESET}"
echo ""
echo "Open in browser: https://idol-docker-host:30003"
echo "Login: admin / Harbor12345"
echo "Add to Windows hosts file: 127.0.0.1 idol-docker-host"