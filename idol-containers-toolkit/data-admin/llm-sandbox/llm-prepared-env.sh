#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# Resolve script location
# ─────────────────────────────────────────────
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOCK_FILE="/tmp/update-models.lock"

# ─────────────────────────────────────────────
# Color codes
# ─────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'

# ─────────────────────────────────────────────
# Initialize RAW_LOG early
# ─────────────────────────────────────────────
RAW_LOG="/dev/null"

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
log()     { echo -e "$1" | tee -a "${RAW_LOG:-/dev/null}" 2>/dev/null || true; }
info()    { log "${CYAN}[INFO]${NC}  $1"; }
success() { log "${GREEN}[OK]${NC}    $1"; }
warn()    { log "${YELLOW}[WARN]${NC}  $1"; }
error()   { log "${RED}[ERROR]${NC} $1"; }
section() { log "\n${BOLD}${BLUE}── $1 ──${NC}"; }

human_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        du -sh "$file" 2>/dev/null | cut -f1
    else
        echo "N/A"
    fi
}

# ─────────────────────────────────────────────
# FORCE CLEAN STALE LOCK (extra safety)
# ─────────────────────────────────────────────
if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$LOCK_PID" ]] && ! ps -p "$LOCK_PID" > /dev/null 2>&1; then
        warn "Removing definitely stale lock (PID $LOCK_PID is gone)."
        rm -f "$LOCK_FILE"
    fi
fi

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────
if [[ -z "${IDOL_LLM_MODEL_PATH:-}" ]]; then
    echo -e "${RED}[ERROR]${NC} IDOL_LLM_MODEL_PATH is empty or not set."
    exit 1
fi

echo -e "${CYAN}[DEBUG]${NC} IDOL_LLM_MODEL_PATH → ${IDOL_LLM_MODEL_PATH}"

# ─────────────────────────────────────────────
# AUTOMATIC LOCK GUARD (enhanced)
# ─────────────────────────────────────────────
LOCK_FILE="/tmp/update-models.lock"
FORCE_LOCK=0

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --force|-f)
            FORCE_LOCK=1
            shift
            ;;
        *)
            ;;
    esac
done

if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    
    # Check if lock is stale (process not running OR older than 1 hour)
    LOCK_AGE=0
    if [[ -n "$LOCK_PID" ]]; then
        if [[ "$(uname)" == "Linux" ]]; then
            LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
        else
            # macOS fallback
            LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0) ))
        fi
    fi
    
    PROCESS_RUNNING=false
    if [[ -n "$LOCK_PID" ]] && ps -p "$LOCK_PID" > /dev/null 2>&1; then
        PROCESS_RUNNING=true
    fi
    
    if $PROCESS_RUNNING && [[ $LOCK_AGE -lt 3600 ]] && [[ $FORCE_LOCK -eq 0 ]]; then
        error "${RED}Another instance is already running ${BOLD}(PID: $LOCK_PID, lock: $LOCK_FILE)."
        error "${RED}Use ${BOLD}[ ./llm-sandbox/llm-prepared-env.sh --force ]${RED} to override (dangerous, may corrupt downloads). Exiting.${NC}"
        exit 1
    else
        if $PROCESS_RUNNING && [[ $LOCK_AGE -ge 3600 ]]; then
            warn "Lock file is older than 1 hour (PID: $LOCK_PID still running?). Removing stale lock."
        elif ! $PROCESS_RUNNING; then
            warn "Stale lock file found (old PID: $LOCK_PID is not running). Removing it."
        elif [[ $FORCE_LOCK -eq 1 ]]; then
            warn "Force flag set — removing existing lock file even though process may be running."
        fi
        rm -f "$LOCK_FILE"
        success "Lock cleaned — continuing."
    fi
fi

# Create fresh lock
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE" 2>/dev/null || true' EXIT INT TERM

# ─────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="${SCRIPT_DIR}/logs/update-models-${TIMESTAMP}.log"
mkdir -p "$(dirname "$LOG_FILE")"
RAW_LOG="${LOG_FILE}.raw"
exec > >(tee -a "$RAW_LOG") 2>&1

FAILED=0
SKIPPED=0
DOWNLOADED=0

# ─────────────────────────────────────────────
# Parse models
# ─────────────────────────────────────────────
declare -a MODEL_NAMES=()
declare -a MODEL_URLS=()

