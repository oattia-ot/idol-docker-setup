#!/bin/bash
# =============================================================================
# Ollama GGUF Validator (simplified)
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; NC='\033[0m'

# --- Usage / help ---
print_usage() {
    echo -e "${BOLD}${BLUE}Ollama GGUF Validator${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC} $0 [-h|--help]"
    echo ""
    echo "Scans a folder of .gguf files, validates each one loads in Ollama,"
    echo "and reports the hardware placement (GPU/CPU) each model would need."
    echo ""
    echo -e "${BOLD}GPU column legend:${NC}"

    # Pad the label first (plain text) so color codes don't throw off alignment,
    # then wrap the already-padded label in color.
    legend_row() {
        local color="$1" label="$2" desc="$3"
        printf "  %b %s\n" "${color}$(printf '%-16s' "$label")${NC}" "$desc"
    }

    legend_row "$GREEN"  "GPU only"        "Model fits in ~90% of VRAM (headroom reserved for context) — fully GPU-resident"
    legend_row "$CYAN"   "GPU+CPU split"   "Doesn't fit in VRAM alone, but VRAM + available RAM covers it — this is how"
    legend_row "$NC"     ""                "Ollama/llama.cpp actually run oversized models (partial layer offload)"
    legend_row "$BLUE"   "CPU only"        "No GPU detected at all, and RAM is sufficient"
    legend_row "$YELLOW" "CPU fallback"    "GPU exists but is too small to help meaningfully (model needs RAM"
    legend_row "$NC"     ""                "regardless), falls back to CPU+RAM"
    legend_row "$RED"    "Insufficient HW" "Neither VRAM+RAM nor RAM alone is enough to run this model"

    echo ""
    echo -e "${BOLD}Environment:${NC}"
    echo -e "  ${CYAN}IDOL_LLM_MODEL_PATH${NC}   Default models folder (falls back to ./llm_models)"
    echo ""
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    print_usage
    exit 0
fi

clear
echo -e "${BLUE}== Ollama GGUF Validator + Hardware Requirements ==${NC}"
echo ""

# --- Check Ollama is installed and reachable BEFORE doing anything else ---
check_ollama() {
    if ! command -v ollama &>/dev/null; then
        echo -e "${RED}Error: 'ollama' command not found.${NC}"
        echo "Install it from https://ollama.com/download, then re-run this script."
        exit 1
    fi

    # ollama list talks to the local daemon; if it's not running this fails fast
    if ! ollama list &>/dev/null; then
        echo -e "${RED}Error: Ollama is installed but the Ollama service isn't reachable.${NC}"
        echo "Start it with 'ollama serve' (or check 'systemctl status ollama'), then re-run this script."
        exit 1
    fi
}
check_ollama

# --- Directory ---
# Default comes from $IDOL_LLM_MODEL_PATH if set, otherwise <current dir>/llm_models
DEFAULT_MODELS_DIR="${IDOL_LLM_MODEL_PATH:-$(pwd)/llm_models}"
read -p "$(echo -e "${YELLOW}Path to your Ollama models folder${NC} [${DEFAULT_MODELS_DIR}]: ")" MODELS_DIR
MODELS_DIR=${MODELS_DIR:-$DEFAULT_MODELS_DIR}
echo -e "Using: ${CYAN}${MODELS_DIR}${NC}"
echo ""

if [ ! -d "$MODELS_DIR" ]; then
    echo -e "${RED}Directory not found.${NC}"
    exit 1
fi

# --- Hardware detection ---
echo -e "${YELLOW}Detecting hardware...${NC}"
AVAILABLE_RAM_GB=$(free -m | awk '/Mem:/ {printf "%.1f", $7/1024}')
TOTAL_RAM_GB=$(free -m | awk '/Mem:/ {printf "%.1f", $2/1024}')

GPU_TYPE="None"
GPU_INFO=""
GPU_VRAM_GB=0   # 0 means "no GPU / VRAM unknown" -> treated as CPU-only

if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ -n "$GPU_NAME" ]; then
        GPU_TYPE="NVIDIA"
        GPU_VRAM_GB=$(awk "BEGIN { printf \"%.1f\", ${GPU_VRAM_MB:-0} / 1024 }")
        GPU_INFO="$GPU_NAME (${GPU_VRAM_GB} GB VRAM)"
    fi
elif command -v rocm-smi &>/dev/null; then
    # Best-effort VRAM read for AMD; falls back to "unknown" if the output format differs
    GPU_VRAM_MB=$(rocm-smi --showmeminfo vram 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)
    if [ -n "$GPU_VRAM_MB" ]; then
        GPU_TYPE="AMD"
        GPU_VRAM_GB=$(awk "BEGIN { printf \"%.1f\", ${GPU_VRAM_MB:-0} / 1024 }")
        GPU_INFO="AMD ROCm GPU (${GPU_VRAM_GB} GB VRAM)"
    else
        GPU_TYPE="AMD"
        GPU_VRAM_GB=0
        GPU_INFO="AMD ROCm GPU (VRAM unknown)"
    fi
