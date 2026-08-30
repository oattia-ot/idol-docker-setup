#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# Color codes
# ─────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ─────────────────────────────────────────────
# Usage / Help
# ─────────────────────────────────────────────
usage() {
  echo -e "
${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗
║                     LLM Stack Manager                        ║
╚══════════════════════════════════════════════════════════════╝${NC}

${BOLD}SYNOPSIS${NC}
    $(basename "$0") [OPTIONS] <DOCKER_COMPOSE_COMMAND> [ARGS...]

${BOLD}DESCRIPTION${NC}
    Wrapper around docker compose for the LLM sandbox stack.
    Handles environment preparation, model import, and health checks automatically.

${BOLD}OPTIONS${NC}
    ${CYAN}-h, --help${NC}        Show this help message and exit
    ${CYAN}-v, --version${NC}     Show script version

${BOLD}DOCKER COMPOSE COMMANDS${NC}
    ${GREEN}up${NC}                Start the full LLM stack
    ${GREEN}down${NC}              Stop and remove containers
    ${GREEN}restart${NC}           Restart all services
    ${GREEN}logs${NC}              View service logs
    ${GREEN}ps${NC}                List running services
    ${GREEN}pull${NC}              Pull latest images
    ${GREEN}exec${NC}              Execute command inside a container
    ${GREEN}build${NC}             Build or rebuild services

${BOLD}REQUIRED ENVIRONMENT VARIABLES${NC}
    ${CYAN}IDOL_BASE_PATH${NC}                    Base path for IDOL deployment
    ${CYAN}IDOL_TOOLKIT_PATH${NC}                 Relative path to the toolkit
    ${CYAN}IDOL_DEPLOYMENT_SUBTYPE${NC}           Deployment subtype
    ${CYAN}IDOL_LLM_MODEL_PATH${NC}               Path to .gguf model files
    ${CYAN}IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC}  (optional) Default model for Answer Server
    ${CYAN}IDOL_LLM_MODEL_NAME${NC}               (optional) Fallback name

${BOLD}USAGE EXAMPLES${NC}
    ./$(basename "$0") up -d
    ./$(basename "$0") restart ollama
    ./$(basename "$0") logs -f

${DIM}────────────────────────────────────────────────────────────────${NC}
"
  exit 0
}

version() {
  echo -e "${BOLD}llm-deploy.sh${NC} version ${CYAN}1.5.0${NC} (smart auto-selection for IDOL_ANSWERSERVER_LLM_MODEL_NAME)"
  exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage
[[ "${1:-}" == "-v" || "${1:-}" == "--version" ]] && version

# ─────────────────────────────────────────────
# INTERACTIVE ENVIRONMENT CONFIGURATION
# ─────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── Environment Configuration ──${NC}"

prompt_var() {
  local varname="$1"
  local default="$2"
  local description="$3"

  if [ -z "${!varname:-}" ]; then
    echo -e "${CYAN}→ ${description}${NC}"
    read -r -p "Use default [${default}]? (Y/n) or type new value: " answer
    if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
      export "$varname"="$default"
      echo -e "${GREEN}[OK]${NC}    Using default: ${default}"
    else
      export "$varname"="$answer"
      echo -e "${GREEN}[OK]${NC}    Using: ${answer}"
    fi
  else
    echo -e "${GREEN}[OK]${NC}    ${varname} is already set → ${!varname}"
  fi
}

prompt_var "IDOL_BASE_PATH" "~/idol-docker-setup" "Base path for IDOL deployment"
prompt_var "IDOL_TOOLKIT_PATH" "idol-containers-toolkit" "Relative path to the toolkit"
prompt_var "IDOL_DEPLOYMENT_SUBTYPE" "data-admin" "Deployment subtype"

# ─────────────────────────────────────────────
# LLM MODEL PATH – ONLY ASK IF NOT ALREADY SET
# ─────────────────────────────────────────────
if [ -z "${IDOL_LLM_MODEL_PATH:-}" ]; then
  DEFAULT_MODEL_PATH="$HOME/llm-models"
  echo -e "${CYAN}→ Where do you want to save the LLM models?${NC}"
  echo -e "${DIM}   (press Enter to accept the default shown in [])${NC}"
  read -r -p "Path [${DEFAULT_MODEL_PATH}]: " MODEL_ANSWER

  if [ -n "$MODEL_ANSWER" ]; then
    export IDOL_LLM_MODEL_PATH="$MODEL_ANSWER"
  else
    export IDOL_LLM_MODEL_PATH="$DEFAULT_MODEL_PATH"
  fi
  echo -e "${GREEN}[OK]${NC}    LLM models will be stored in: ${IDOL_LLM_MODEL_PATH}"
else
  echo -e "${GREEN}[OK]${NC}    IDOL_LLM_MODEL_PATH is already set → ${IDOL_LLM_MODEL_PATH}"
fi

mkdir -p "$IDOL_LLM_MODEL_PATH"
echo -e "${GREEN}[OK]${NC}    Model directory is ready"

# ─────────────────────────────────────────────
# Resolve script location
# ─────────────────────────────────────────────
llm_deploy_subtype=$(echo "$IDOL_DEPLOYMENT_SUBTYPE" | tr ',' '\n' | grep 'data-admin' | head -1)
llm_deploy_path="$IDOL_BASE_PATH/$IDOL_TOOLKIT_PATH/$llm_deploy_subtype"
llm_sandbox_dir="$llm_deploy_path/llm-sandbox"

if [ ! -d "$llm_sandbox_dir" ]; then
    echo -e "\n${RED}${BOLD}ERROR: LLM sandbox directory not found!${NC}"
    echo -e "${RED}       Path checked: ${BOLD}$llm_sandbox_dir${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$llm_sandbox_dir" && pwd)"