if [[ -n "${IDOL_LLM_MODEL_SELECTION:-}" && -n "${IDOL_LLM_MODEL_URL:-}" ]]; then
    IFS=',' read -ra MODEL_NAMES <<< "$IDOL_LLM_MODEL_SELECTION"
    IFS=',' read -ra MODEL_URLS <<< "$IDOL_LLM_MODEL_URL"
    if [[ ${#MODEL_NAMES[@]} -ne ${#MODEL_URLS[@]} ]]; then
        echo -e "${RED}[ERROR]${NC} Number of model names does not match number of URLs."
        exit 1
    fi
elif [[ -n "${IDOL_LLM_MODEL_NAME:-}" && -n "${IDOL_LLM_MODEL_URL:-}" ]]; then
    MODEL_NAMES=("$IDOL_LLM_MODEL_NAME")
    MODEL_URLS=("$IDOL_LLM_MODEL_URL")
else
    echo -e "${RED}[ERROR]${NC} No LLM model(s) was selected [IDOL_LLM_MODEL_SELECTION = ${IDOL_LLM_MODEL_SELECTION:-Empty}]."
    exit 1
fi

declare -a MODELS=()
for i in "${!MODEL_NAMES[@]}"; do
    MODELS+=("${MODEL_NAMES[$i]}|${MODEL_URLS[$i]}")
done

# ─────────────────────────────────────────────
# DOWNLOAD FUNCTION
# ─────────────────────────────────────────────
download_with_progress() {
    local url="$1"
    local output="$2"
    local name="$3"
    local total="${4:-1}"
    local current="${5:-1}"

    printf "\033[2K${CYAN}[DOWNLOAD]${NC} ${BOLD}[${current}/${total}]${NC} %s ...\n" "$name" > /dev/tty

    local total_size
    total_size=$(curl -sI -L --max-redirs 10 --fail -H "Accept: */*" "$url" 2>/dev/null \
                 | grep -i '^content-length:' | awk '{print $2}' | tr -d '\r' || echo "0")
    [[ "$total_size" =~ ^[0-9]+$ ]] || total_size=0

    curl -L --fail -s -o "$output" "$url" &
    local curl_pid=$!

    sleep 1.2

    local bar_width=20
    local spinner=('-' '\\' '|' '/')
    local spin_idx=0

    bytes_to_human() {
        local b=$1
        if [[ $b -ge 1073741824 ]]; then printf "%.1f GB" "$(awk "BEGIN {print $b/1073741824}")"
        elif [[ $b -ge 1048576 ]];   then printf "%.1f MB" "$(awk "BEGIN {print $b/1048576}")"
        elif [[ $b -ge 1024 ]];      then printf "%.1f KB" "$(awk "BEGIN {print $b/1024}")"
        else printf "%d B" "$b"; fi
    }

    while kill -0 "$curl_pid" 2>/dev/null; do
        sleep 0.35

        local current_size=0
        if [[ -f "$output" ]]; then
            current_size=$(wc -c < "$output" 2>/dev/null || echo "0")
        fi
        [[ "$current_size" =~ ^[0-9]+$ ]] || current_size=0

        local human_current=$(bytes_to_human "$current_size")
        local human_total="???"
        [[ $total_size -gt 0 ]] && human_total=$(bytes_to_human "$total_size")

        printf "\033[1A\033[2K${CYAN}[DOWNLOAD]${NC} ${BOLD}[${current}/${total}]${NC} %s ... " "$name" > /dev/tty

        if [[ $total_size -gt 0 ]]; then
            local percent=$(( (current_size * 100) / total_size ))
            (( percent > 100 )) && percent=100
            local filled=$(( percent * bar_width / 100 ))
            local bar="" empty="" i
            for ((i=0; i<filled; i++));          do bar="${bar}█";  done
            for ((i=filled; i<bar_width; i++));  do empty="${empty}░"; done
            printf "${ORANGE}%s%s${NC} %3d%% ${GRAY}(%s / %s)${NC}\n" \
                "$bar" "$empty" "$percent" "$human_current" "$human_total" > /dev/tty
        else
            printf "${ORANGE}%s${NC} %s\n" "${spinner[spin_idx]}" "$human_current" > /dev/tty
            spin_idx=$(( (spin_idx + 1) % 4 ))
        fi
    done

    wait "$curl_pid"
    local curl_status=$?

    printf "\033[1A\033[2K" > /dev/tty

    if [[ $curl_status -eq 0 ]]; then
        printf "${CYAN}[DOWNLOAD]${NC} ${BOLD}[${current}/${total}]${NC} %s ... ${GREEN}████████████████████ 100%% ✓ Done${NC}\n" "$name" > /dev/tty
        return 0
    else
        printf "${CYAN}[DOWNLOAD]${NC} ${BOLD}[${current}/${total}]${NC} %s ... ${RED}✗ Failed${NC}\n" "$name" > /dev/tty
        return 1
    fi
}

# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────
section "Setup"
mkdir -p "$IDOL_LLM_MODEL_PATH"

info "Script dir     : $SCRIPT_DIR"
info "Model directory: $IDOL_LLM_MODEL_PATH"
info "Log file       : $LOG_FILE"

# ─────────────────────────────────────────────
# Download
# ─────────────────────────────────────────────
section "Downloading Models"

for i in "${!MODELS[@]}"; do
    entry="${MODELS[$i]}"
    FILENAME="${entry%%|*}"
    URL="${entry##*|}"
    FILENAME="${FILENAME%.gguf}.gguf"
    FINAL_FILE="$IDOL_LLM_MODEL_PATH/$FILENAME"

    if [[ -f "$FINAL_FILE" ]]; then
        SIZE=$(human_size "$FINAL_FILE")
        warn "Model already exists at: $FINAL_FILE ($SIZE)"
        echo -e "${BOLD}Overwrite or use existing?${NC}" > /dev/tty
        echo -e "  ${CYAN}[1]${NC} Use existing (skip download)" > /dev/tty
        echo -e "  ${CYAN}[2]${NC} Overwrite (re-download)" > /dev/tty
        read -r -p "Choice [1/2]: " CHOICE < /dev/tty

        case "$CHOICE" in
            2)
                info "Overwrite selected — removing existing file..."
                rm -f "$FINAL_FILE"
                ;;
            *)
                success "Using existing model: $FILENAME ($SIZE)"
                (( SKIPPED++ )) || true
                continue
                ;;
        esac
    fi

    if download_with_progress "$URL" "$FINAL_FILE" "$FILENAME" "${#MODELS[@]}" "$((i+1))"; then
        SIZE=$(human_size "$FINAL_FILE")
        success "Downloaded: $FILENAME ($SIZE)"
        (( DOWNLOADED++ )) || true
    else
        error "Failed to download: $FILENAME"
        rm -f "$FINAL_FILE" 2>/dev/null || true
        (( FAILED++ )) || true
    fi
done

# ─────────────────────────────────────────────
# Download Summary
# ─────────────────────────────────────────────
section "Download Summary"
TOTAL=${#MODELS[@]}
log "  Total models  : ${BOLD}$TOTAL${NC}"
log "  Downloaded    : ${GREEN}${BOLD}$DOWNLOADED${NC}"
log "  Skipped       : ${YELLOW}${BOLD}$SKIPPED${NC}"
log "  Failed        : ${RED}${BOLD}$FAILED${NC}"
log ""

if [[ $FAILED -gt 0 ]]; then
    error "$FAILED model(s) failed. Check log: $LOG_FILE"
    exit 1
fi

# ─────────────────────────────────────────────
# Set Main Model directly from Environment Variables
# (non-interactive — uses IDOL_LLM_MODEL_NAME + IDOL_LLM_MODEL_PATH)
# ─────────────────────────────────────────────
section "Setting Main Model for AnswerBank"

if [[ -z "${IDOL_LLM_MODEL_NAME:-}" ]]; then
    error "IDOL_LLM_MODEL_NAME is not set. Cannot determine main model for AnswerBank."
    exit 1
fi

if [[ -z "${IDOL_LLM_MODEL_PATH:-}" ]]; then
    error "IDOL_LLM_MODEL_PATH is not set."
    exit 1
fi

MAIN_MODEL="${IDOL_LLM_MODEL_NAME}"

# Build full path to the .gguf file (append .gguf if the name doesn't already have it)
if [[ "$MAIN_MODEL" == *.gguf ]]; then
    MAIN_MODEL_FILE="${IDOL_LLM_MODEL_PATH}/${MAIN_MODEL}"
else
    MAIN_MODEL_FILE="${IDOL_LLM_MODEL_PATH}/${MAIN_MODEL}.gguf"
fi

# Verify the file actually exists
if [[ ! -f "$MAIN_MODEL_FILE" ]]; then
    error "Main model file does not exist: $MAIN_MODEL_FILE"
    error "Make sure the model was downloaded successfully in the previous step."
    exit 1
fi

success "Main model configured from environment variables:"
info "  IDOL_LLM_MAIN_MODEL_NAME = $MAIN_MODEL"
info "  IDOL_LLM_MAIN_MODEL_PATH = $MAIN_MODEL_FILE"


# ─────────────────────────────────────────────
# Save main model config
# ─────────────────────────────────────────────
CONFIG_DIR="${SCRIPT_DIR}/config"
mkdir -p "$CONFIG_DIR"
MAIN_MODEL_CONFIG="$CONFIG_DIR/main_model.conf"

cat > "$MAIN_MODEL_CONFIG" <<EOF
# Main LLM model for IDOL AnswerBank integration
# Generated on $(date)
IDOL_LLM_MAIN_MODEL_NAME="$MAIN_MODEL"
IDOL_LLM_MAIN_MODEL_PATH="$MAIN_MODEL_FILE"
EOF

success "Main model configuration saved to: $MAIN_MODEL_CONFIG"
echo -e "${CYAN}You can source this file:${NC} source $MAIN_MODEL_CONFIG"

section "Done"
success "${GREEN}All models processed. Main model for AnswerBank: ${ORANGE}$MAIN_MODEL ($MAIN_MODEL_FILE)${NC}"
exit 0