fi

echo -e "  RAM: ${AVAILABLE_RAM_GB} GB available / ${TOTAL_RAM_GB} GB total"
if [ "$GPU_TYPE" != "None" ]; then
    echo -e "  GPU: ${GREEN}${GPU_INFO}${NC}"
else
    echo -e "  GPU: ${YELLOW}None detected (CPU only)${NC}"
fi
echo ""

# --- Pre-flight cleanup: clear stale state that skews warmup timing ---
# This fixes the "valid but slow" vs "valid + OK" inconsistency between runs by
# making each run start from the same clean state instead of whatever was left
# over (models still loaded in RAM/VRAM, leftover temp models, background load).
cleanup_environment() {
    echo -e "${YELLOW}Cleaning up environment before validation...${NC}"

    # 1) Unload any models Ollama currently has resident in RAM/VRAM.
    #    A model left loaded from a previous session can hold GPU memory and
    #    make the next model's warmup look "slow" simply because there's no
    #    room/bandwidth left for it.
    local loaded
    loaded=$(ollama ps 2>/dev/null | awk 'NR>1 {print $1}')
    if [ -n "$loaded" ]; then
        while IFS= read -r m; do
            [ -z "$m" ] && continue
            ollama stop "$m" >/dev/null 2>&1
            echo -e "  ${CYAN}Unloaded resident model: $m${NC}"
        done <<< "$loaded"
    fi

    # 2) Remove leftover verify-* temp models from a previous interrupted run.
    local stale
    stale=$(ollama list 2>/dev/null | awk '$1 ~ /^verify-/ {print $1}')
    if [ -n "$stale" ]; then
        while IFS= read -r m; do
            [ -z "$m" ] && continue
            ollama rm "$m" >/dev/null 2>&1
            echo -e "  ${CYAN}Removed stale temp model: $m${NC}"
        done <<< "$stale"
    fi

    # 3) Report current system load so the user knows whether something else
    #    on the box is competing for CPU/disk right now. We can't force other
    #    processes off the machine, but we surface it instead of silently
    #    blaming the model.
    if command -v uptime &>/dev/null; then
        local load
        load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
        echo -e "  ${CYAN}System load average (1/5/15 min): ${load}${NC}"
    fi

    # 4) Report GPU memory state so a "slow" result caused by another process
    #    holding VRAM is visible rather than silent.
    if [ "$GPU_TYPE" = "NVIDIA" ] && command -v nvidia-smi &>/dev/null; then
        local gpu_used gpu_total
        gpu_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
        gpu_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        echo -e "  ${CYAN}GPU VRAM in use: ${gpu_used} MB / ${gpu_total} MB${NC}"
    fi

    echo ""
}
cleanup_environment

# Pre-warm a file's pages into the OS disk cache before we time its load.
# A cold read from disk (page cache miss) is the most common reason the same
# model shows "Valid (warmup slow)" one day and "Valid + warmup OK" the next
# — this makes every run start from a warm cache so results are consistent.
warm_disk_cache() {
    local f="$1"
    dd if="$f" of=/dev/null bs=4M status=none 2>/dev/null
}

# --- Find GGUF files ---
mapfile -t GGUF_FILES < <(find "$MODELS_DIR" -maxdepth 1 -name "*.gguf" -type f | sort)

