#!/bin/bash
#
# IDOL Deployment Script
# Professional, simplified, and robust deployment automation for IDOL platform.
# Written in the style of senior DevOps / Platform Engineering.
#
# Features:
#   - Pre-flight dependency checks
#   - Secure Docker registry authentication (PAT)
#   - Environment loading from pre-setup.sh + SSL passwords
#   - Interactive LLM Answer Server model selection with smart matching
#   - Support for IDOL_LLM_MODEL_NAME and IDOL_ANSWERSERVER_LLM_MODEL_NAME
#   - LLM + LLM-Wiki deployment orchestration
#   - Docker network management
#   - Conditional SSL compose file
#   - Safe 'down' handling with project selection + confirmation
#   - Post-up configuration (Community users/roles)
#
# Usage:
#   ./deploy.sh up -d
#   ./deploy.sh down
#   IDOL_LLM_MODEL_NAME=Gemma3-4B ./deploy.sh up
#

set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Color & Logging
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHT_YELLOW='\033[38;5;228m'
BLUE='\033[0;34m'
ORANGE='\033[0;38;5;214m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

log() {
    local level="$1"; shift
    local color="$NC"
    case "$level" in
        INFO)    color="$CYAN" ;;
        SUCCESS) color="$GREEN" ;;
        WARN)    color="$YELLOW" ;;
        ERROR)   color="$RED" ;;
        STEP)    color="$BLUE" ;;
    esac
    printf "%b[%s]%b %s\n" "$color" "$level" "$NC" "$*"
}

