#!/bin/bash
set -e

# Create directories
mkdir -p config lib logs

# ========== deploy-minikube.sh ==========
cat > deploy-minikube.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Determine script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Default values
BASE_PATH="${SCRIPT_DIR}"
LOG_PATH="${BASE_PATH}/logs"
INSTALL_VERSION="1.0.0"
PROFILE_NAME=""
NON_INTERACTIVE=false
STANDALONE=false

# Parse command line arguments
usage() {
    cat <<EOL
Usage: $0 [options]

Options:
  --base-path PATH       Base directory for config, logs, etc. (default: script dir)
  --log-path PATH        Directory for log files (default: BASE_PATH/logs)
  --install-version VER  Version identifier for this installation (default: 1.0.0)
  --profile-name NAME    Directly use a specific profile (bypass selection)
  --non-interactive      Run without prompts (requires --profile-name)
  --standalone           Execute the full deployment (instead of just loading functions)
  -h, --help             Show this help
EOL
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --base-path)       BASE_PATH="$2"; shift 2 ;;
        --log-path)        LOG_PATH="$2"; shift 2 ;;
        --install-version) INSTALL_VERSION="$2"; shift 2 ;;
        --profile-name)    PROFILE_NAME="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --standalone)      STANDALONE=true; shift ;;
        -h|--help)         usage; exit 0 ;;
        *)                 error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Validate required parameters for non-interactive mode
if [[ "$NON_INTERACTIVE" == true && -z "$PROFILE_NAME" ]]; then
    error "Non-interactive mode requires --profile-name"
    exit 1
fi

# Set up logging
setup_logging "$LOG_PATH" "deploy_minikube_${INSTALL_VERSION}.log"
log "INFO" "Starting Minikube deployment (version $INSTALL_VERSION)"

# Load configuration
PROFILES_FILE="${BASE_PATH}/config/profiles.json"
if [[ ! -f "$PROFILES_FILE" ]]; then
    error "Profiles file not found: $PROFILES_FILE"
    exit 1
fi
CONFIG_PROFILES=$(jq -c . "$PROFILES_FILE") || die "Invalid JSON in profiles file"

# Check prerequisites
source "$SCRIPT_DIR/lib/prerequisites.sh"
check_prerequisites || die "Prerequisites check failed"

# If no profile name given, let the user select one
if [[ -z "$PROFILE_NAME" ]]; then
    source "$SCRIPT_DIR/lib/profile.sh"
    PROFILE_NAME=$(select_profile "$PROFILES_FILE" "$NON_INTERACTIVE")
fi

# Load the selected profile settings
source "$SCRIPT_DIR/lib/profile.sh"
PROFILE_ENV=$(load_profile_settings "$PROFILES_FILE" "$PROFILE_NAME" "$BASE_PATH")
source "$PROFILE_ENV"   # This exports MINIKUBE_* variables

# Start Minikube with the profile
source "$SCRIPT_DIR/lib/minikube.sh"
start_minikube_profile "$PROFILE_NAME"

# Enable required add‑ons and configure registry
configure_minikube_addons "$PROFILE_NAME"

log "SUCCESS" "Minikube profile '$PROFILE_NAME' is ready."
EOF

# ========== config/profiles.json ==========
cat > config/profiles.json << 'EOF'
{
  "Minikube_Settings": {
    "Knowledge_Discovery": {
      "Profile_Name": "opentext-idol",
      "Memory": "8192",
      "CPUs": "4",
      "Storage": "50GB",
      "Container_Runtime": "docker",
      "Network_Policy": "calico",
      "Insecure_Registry": "myregistry.local:5000",
      "Kubernetes_Version": "stable"
    },
    "Extended_ECM": {
      "Profile_Name": "opentext-xecm",
      "Memory": "8192",
      "CPUs": "4",
      "Storage": "50GB",
      "Container_Runtime": "docker",
      "Network_Policy": "calico",
      "Insecure_Registry": "myregistry.local:5000",
      "Kubernetes_Version": "v1.35.0"
    },    
    "Default": {
      "Profile_Name": "minikube",
      "Memory": "4096",
      "CPUs": "2",
      "Storage": "20GB",
      "Container_Runtime": "docker",
      "Network_Policy": "bridge",
      "Insecure_Registry": "",
      "Kubernetes_Version": "stable"
    }
  }
}
EOF