echo -e "${GREEN}${BOLD}✓${NC} LLM sandbox directory found at: ${BOLD}$SCRIPT_DIR${NC}"

# ─────────────────────────────────────────────
# Setup logging
# ─────────────────────────────────────────────
LOG_DIR="$SCRIPT_DIR/logs"
TIMESTAMP=$(date '+%Y-%m-%d_%H:%M:%S')
LOG_FILE="${LOG_DIR}/llm-stack-${TIMESTAMP}.log"
mkdir -p "$LOG_DIR"
echo "[$TIMESTAMP] llm-deploy started with args: ${*:-<none>}" >> "$LOG_FILE"

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────
log()     { echo -e "$1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "$1"; }
info()    { log "${CYAN}[INFO]${NC}  $1"; }
success() { log "${GREEN}[OK]${NC}    $1"; }
warn()    { log "${YELLOW}[WARN]${NC}  $1"; }
error()   { log "${RED}[ERROR]${NC} $1"; }
section() { log "\n${BOLD}${BLUE}── $1 ──${NC}"; }

# ─────────────────────────────────────────────
# Dependency check
# ─────────────────────────────────────────────
section "Dependency Check"

for cmd in docker; do
  if command -v "$cmd" &>/dev/null; then
    success "$cmd found ($(command -v $cmd))"
  else
    error "$cmd is required but not installed. Aborting."
    exit 1
  fi
done

if docker compose version &>/dev/null; then
  success "docker compose plugin found ($(docker compose version --short))"
else
  error "docker compose plugin not found. Aborting."
  exit 1
fi

# ─────────────────────────────────────────────
# File checks
# ─────────────────────────────────────────────
section "Pre-flight Checks"

COMPOSE_FILE="$SCRIPT_DIR/llm-docker-compose.yml"
PREPARED_ENV="$SCRIPT_DIR/llm-prepared-env.sh"
IMPORT_LLM_MODELS="$SCRIPT_DIR/import-llm-models.sh"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  error "Compose file not found: $COMPOSE_FILE"
  exit 1
fi
success "Compose file: $COMPOSE_FILE"

if [[ ! -f "$PREPARED_ENV" ]]; then
  error "llm-prepared-env.sh not found: $PREPARED_ENV"
  exit 1
fi

if [[ ! -x "$PREPARED_ENV" ]]; then
  warn "llm-prepared-env.sh is not executable — fixing..."
  chmod +x "$PREPARED_ENV"
fi
success "llm-prepared-env.sh: $PREPARED_ENV"

# ─────────────────────────────────────────────
# Run prepared-env.sh
# ─────────────────────────────────────────────
section "Environment Preparation"
info "Running llm-prepared-env.sh..."

if bash "$PREPARED_ENV" 2>&1 | tee -a "$LOG_FILE"; then
  success "Environment prepared successfully"
else
  error "llm-prepared-env.sh failed. Aborting."
  exit 1
fi

# ─────────────────────────────────────────────
# Run docker compose
# ─────────────────────────────────────────────
section "Docker Compose"
info "Command: docker compose -f $(basename "$COMPOSE_FILE") ${*:-<no args>}"
log ""

docker compose -f "$COMPOSE_FILE" "$@" 
EXIT_CODE=${PIPESTATUS[0]}

# ─────────────────────────────────────────────
# Result
# ─────────────────────────────────────────────
section "Result"
if [[ $EXIT_CODE -eq 0 ]]; then
  success "Completed successfully"
else
  error "docker compose exited with code $EXIT_CODE"
  exit $EXIT_CODE
fi

# ─────────────────────────────────────────────
# Post-up steps only for "up" command
# ─────────────────────────────────────────────
FIRST_ARG="${1:-}"
if [[ "$FIRST_ARG" != "up" ]]; then
  info "Skipping post-up steps (command was: ${FIRST_ARG:-<none>})"
  exit 0
fi

# ─────────────────────────────────────────────
# Health Check
# ─────────────────────────────────────────────
section "Health Check"
spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
pos=0

until docker exec open-webui curl -s -f http://localhost:8080/health > /dev/null 2>&1; do
    printf "\rWaiting for Open WebUI to become ready... ${spinner[$pos]}  "
    pos=$(( (pos + 1) % 10 ))
    sleep 0.15
done
printf "\r${GREEN}${BOLD}✓${NC} Open WebUI is ready!%*s\n" 50 ""

# ─────────────────────────────────────────────
# Model Import — Smart auto-selection (based on your reference logic)
# ─────────────────────────────────────────────
section "Model Import"

if [[ ! -f "$IMPORT_LLM_MODELS" ]]; then
  error "import-llm-models.sh not found"
  exit 1
fi
if [[ ! -x "$IMPORT_LLM_MODELS" ]]; then
  chmod +x "$IMPORT_LLM_MODELS"
fi
success "Found import-llm-models.sh"

# ───── Scan for .gguf models ─────
echo ""
info "Scanning for .gguf models in: ${IDOL_LLM_MODEL_PATH}"

MODELS=()
if [ -d "$IDOL_LLM_MODEL_PATH" ]; then
  while IFS= read -r -d '' file; do
    MODELS+=("$(basename "$file")")
  done < <(find "$IDOL_LLM_MODEL_PATH" -maxdepth 1 -name "*.gguf" -type f -print0 2>/dev/null | sort -z)
fi

if [ ${#MODELS[@]} -eq 0 ]; then
  warn "No .gguf model files found in ${IDOL_LLM_MODEL_PATH}"
  echo -e "${YELLOW}   You can place .gguf files in this folder and re-run the script.${NC}"
  exit 0
fi

# Display numbered list
echo -e "\n${BOLD}Available models (${#MODELS[@]} found):${NC}"
for i in "${!MODELS[@]}"; do
  printf "  ${CYAN}%2d${NC}) %s\n" $((i+1)) "${MODELS[$i]}"
done

# ── Resolve auto-select target — fallback chain across all three env vars ──
ANSWER_MODEL_TARGET="${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-${IDOL_LLM_MODEL_NAME:-}}"

if [[ -n "$ANSWER_MODEL_TARGET" ]]; then
    info "Auto-select target: \"$ANSWER_MODEL_TARGET\""
else
    info "No answer server model env var set — will prompt manually."
fi

SELECTED=()

# ── Only one model → auto-select ──────────────────────────────────────────
if [[ ${#MODELS[@]} -eq 1 ]]; then
    SELECTED=("${MODELS[@]}")
    success "Only one model available — automatically selected as main."

# ── Env var set → fuzzy match ─────────────────────────────────────────────
elif [[ -n "$ANSWER_MODEL_TARGET" ]]; then
    TARGET="${ANSWER_MODEL_TARGET,,}"
    TARGET_CLEAN="${TARGET//:/_}"
    BEST_IDX=-1
    BEST_SCORE=-1

    for i in "${!MODELS[@]}"; do
        FILE="${MODELS[$i],,}"
        FILE_STEM="${FILE%.gguf}"
        FILE_CLEAN="${FILE_STEM//:/_}"
        SCORE=0

        if [[ "$FILE_STEM" == "$TARGET" ]] || [[ "$FILE_CLEAN" == "$TARGET_CLEAN" ]]; then
            SCORE=100
        elif [[ "$FILE_STEM" == *"$TARGET"* ]] || [[ "$FILE_CLEAN" == *"$TARGET_CLEAN"* ]]; then
            SCORE=80
        elif [[ "$TARGET" == *"$FILE_STEM"* ]] || [[ "$TARGET_CLEAN" == *"$FILE_CLEAN"* ]]; then
            SCORE=70
        else
            IFS='-_: ' read -ra TOKENS <<< "$TARGET"
            MATCHED=0
            TOKEN_TOTAL=${#TOKENS[@]}
            for tok in "${TOKENS[@]}"; do
                [[ ${#tok} -lt 2 ]] && continue
                [[ "$FILE_STEM" == *"$tok"* ]] && (( MATCHED++ )) || true
            done
            if [[ $TOKEN_TOTAL -gt 0 ]]; then
                SCORE=$(( (MATCHED * 60) / TOKEN_TOTAL ))
            fi
        fi

        if [[ $SCORE -gt $BEST_SCORE ]]; then
            BEST_SCORE=$SCORE
            BEST_IDX=$i
        fi
    done

    if [[ $BEST_IDX -ge 0 && $BEST_SCORE -ge 30 ]]; then
        SELECTED=("${MODELS[$BEST_IDX]}")
        success "Auto-selected: \"${ANSWER_MODEL_TARGET}\" → ${MODELS[$BEST_IDX]} ${DIM}(score: ${BEST_SCORE}/100)${NC}"
    else
        warn "No close match for \"${ANSWER_MODEL_TARGET}\" (best score: ${BEST_SCORE}/100) — falling back to manual."
    fi
fi

# ── Fallback: Interactive selection if no auto-selection happened ────────
if [[ ${#SELECTED[@]} -eq 0 ]]; then
    echo ""
    echo -e "${YELLOW}Which model(s) would you like to import?${NC}"
    echo -e "   • Type ${CYAN}all${NC} (or press Enter) → import every model"
    echo -e "   • Numbers separated by comma → e.g. ${CYAN}1,3,5${NC}"
    echo -e "   • Model names separated by comma → e.g. ${CYAN}llama3.gguf,mistral.gguf${NC}"
    echo -e "   • (leave empty = All)${NC}"

    read -r -p "→ Selection: " USER_CHOICE

    # Default to "all" if nothing entered
    USER_CHOICE="${USER_CHOICE:-all}"
    USER_CHOICE=$(echo "$USER_CHOICE" | xargs | tr '[:upper:]' '[:lower:]')

    if [[ "$USER_CHOICE" == "all" || "$USER_CHOICE" == "*" ]]; then
        SELECTED=("${MODELS[@]}")
        info "Importing ALL models..."
    else
        # Parse comma-separated input
        IFS=',' read -ra INPUTS <<< "$USER_CHOICE"

        for item in "${INPUTS[@]}"; do
            item=$(echo "$item" | xargs)

            # Number (e.g. 1, 3)
            if [[ "$item" =~ ^[0-9]+$ ]]; then
                idx=$((item - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#MODELS[@]}" ]; then
                    SELECTED+=("${MODELS[$idx]}")
                else
                    warn "Invalid model number: ${item}"
                fi

            # Model name (with or without .gguf)
            else
                [[ "$item" != *.gguf ]] && item="${item}.gguf"
                # Check if it actually exists
                if printf '%s\n' "${MODELS[@]}" | grep -qx "$item"; then
                    SELECTED+=("$item")
                else
                    warn "Model not found: ${item}"
                fi
            fi
        done
    fi
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
  warn "No valid models selected → skipping import."
  exit 0
fi

# ───── Call the import script ─────
info "Starting import of ${#SELECTED[@]} model(s): ${SELECTED[*]}"

# Pass selected model filenames as arguments
"$IMPORT_LLM_MODELS" "${SELECTED[@]}" && \
  success "✅ Model import completed successfully" || \
  { error "❌ Model import failed"; exit 1; }