die() {
    log ERROR "$*"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight Checks
# ─────────────────────────────────────────────────────────────────────────────
command -v docker >/dev/null || die "Docker is not installed or not in PATH."
command -v jq     >/dev/null || die "jq is required but not installed."

# ─────────────────────────────────────────────────────────────────────────────
# Argument & Environment Handling
# ─────────────────────────────────────────────────────────────────────────────
DOCKER_COMPOSE_ARGS="$*"
LLM_DEPLOY_ARGS="${LLM_DEPLOY_ARGS:-$DOCKER_COMPOSE_ARGS}"

# Detect command type (robust enough for common cases)
IS_DOWN=false
IS_UP=false
[[ " $* " =~ " down " ]] && IS_DOWN=true
[[ " $* " =~ " up "   ]] && IS_UP=true

# ─────────────────────────────────────────────────────────────────────────────
# Load Secrets & Pre-setup
# ─────────────────────────────────────────────────────────────────────────────
PASSWORD_FILE="../../env/.idol-ssl-passwords.env"
if [[ ! -f "$PASSWORD_FILE" ]]; then
    die "Password file not found: $PASSWORD_FILE\nRun generate-ssl.sh first."
fi
# shellcheck disable=SC1090
source "$PASSWORD_FILE"
log SUCCESS "Sourced SSL passwords: IDOL_CERT_KEYSTORE_PASS=${IDOL_CERT_KEYSTORE_PASS:-(not set)}"

if [[ ! -s ./pre-setup.sh ]]; then
    die "pre-setup.sh is missing or empty.\nRestore from pre-setup-backup.sh if needed."
fi
# shellcheck disable=SC1091
source ./pre-setup.sh
log SUCCESS "Sourced pre-setup.sh — environment variables loaded."

# Promote IDOL_LLM_MODEL_NAME → IDOL_ANSWERSERVER_LLM_MODEL_NAME if needed
if [[ -z "${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-}" && -n "${IDOL_LLM_MODEL_NAME:-}" ]]; then
    export IDOL_ANSWERSERVER_LLM_MODEL_NAME="$IDOL_LLM_MODEL_NAME"
    log INFO "IDOL_ANSWERSERVER_LLM_MODEL_NAME set from IDOL_LLM_MODEL_NAME=${IDOL_ANSWERSERVER_LLM_MODEL_NAME}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Docker Registry Authentication (skipped for teardown)
# ─────────────────────────────────────────────────────────────────────────────
if ! $IS_DOWN; then
    log STEP "Docker Registry Authentication"
    log WARN "IDOL images must be downloaded from https://authenticate.microfocus.net/ using your OpenText credentials."

    DOCKER_LOGIN_SUCCESS=false

    # Try env var first
    if [[ -n "${IDOL_LICENSE_KEY_TOKEN:-}" ]]; then
        log INFO "Attempting login with IDOL_LICENSE_KEY_TOKEN from environment..."
        if echo "$IDOL_LICENSE_KEY_TOKEN" | docker login --username microfocusidolreadonly --password-stdin &>/dev/null; then
            log SUCCESS "Docker access token validated."
            DOCKER_LOGIN_SUCCESS=true
        else
            log WARN "Env token invalid. Prompting for new token..."
        fi
    fi

    # Interactive prompt loop
    while ! $DOCKER_LOGIN_SUCCESS; do
        read -r -s -p "$(printf "%bEnter IDOL Docker PAT [dckr_pat_XXXXX]: %b" "$CYAN" "$NC")" IDOL_LICENSE_KEY_TOKEN
        echo
        if [[ ! "$IDOL_LICENSE_KEY_TOKEN" =~ ^dckr[_A-Za-z0-9-]+$ ]]; then
            log ERROR "Invalid token format. Expected: dckr_pat_..."
            continue
        fi
        if echo "$IDOL_LICENSE_KEY_TOKEN" | docker login --username microfocusidolreadonly --password-stdin; then
            log SUCCESS "Docker access token is valid."
            DOCKER_LOGIN_SUCCESS=true
        else
            log ERROR "Login failed. Please try again."
        fi
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Main Deployment Banner
# ─────────────────────────────────────────────────────────────────────────────
cat <<'EOF'

═══════════════════════════════════════════════════════════════════════════════
  IDOL Deployment Script  •  DATA-ADMIN subtype
═══════════════════════════════════════════════════════════════════════════════
EOF

# ─────────────────────────────────────────────────────────────────────────────
# LLM Integration (Answer Server model selection + deployment)
# ─────────────────────────────────────────────────────────────────────────────
if $IS_DOWN; then
    log WARN "LLM deployment skipped (down command detected)."
elif [[ "${IDOL_LLM_INTEGRATION:-}" == "TRUE" ]]; then
    log STEP "LLM Deployment"

    # ── Interactive Default Answer Server Model Selection ─────────────────────
    MODEL_DIR="${IDOL_LLM_MODEL_PATH:-$HOME/llm-models}"
    mkdir -p "$MODEL_DIR"

    if [[ -t 0 ]]; then
        shopt -s nullglob
        gguf_files=("$MODEL_DIR"/*.gguf)
        shopt -u nullglob

        CONFIGURED_MODEL="${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-}"
        CONFIGURED_NORM=""
        if [[ -n "$CONFIGURED_MODEL" ]]; then
            CONFIGURED_NORM=$(echo "$CONFIGURED_MODEL" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
        fi

        # Check if configured model already exists locally
        CONFIGURED_FILE=""
        for f in "${gguf_files[@]}"; do
            NORM=$(basename "$f" .gguf | tr '[:upper:]' '[:lower:]' | tr '_' '-')
            FILE_KEY=$(echo "$NORM" | tr -d '[:punct:]')
            if [[ -n "$CONFIGURED_NORM" ]] && \
               { [[ "$FILE_KEY" == "$CONFIGURED_NORM" ]] || \
                 [[ "$FILE_KEY" == *"$CONFIGURED_NORM"* ]] || \
                 [[ "$CONFIGURED_NORM" == *"$FILE_KEY"* ]]; }; then
                CONFIGURED_FILE="$f"
                break
            fi
        done

        if [[ -n "$CONFIGURED_MODEL" && -z "$CONFIGURED_FILE" ]]; then
            log WARN "Configured model '${CONFIGURED_MODEL}' not found locally."
            log INFO "It will be downloaded/prepared during LLM deployment."
        fi

        # Only show interactive picker if there are local models OR a configured model is set
        if ((${#gguf_files[@]} > 0)) || [[ -n "$CONFIGURED_MODEL" ]]; then
            log STEP "Select Default Answer Server Model"

            declare -a MODEL_NAMES=()
            DEFAULT_IDX=1
            idx=1

            # Show configured model first (even if file missing)
            if [[ -n "$CONFIGURED_MODEL" ]]; then
                MARK=""
                if [[ -n "$CONFIGURED_FILE" ]]; then
                    MARK=" ${GREEN}(current)${NC}"
                else
                    MARK=" ${ORANGE}(not found locally — will download)${NC}"
                fi
                printf "   %b[%d]%b %s%b\n" "$CYAN" "$idx" "$NC" "$CONFIGURED_MODEL" "$MARK"
                MODEL_NAMES+=("$CONFIGURED_MODEL")
                DEFAULT_IDX=1
                ((idx++))
            fi

            # Then list all locally available models
            for f in "${gguf_files[@]}"; do
                NORM=$(basename "$f" .gguf | tr '[:upper:]' '[:lower:]' | tr '_' '-')

                # Skip if this is the same as the configured one we already showed
                if [[ -n "$CONFIGURED_MODEL" && "$NORM" == "$(echo "$CONFIGURED_MODEL" | tr '[:upper:]' '[:lower:]' | tr '_' '-')" ]]; then
                    continue
                fi

                MODEL_NAMES+=("$NORM")

                MARK=""
                if [[ -n "$CONFIGURED_NORM" ]]; then
                    FILE_KEY=$(echo "$NORM" | tr -d '[:punct:]')
                    if [[ "$FILE_KEY" == "$CONFIGURED_NORM" || "$FILE_KEY" == *"$CONFIGURED_NORM"* || "$CONFIGURED_NORM" == *"$FILE_KEY"* ]]; then
                        MARK=" ${GREEN}(current)${NC}"
                        DEFAULT_IDX=$idx
                    fi
                fi

                printf "   %b[%d]%b %s%b  %b(%s)%b\n" \
                    "$CYAN" "$idx" "$NC" "$NORM" "$MARK" "$BLUE" "$(basename "$f")" "$NC"
                ((idx++))
            done

            TOTAL_OPTIONS=${#MODEL_NAMES[@]}
            if (( TOTAL_OPTIONS > 0 )); then
                read -r -p "$(printf "%b→ Enter number [1-%d] (default: %d): %b" "$YELLOW" "$TOTAL_OPTIONS" "$DEFAULT_IDX" "$NC")" SELECTED_IDX
                SELECTED_IDX="${SELECTED_IDX:-$DEFAULT_IDX}"

                if [[ "$SELECTED_IDX" =~ ^[0-9]+$ ]] && (( SELECTED_IDX >= 1 && SELECTED_IDX <= TOTAL_OPTIONS )); then
                    export IDOL_ANSWERSERVER_LLM_MODEL_NAME="${MODEL_NAMES[$((SELECTED_IDX-1))]}"
                    log SUCCESS "IDOL_ANSWERSERVER_LLM_MODEL_NAME set to: ${IDOL_ANSWERSERVER_LLM_MODEL_NAME}"
                else
                    log WARN "Invalid selection — keeping: ${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-$CONFIGURED_MODEL}"
                fi
                echo
            fi
        fi
    fi

    # Run LLM deployment
    log INFO "Starting LLM deployment via llm-deploy.sh..."
    ./llm-sandbox/llm-deploy.sh $LLM_DEPLOY_ARGS
    LLM_EXIT=$?

    if (( LLM_EXIT == 0 )); then
        log SUCCESS "LLM deployment completed successfully."

        # Pull back any model choice written by child scripts
        if [[ -f /tmp/idol-answerserver-model.env ]]; then
            PREV="${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-}"
            # shellcheck disable=SC1091
            source /tmp/idol-answerserver-model.env
            if [[ "${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-}" != "$PREV" ]]; then
                log INFO "IDOL_ANSWERSERVER_LLM_MODEL_NAME updated by LLM deployment → ${IDOL_ANSWERSERVER_LLM_MODEL_NAME}"
            fi
            export IDOL_ANSWERSERVER_LLM_MODEL_NAME
        fi

        # ── Update answerserver.cfg with the selected Ollama model ─────────────
        ANSWERSERVER_CFG="${IDOL_PRESERVE_ANSWERSERVER_PATH}/cfg/answerserver.cfg"
        MODEL_TO_SET="${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-${IDOL_LLM_MODEL_NAME:-}}"

        if [[ -n "$MODEL_TO_SET" && -f "$ANSWERSERVER_CFG" ]]; then
            if grep -q '^OllamaModel=' "$ANSWERSERVER_CFG"; then
                sed -i "s|^OllamaModel=.*|OllamaModel=$MODEL_TO_SET|" "$ANSWERSERVER_CFG"
                log SUCCESS "Updated OllamaModel=$MODEL_TO_SET in answerserver.cfg"
            else
                echo "OllamaModel=$MODEL_TO_SET" >> "$ANSWERSERVER_CFG"
                log SUCCESS "Added OllamaModel=$MODEL_TO_SET to answerserver.cfg"
            fi
        elif [[ -n "$MODEL_TO_SET" ]]; then
            log WARN "answerserver.cfg not found at $ANSWERSERVER_CFG — could not set OllamaModel"
        fi
    else
        die "LLM deployment failed (exit code: $LLM_EXIT)"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# LLM-Wiki Deployment (Obsidian + Ollama)
# ─────────────────────────────────────────────────────────────────────────────
if $IS_DOWN; then
    log WARN "LLM-Wiki deployment skipped (down command detected)."
elif [[ "${IDOL_LLM_WIKI_ENABLED:-}" == "TRUE" ]]; then
    log STEP "LLM-Wiki Deployment (Obsidian + Ollama)"

    WIKI_SCRIPT="./llm-wiki-setup/deploy-llm-wiki.sh"
    [[ -f "$WIKI_SCRIPT" ]] || die "LLM-Wiki script not found: $WIKI_SCRIPT"
    [[ -x "$WIKI_SCRIPT" ]] || chmod +x "$WIKI_SCRIPT"

    "$WIKI_SCRIPT" $DOCKER_COMPOSE_ARGS
    WIKI_EXIT=$?

    if (( WIKI_EXIT == 0 )); then
        log SUCCESS "LLM-Wiki deployment completed successfully."
    else
        die "LLM-Wiki deployment failed (exit code: $WIKI_EXIT)"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Docker Network
# ─────────────────────────────────────────────────────────────────────────────
DOCKER_NETWORK="idol-${IDOL_DEPLOYMENT_TYPE:-demo}-network"

if docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
    log SUCCESS "Docker network '$DOCKER_NETWORK' already exists."
else
    log INFO "Creating Docker network '$DOCKER_NETWORK'..."
    docker network create "$DOCKER_NETWORK" || die "Failed to create network $DOCKER_NETWORK"
    log SUCCESS "Network '$DOCKER_NETWORK' created."
fi

# ─────────────────────────────────────────────────────────────────────────────
# Docker Compose Execution
# ─────────────────────────────────────────────────────────────────────────────
log STEP "Starting Docker Compose"

SSL_COMPOSE=""
[[ "${IDOL_LICENSESERVER_PROTOCOL:-}" == "https" ]] && SSL_COMPOSE="-f docker-compose.ssl.yml"

docker compose --progress=auto \
    -f docker-compose.yml \
    $SSL_COMPOSE \
    -f docker-compose.expose-ports.yml \
    $DOCKER_COMPOSE_ARGS

COMPOSE_EXIT=$?
if (( COMPOSE_EXIT != 0 )); then
    die "Docker Compose failed (exit code: $COMPOSE_EXIT)"
fi
log SUCCESS "Docker Compose completed successfully."

# ─────────────────────────────────────────────────────────────────────────────
# Post-processing for 'down' command
# ─────────────────────────────────────────────────────────────────────────────
if $IS_DOWN; then
    log STEP "Cleaning up Docker Compose project"

    mapfile -t projects < <(docker compose ls --format json 2>/dev/null | jq -r '.[].Name' || true)

    if (( ${#projects[@]} == 0 )); then
        log WARN "No Docker Compose projects found."
        exit 0
    fi

    printf "\nAvailable projects:\n"
    for i in "${!projects[@]}"; do
        printf "  %2d. %s\n" $((i+1)) "${projects[$i]}"
    done

    DEFAULT_PROJECT="idol-demo"
    read -r -p "Project number to remove (default: $DEFAULT_PROJECT): " PROJECT_NUMBER

    if [[ "$PROJECT_NUMBER" =~ ^[0-9]+$ && PROJECT_NUMBER -ge 1 && PROJECT_NUMBER -le ${#projects[@]} ]]; then
        PROJECT_NAME="${projects[$((PROJECT_NUMBER-1))]}"
    else
        PROJECT_NAME="$DEFAULT_PROJECT"
        log WARN "Using default project: $PROJECT_NAME"
    fi

    while true; do
        read -r -p "Really stop & remove ALL containers, volumes, orphans for '$PROJECT_NAME'? [y/N]: " CONFIRM
        case "$CONFIRM" in
            [Yy]) break ;;
            [Nn]|"") log INFO "Aborted by user."; exit 0 ;;
            *) log WARN "Please answer y or n." ;;
        esac
    done

    log WARN "Removing project: $PROJECT_NAME"
    if docker compose -p "$PROJECT_NAME" down -v --remove-orphans --progress=auto; then
        log SUCCESS "Project '$PROJECT_NAME' fully removed."
    else
        die "Failed to remove project '$PROJECT_NAME'"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Post-processing for 'up' command
# ─────────────────────────────────────────────────────────────────────────────
if $IS_UP; then
    if [[ -f ./wait-dataadmin-for-log.sh ]]; then
        log STEP "Waiting for IDOL Data Admin UI to become ready..."
        chmod +x ./wait-dataadmin-for-log.sh 2>/dev/null || true
        ./wait-dataadmin-for-log.sh
        log SUCCESS "Data Admin UI is ready."
    else
        log WARN "wait-dataadmin-for-log.sh not found — skipping wait."
    fi

    log STEP "Configuring IDOL Community users and roles..."
    # Prefer EXTRA_IP_SANS_ENV when it differs from IDOL_NET_HOST_IP (e.g. public IP)
    if [[ -n "${EXTRA_IP_SANS_ENV:-}" && -n "${IDOL_NET_HOST_IP:-}" && "${EXTRA_IP_SANS_ENV}" != "${IDOL_NET_HOST_IP}" ]]; then
        export COMMUNITY_HOST="${EXTRA_IP_SANS_ENV}"
        log INFO "COMMUNITY_HOST set from EXTRA_IP_SANS_ENV → ${COMMUNITY_HOST}"
    else
        export COMMUNITY_HOST="${IDOL_NET_HOST_IP:-idol-docker-host}"
        log INFO "COMMUNITY_HOST set from IDOL_NET_HOST_IP (or default) → ${COMMUNITY_HOST}"
    fi

    if [[ -n "${PORT_DATA_ADMIN_COMMUNITY:-}" ]]; then
        export COMMUNITY_PORT="${PORT_DATA_ADMIN_COMMUNITY}"
        log INFO "COMMUNITY_PORT set from PORT_DATA_ADMIN_COMMUNITY → ${COMMUNITY_PORT}"
    else
        export COMMUNITY_PORT="${COMMUNITY_PORT:-9033}"
        log WARN "PORT_DATA_ADMIN_COMMUNITY is unset — using ${COMMUNITY_PORT}"
    fi

    export COMMUNITY_CERT="${COMMUNITY_CERT:-./ssl/intermediate/certs/ca-chain.cert.pem}"
    export COMMUNITY_YES=1
    log INFO "COMMUNITY_CERT=${COMMUNITY_CERT}"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    USER_ROLE_SCRIPT=""
    for candidate in \
        "${SCRIPT_DIR}/create-users-roles.py" \
        "./create-users-roles.py" \
        "${SCRIPT_DIR}/../create-users-roles.py"
    do
        if [[ -f "$candidate" ]]; then
            USER_ROLE_SCRIPT="$candidate"
            break
        fi
    done

    if [[ -z "$USER_ROLE_SCRIPT" ]]; then
        log ERROR "create-users-roles.py not found next to this deploy script (${SCRIPT_DIR})."
    elif ! command -v python3 >/dev/null; then
        log ERROR "python3 is not installed or not in PATH."
    elif python3 "$USER_ROLE_SCRIPT" -y; then
        log SUCCESS "Community users and roles configured."
    else
        log ERROR "Community user/role setup failed."
        log WARN "Rerun standalone: python3 ${USER_ROLE_SCRIPT} --host ${COMMUNITY_HOST} --port ${COMMUNITY_PORT} --insecure -y"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Final Banner
# ─────────────────────────────────────────────────────────────────────────────
cat <<'EOF'

═══════════════════════════════════════════════════════════════════════════════
  ✅  Deployment Complete
═══════════════════════════════════════════════════════════════════════════════
EOF