# ========== lib/common.sh ==========
cat > lib/common.sh << 'EOF'
#!/bin/bash
# Common functions for logging, prompting, validation

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly ORANGE='\033[0;38;5;214m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

LOGFILE=""

setup_logging() {
    local log_dir="$1"
    local log_file="$2"
    mkdir -p "$log_dir"
    LOGFILE="${log_dir}/${log_file}"
    touch "$LOGFILE"
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=""
    case $level in
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        *)     color="$NC" ;;
    esac
    echo -e "${timestamp} ${color}[${level}]${NC} ${message}" | tee -a "$LOGFILE"
}

die() {
    log "ERROR" "$1"
    exit 1
}

prompt_yn() {
    local prompt="$1"
    local default="${2:-Y}"
    local response
    while true; do
        read -p "$prompt (Y/n): " response
        response=${response:-$default}
        case "${response,,}" in
            y) return 0 ;;
            n) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        return 1
    fi
    return 0
}

has_sudo() {
    if [[ $EUID -eq 0 ]]; then
        die "This script should not be run as root. Run as a user with sudo privileges."
    fi
    if ! sudo -n true 2>/dev/null; then
        return 1
    fi
    return 0
}
EOF

# ========== lib/prerequisites.sh ==========
cat > lib/prerequisites.sh << 'EOF'
#!/bin/bash
# Functions to verify/install Docker, kubectl, helm, minikube, jq

check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    # Docker
    if ! check_command docker; then
        log "WARN" "Docker not found. Installing..."
        install_docker
    else
        log "INFO" "Docker is already installed."
    fi

    # kubectl
    if ! check_command kubectl; then
        log "WARN" "kubectl not found. Installing..."
        install_kubectl
    fi

    # helm
    if ! check_command helm; then
        log "WARN" "helm not found. Installing..."
        install_helm
    fi

    # minikube
    if ! check_command minikube; then
        log "WARN" "minikube not found. Installing..."
        install_minikube
    fi

    # jq (for JSON parsing)
    if ! check_command jq; then
        log "WARN" "jq not found. Installing..."
        sudo apt-get update && sudo apt-get install -y jq
    fi

    log "INFO" "All prerequisites satisfied."
}

install_docker() {
    # Official Docker install script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    sudo usermod -aG docker "$USER"
    log "WARN" "You may need to log out and back in for docker group changes to take effect."
    # Restart docker service
    sudo systemctl enable docker && sudo systemctl start docker
}

install_kubectl() {
    local version
    version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo install -o "$USER" -g "$USER" -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
}

install_helm() {
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
}

install_minikube() {
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
    sudo dpkg -i minikube_latest_amd64.deb
    rm minikube_latest_amd64.deb
}
EOF

# ========== lib/profile.sh ==========
cat > lib/profile.sh << 'EOF'
#!/bin/bash
# Functions for listing, selecting, creating, and loading profiles

# Load profile settings and export as environment variables
load_profile_settings() {
    local config_file="$1"
    local profile_name="$2"
    local base_path="$3"
    local env_file="${base_path}/env/minikube_${profile_name}.env"
    mkdir -p "${base_path}/env"

    # Validate profile exists
    if ! jq -e ".Minikube_Settings.\"$profile_name\"" "$config_file" &>/dev/null; then
        die "Profile '$profile_name' not found in $config_file"
    fi

    # Write environment file
    jq -r ".Minikube_Settings.\"$profile_name\" | to_entries[] | \"export MINIKUBE_\(.key | ascii_upcase)=\(.value | @sh)\"" "$config_file" > "$env_file"

    # Source it to export in current shell
    source "$env_file"
    echo "$env_file"
}

# List available profiles with numbers
list_profiles() {
    local config_file="$1"
    jq -r '.Minikube_Settings | keys[]' "$config_file" | nl -w2 -s'. '
}