if [ ${#GGUF_FILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}No .gguf files found.${NC}"
    exit 0
fi

echo -e "${MAGENTA}Found ${#GGUF_FILES[@]} .gguf file(s). Validating...${NC}"
echo ""

# --- Simple spinner ---
SPIN_PID=""
start_spinner() {
    local name="$1"
    ( while true; do
        for c in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
            printf "\r  ${CYAN}[%s] Validating %s (large models can take a while)...${NC} " "$c" "$name"
            sleep 0.12
        done
      done ) &
    SPIN_PID=$!
    disown
}
stop_spinner() {
    [ -n "$SPIN_PID" ] && kill "$SPIN_PID" 2>/dev/null
    wait "$SPIN_PID" 2>/dev/null
    SPIN_PID=""
    printf "\r%100s\r" " "
}

# --- Table header ---
ROW_FMT="%-40s %8s %8s %-14s %b\n"
printf "${BOLD}${ROW_FMT}${NC}" "FILENAME" "SIZE GB" "MIN RAM" "GPU" "STATUS"

declare -a VALID_FILES=()
declare -a INVALID_FILES=()

for file in "${GGUF_FILES[@]}"; do
    FILENAME=$(basename "$file")
    SIZE_BYTES=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
    SIZE_GB=$(awk "BEGIN { printf \"%.2f\", $SIZE_BYTES / 1024/1024/1024 }")
    MIN_RAM=$(awk "BEGIN { printf \"%.1f\", ($SIZE_GB * 1.4) + 3.0 }")

    # --- Compute placement: figure out whether this model fits entirely on
    # the GPU, needs to split across GPU+CPU (partial layer offload, which is
    # how Ollama/llama.cpp actually run oversized models), or has to run on
    # CPU alone — either because there's no GPU, or the GPU is too small to
    # help meaningfully and the system falls back to CPU+RAM.
    GPU_REC=$(awk -v size="$SIZE_GB" -v vram="$GPU_VRAM_GB" -v ram="$AVAILABLE_RAM_GB" -v has_gpu="$([ "$GPU_TYPE" != "None" ] && echo 1 || echo 0)" '
        BEGIN {
            if (has_gpu != 1 || vram <= 0) {
                # No GPU at all, or VRAM unknown -> CPU is the only option
                if (ram >= size * 1.4 + 3.0) print "CPU only"
                else print "CPU (tight RAM)"
                exit
            }
            # Leave ~10% VRAM headroom for context/runtime overhead
            usable_vram = vram * 0.9
            if (size <= usable_vram) {
                print "GPU only"
            } else if (size <= usable_vram + ram) {
                # Doesnt fully fit in VRAM, but GPU+CPU layer split can cover it
                print "GPU+CPU split"
            } else if (ram >= size * 1.4 + 3.0) {
                # Too big to meaningfully use the GPU; fall back to CPU+RAM
                print "CPU fallback"
            } else {
                print "Insufficient HW"
            }
        }'
    )

    # Magic byte check
    if [[ "$(head -c 4 "$file")" != "GGUF" ]]; then
        printf "$ROW_FMT" "$FILENAME" "$SIZE_GB" "$MIN_RAM" "$GPU_REC" "${RED}INVALID (bad header)${NC}"
        INVALID_FILES+=("$file")
        continue
    fi

    SAFE_NAME=$(basename "$file" .gguf | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
    TEMP_MODEL="verify-${SAFE_NAME}"

    start_spinner "$FILENAME (warming cache)"
    warm_disk_cache "$file"
    stop_spinner

    start_spinner "$FILENAME"
    timeout 180 ollama create "$TEMP_MODEL" -f <(echo "FROM $file") >/dev/null 2>&1
    CREATE_EXIT=$?

    if [ $CREATE_EXIT -eq 0 ]; then
        if timeout 25 ollama run "$TEMP_MODEL" "Hi" --nowordwrap >/dev/null 2>&1; then
            STATUS="${GREEN}Valid + warmup OK${NC}"
        else
            STATUS="${YELLOW}Valid (warmup slow)${NC}"
        fi
        VALID_FILES+=("$file")
    else
        STATUS="${RED}INVALID (failed to load)${NC}"
        INVALID_FILES+=("$file")
    fi
    # Stop (unload from RAM/VRAM) before removing, so the next file in the
    # loop starts from a clean memory state instead of inheriting this one.
    ollama stop "$TEMP_MODEL" >/dev/null 2>&1
    ollama rm "$TEMP_MODEL" >/dev/null 2>&1
    stop_spinner

    printf "$ROW_FMT" "$FILENAME" "$SIZE_GB" "$MIN_RAM" "$GPU_REC" "$STATUS"
done

echo ""
echo -e "${BLUE}== Summary ==${NC}"
echo -e "  ${GREEN}Valid:   ${#VALID_FILES[@]}${NC}"
echo -e "  ${RED}Invalid: ${#INVALID_FILES[@]}${NC}"
echo ""

if [ "$GPU_TYPE" != "None" ]; then
    echo -e "${GREEN}GPU acceleration available — recommended for models under ~30 GB.${NC}"
else
    echo -e "${YELLOW}No GPU detected — models will run on CPU only (slower).${NC}"
fi
echo ""

if [ ${#INVALID_FILES[@]} -gt 0 ]; then
    echo -e "${RED}Invalid files:${NC}"
    for bad in "${INVALID_FILES[@]}"; do
        echo "  - $(basename "$bad")"
    done
    echo ""
    read -p "Delete ALL invalid files now? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        for bad in "${INVALID_FILES[@]}"; do
            rm -f "$bad" && echo -e "  ${RED}Deleted: $(basename "$bad")${NC}"
        done
    fi
else
    echo -e "${GREEN}All files passed validation.${NC}"
fi

echo ""
echo -e "${BLUE}Done.${NC}"