# Interactive profile selection (or return default if non‑interactive)
select_profile() {
    local config_file="$1"
    local non_interactive="$2"
    local profiles=($(jq -r '.Minikube_Settings | keys[]' "$config_file"))

    if [[ "$non_interactive" == true ]]; then
        # Return first profile as default
        echo "${profiles[0]}"
        return
    fi

    echo "Available profiles:"
    list_profiles "$config_file"
    echo ""
    read -p "Select profile by number (default 1): " choice
    choice=${choice:-1}
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#profiles[@]} )); then
        die "Invalid selection"
    fi
    echo "${profiles[$((choice-1))]}"
}

# Create a new profile interactively
create_new_profile() {
    local config_file="$1"
    local base_path="$2"
    # This function would prompt for all settings and append to profiles.json
    # Implementation omitted for brevity – similar to original get_infra_configuration
    # but writes to the JSON file instead of an env file.
}
EOF

# ========== lib/minikube.sh ==========
cat > lib/minikube.sh << 'EOF'
#!/bin/bash
# Functions to start Minikube, enable addons, configure registry

start_minikube_profile() {
    local profile="$1"

    # Check if already running
    if minikube status -p "$profile" &>/dev/null; then
        log "INFO" "Minikube profile '$profile' is already running."
        return 0
    fi

    log "INFO" "Starting Minikube profile '$profile'..."

    # Build command from environment variables
    local cmd=(minikube start -p "$profile")
    [[ -n "${MINIKUBE_CPUS:-}" ]] && cmd+=(--cpus="$MINIKUBE_CPUS")
    [[ -n "${MINIKUBE_MEMORY:-}" ]] && cmd+=(--memory="${MINIKUBE_MEMORY}")
    [[ -n "${MINIKUBE_DISK_SIZE:-}" ]] && cmd+=(--disk-size="${MINIKUBE_DISK_SIZE}")
    [[ -n "${MINIKUBE_CONTAINER_RUNTIME:-}" ]] && cmd+=(--container-runtime="${MINIKUBE_CONTAINER_RUNTIME}")
    [[ -n "${MINIKUBE_NETWORK_POLICY:-}" ]] && cmd+=(--cni="${MINIKUBE_NETWORK_POLICY}")
    [[ -n "${MINIKUBE_INSECURE_REGISTRY:-}" ]] && cmd+=(--insecure-registry="${MINIKUBE_INSECURE_REGISTRY}")
    [[ -n "${MINIKUBE_KUBERNETES_VERSION:-}" ]] && cmd+=(--kubernetes-version="${MINIKUBE_KUBERNETES_VERSION}")
    cmd+=(--addons=ingress --install-addons=true)

    # Execute
    if ! "${cmd[@]}"; then
        die "Failed to start Minikube profile '$profile'"
    fi
    log "INFO" "Minikube profile '$profile' started."
}

configure_minikube_addons() {
    local profile="$1"
    log "INFO" "Enabling addons for profile '$profile'..."
    minikube -p "$profile" addons enable ingress
    minikube -p "$profile" addons enable metrics-server
    minikube -p "$profile" addons enable dashboard

    # Set as active profile
    minikube profile "$profile"

    # Registry secret creation (example – adapt to your needs)
    if [[ -n "${REGISTRY_URL:-}" && -n "${REGISTRY_PROJECT:-}" ]]; then
        kubectl create namespace "${REGISTRY_PROJECT}" --dry-run=client -o yaml | kubectl apply -f -
        if kubectl get secret -n "$REGISTRY_PROJECT" registry-secret &>/dev/null; then
            kubectl delete secret -n "$REGISTRY_PROJECT" registry-secret
        fi
        kubectl create secret docker-registry registry-secret \
            --docker-server="$REGISTRY_URL/$REGISTRY_PROJECT" \
            --docker-username="${REGISTRY_USERNAME:-admin}" \
            --docker-password="${REGISTRY_PASSWORD:-Harbor12345}" \
            -n "$REGISTRY_PROJECT"
    fi
}
EOF

# Make the main script executable
chmod +x deploy-minikube.sh

echo "✅ All files created successfully."
echo "Run ./deploy-minikube.sh --help for usage."