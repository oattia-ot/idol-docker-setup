#!/usr/bin/env bash
# =============================================================================
# ollama-resource-estimator.sh  —  KV‑cache max context calculator + file updater
# FINAL: default-models.json support + strict model validation + updated help
# =============================================================================

set -euo pipefail

# ── Colours (bright & bold) ──────────────────────────────────────────────────
RED='\033[0;91m'; YLW='\033[1;93m'; GRN='\033[0;92m'; BLU='\033[0;94m'
CYN='\033[0;96m'; MGN='\033[0;95m'; BLD='\033[1m'; RST='\033[0m'; YELLOW='\033[1;33m'
DIM='\033[2m'

divider() { echo -e "${CYN}──────────────────────────────────────────────────────${RST}"; }
success() { echo -e "${GRN}${BLD}✅ $*${RST}"; }
info()    { echo -e "${BLU}${BLD}ℹ️  $*${RST}"; }
warn()    { echo -e "${YLW}${BLD}⚠️  $*${RST}"; }
error()   { echo -e "${RED}${BLD}❌ $*${RST}" >&2; }

# =============================================================================
# HELP
# =============================================================================
show_help() {
    echo -e "${BLD}${CYN}"
    cat << 'ASCII'
 ██████╗ █████╗ ███╗ ███╗██████╗ ██████╗████████╗██╗ ██╗
██╔══██╗██╔══██╗████╗ ████║╚════██╗██╔════╝╚══██╔══╝╚██╗██╔╝
██████╔╝███████║██╔████╔██║ █████╔╝██║        ██║    ╚███╔╝
██╔══██╗██╔══██║██║╚██╔╝██║██╔═══╝ ██║        ██║    ██╔██╗
██║  ██║██║  ██║██║ ╚═╝ ██║███████╗╚██████╗   ██║   ██╔╝ ██╗
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ ╚═════╝   ╚═╝   ╚═╝  ╚═╝
ASCII
    echo -e "${RST}"
    echo -e "${BLD}KV-cache Max Context Calculator + Python File Updater${RST}"
    echo ""
    echo -e "${BLD}USAGE${RST}"
    echo -e "  ${YELLOW}./ollama-resource-estimator.sh [OPTIONS] [MODELS_JSON] [PYTHON_FILE]${RST}"
    echo ""
    echo -e "${BLD}ARGUMENTS${RST}"
    echo -e "  ${MGN}MODELS_JSON${RST}        Path to model JSON file (default: ${CYN}default-models.json${RST})"
    echo -e "  ${MGN}PYTHON_FILE${RST}        Python file to update (required with ${MGN}-u${RST})"
    echo ""
    echo -e "${BLD}FLAGS${RST}"
    echo -e "  ${MGN}-h, --help${RST}           Show this help"
    echo -e "  ${MGN}-r, --recommendation${RST} Use standard 16384 ctx (no interactive)"
    echo -e "  ${MGN}-d, --default${RST}        Use safe 4096 ctx (no interactive)"
    echo -e "  ${MGN}-u, --update${RST}         Update PYTHON_FILE (replace marked block)"
    echo -e "  ${MGN}-m, --model NAME${RST}     Target model (must exist in MODELS_JSON)"
    echo ""
    echo -e "${BLD}EXAMPLES${RST}"
    echo -e "${CYN}  # Update with RECOMMENDED (16384) context, using default-models.json${RST}"
    echo -e "  ${YELLOW}./ollama-resource-estimator.sh -m gemma-4-e4b:latest -r -u server.py${RST}"
    echo ""
    echo -e "${CYN}  # Update with DEFAULT (safe 4096) context, using custom models.json${RST}"
    echo -e "  ${YELLOW}./ollama-resource-estimator.sh my_models.json -m llama3:8b -d -u server.py${RST}"
    echo ""
    echo -e "${CYN}  # Estimate max context interactively, then update${RST}"
    echo -e "  ${YELLOW}./ollama-resource-estimator.sh -m gemma-4-e4b:latest -u server.py${RST}"
    echo ""
    echo -e "${CYN}  # Use custom JSON file and model, estimate only (no update)${RST}"
    echo -e "  ${YELLOW}./ollama-resource-estimator.sh models.json -m mixtral:8x7b${RST}"
    echo ""
    echo -e "${BLD}MARKERS FOR PYTHON FILE UPDATE${RST}"
    echo -e "${BLD}${CYN}  The script replaces everything between:"
    echo -e "    ${CYN}# OLLAMA_CONFIG_BEGIN${RST}"
    echo -e "    ${CYN}# OLLAMA_CONFIG_END${RST}"
    echo -e "${MGN}  If markers are missing, the block is appended at the end.${RST}"
    exit 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
VERBOSE=false
JSON_FILE=""
PYTHON_FILE=""
SELECTED_MODEL=""
MODE="full"          # full, recommendation, default
DO_UPDATE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)           show_help ;;
        -r|--recommendation) MODE="recommendation" ;;
        -d|--default)        MODE="default" ;;
        -u|--update)         DO_UPDATE=true ;;
        -m|--model)
            shift
            SELECTED_MODEL="$1"
            ;;
        *)
            if [[ -z "$JSON_FILE" && "$1" == *.json ]]; then
                JSON_FILE="$1"
            elif [[ -z "$PYTHON_FILE" && "$1" == *.py ]]; then
                PYTHON_FILE="$1"
            else
                error "Unrecognized argument: $1"
                exit 1
            fi
            ;;
    esac
    shift
done

# Default JSON file if none provided
if [[ -z "$JSON_FILE" && -n "$SELECTED_MODEL" ]]; then
    JSON_FILE="default-models.json"
    info "No JSON file provided, using default: $JSON_FILE"
fi

# Validate JSON existence (required when -m is used)
if [[ -n "$SELECTED_MODEL" ]]; then
    if [[ ! -f "$JSON_FILE" ]]; then
        error "Model JSON file '$JSON_FILE' not found. Please provide a valid JSON file or create default-models.json."
        exit 1
    fi
fi

if $DO_UPDATE && [[ -z "$PYTHON_FILE" ]]; then
    error "-u/--update requires a Python file to modify"
    echo -e "${YLW}   Example: $0 -m modelname -u server.py${RST}"
    exit 1
fi

if [[ -n "$PYTHON_FILE" && ! -f "$PYTHON_FILE" ]]; then
    error "Python file not found: $PYTHON_FILE"
    exit 1
fi

# =============================================================================
# FUNCTION: Get model info from Ollama (always returns 0, outputs status string)
# =============================================================================
get_model_info_from_ollama() {
    local model="$1"
    if ! command -v ollama &> /dev/null; then
        echo "OLLAMA_NOT_FOUND"
        return 0
    fi
    local output
    output=$(ollama show "$model" --modelfile 2>/dev/null | grep -E "^(parameter|context_length|embedding_length|num_layers|num_kv_heads|head_dim)" || true)
    if [[ -z "$output" ]]; then
        echo "MODEL_NOT_FOUND"
        return 0
    fi
    local ctx_len=$(echo "$output" | grep -i "context_length" | awk '{print $2}')
    local emb_len=$(echo "$output" | grep -i "embedding_length" | awk '{print $2}')
    local num_layers=$(echo "$output" | grep -i "num_layers" | awk '{print $2}')
    local num_kv_heads=$(echo "$output" | grep -i "num_kv_heads" | awk '{print $2}')
    local head_dim=$(echo "$output" | grep -i "head_dim" | awk '{print $2}')
    if [[ -z "$head_dim" ]]; then
        local num_heads=$(echo "$output" | grep -i "num_heads" | awk '{print $2}')
        [[ -n "$num_heads" && -n "$emb_len" ]] && head_dim=$(( emb_len / num_heads ))
    fi
    [[ -z "$ctx_len" ]] && ctx_len=131072
    [[ -z "$emb_len" ]] && emb_len=2560
    [[ -z "$num_layers" ]] && num_layers=36
    [[ -z "$num_kv_heads" ]] && num_kv_heads=8
    [[ -z "$head_dim" ]] && head_dim=$(( emb_len / (num_kv_heads * 2) ))
    echo "CONTEXT_LENGTH=$ctx_len"
    echo "EMBEDDING_LENGTH=$emb_len"
    echo "NUM_LAYERS=$num_layers"
    echo "NUM_KV_HEADS=$num_kv_heads"
    echo "HEAD_DIM=$head_dim"
    return 0
}

# =============================================================================
# LOAD MODEL PARAMETERS
# =============================================================================
# Defaults (gemma-4-e4b:latest)
MODEL_NAME="gemma-4-e4b:latest"
MODEL_WEIGHTS_GB=5.0
MODEL_MAX_CTX=131072
EMBEDDING_LENGTH=2560
ARCHITECTURE="gemma4"
PARAMETER_COUNT="7.5B"
QUANTIZATION="Q4_K_M"
NUM_LAYERS=36
NUM_KV_HEADS=8
HEAD_DIM=128

if [[ -n "$SELECTED_MODEL" ]]; then
    MODEL_NAME="$SELECTED_MODEL"
    if [[ -n "$JSON_FILE" ]]; then
        # Use JSON file – parse with Python (robust, no jq pitfalls)
        if ! command -v python3 &> /dev/null; then
            error "python3 is required for JSON parsing"
            exit 1
        fi
        [[ ! -f "$JSON_FILE" ]] && { error "JSON file not found: $JSON_FILE"; exit 1; }

        # Extract model info using Python (handles BOM, trailing commas, etc.)
        MODEL_JSON=$(python3 << PYTHON_JSON
import sys, json
try:
    with open("$JSON_FILE", 'r', encoding='utf-8-sig') as f:
        data = json.load(f)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

model_name = "$SELECTED_MODEL"
found = None
for model in data.get("supported", []) + data.get("custom_required", []):
    if model.get("name") == model_name or model.get("ollama_info", {}).get("tag") == model_name:
        found = model
        break
if found:
    import json
    print(json.dumps(found))
else:
    print(f"ERROR: Model '{model_name}' not found in JSON", file=sys.stderr)
    sys.exit(1)
PYTHON_JSON
)
        if [[ "$MODEL_JSON" == ERROR:* ]] || [[ -z "$MODEL_JSON" ]]; then
            error "$MODEL_JSON"
            exit 1
        fi
        # Now extract fields from the JSON string using jq (safe now)
        MODEL_WEIGHTS_GB=$(echo "$MODEL_JSON" | jq -r '.size_gb // 5.0')
        MODEL_MAX_CTX=$(echo "$MODEL_JSON" | jq -r '.ollama_info.context_length // 131072')
        EMBEDDING_LENGTH=$(echo "$MODEL_JSON" | jq -r '.ollama_info.embedding_length // 2560')
        ARCHITECTURE=$(echo "$MODEL_JSON" | jq -r '.ollama_info.architecture // "unknown"')
        PARAMETER_COUNT=$(echo "$MODEL_JSON" | jq -r '.ollama_info.parameter_count // "?.?B"')
        QUANTIZATION=$(echo "$MODEL_JSON" | jq -r '.ollama_info.quantization // .recommended_quant // "Q4_K_M"')
        NUM_LAYERS=$(echo "$MODEL_JSON" | jq -r '.ollama_info.num_layers // 36')
        NUM_KV_HEADS=$(echo "$MODEL_JSON" | jq -r '.ollama_info.num_kv_heads // 8')
        HEAD_DIM=$(echo "$MODEL_JSON" | jq -r '.ollama_info.head_dim // empty')
        [[ -z "$HEAD_DIM" || "$HEAD_DIM" == "null" ]] && HEAD_DIM=$(( EMBEDDING_LENGTH / (NUM_KV_HEADS * 2) ))
        info "Loaded model from JSON: $MODEL_NAME"
    fi
fi

# =============================================================================
# COMMON VARIABLES
# =============================================================================
BYTES_PER_ELEMENT=2
OLLAMA_OVERHEAD_GB=1.0
OS_OVERHEAD_GB=4.0

# =============================================================================
# FUNCTION: Generate Python options block as a string
# =============================================================================
generate_python_block() {
    local ctx="$1"
    cat <<EOF
    data = {
        "model":   LLM_MODEL,
        "messages": messages,
        "stream":  False,
        "options": {
            "temperature": 0,
            "num_predict": 512,
            "num_ctx":     ${ctx},
        }
    }
EOF
}

# =============================================================================
# FUNCTION: Replace block in Python file using Python (robust)
# =============================================================================
update_python_block() {
    local file="$1"
    local new_block="$2"
    local start_marker="# OLLAMA_CONFIG_BEGIN"
    local end_marker="# OLLAMA_CONFIG_END"

    python3 <<PYTHON_SCRIPT
import sys

file_path = "$file"
new_block = r"""$new_block"""
start_marker = "$start_marker"
end_marker = "$end_marker"

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
except Exception as e:
    print(f"❌ Failed to read {file_path}: {e}", file=sys.stderr)
    sys.exit(1)

in_block = False
block_found = False
new_lines = []
i = 0
while i < len(lines):
    line = lines[i].rstrip('\n')
    if line.strip() == start_marker.strip():
        in_block = True
        block_found = True
        new_lines.append(line)
        new_lines.append(new_block)
        i += 1
        while i < len(lines) and lines[i].rstrip('\n').strip() != end_marker.strip():
            i += 1
        if i < len(lines):
            new_lines.append(lines[i].rstrip('\n'))
        else:
            new_lines.append(end_marker)
        in_block = False
        i += 1
        continue
    if not in_block:
        new_lines.append(line)
    i += 1

if not block_found:
    new_lines.append("")
    new_lines.append(start_marker)
    new_lines.append(new_block)
    new_lines.append(end_marker)
    print(f"⚠️  Markers not found – appended block at end of {file_path}", file=sys.stderr)
else:
    print(f"✅ Replaced block between markers in {file_path}", file=sys.stderr)

try:
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(new_lines))
        if new_lines and new_lines[-1] != '':
            f.write('\n')
except Exception as e:
    print(f"❌ Failed to write {file_path}: {e}", file=sys.stderr)
    sys.exit(1)

print(f"✅ Successfully updated {file_path}", file=sys.stderr)
PYTHON_SCRIPT
}

# =============================================================================
# QUICK OUTPUT MODES (no interactive, no system query)
# =============================================================================
if [[ "$MODE" == "recommendation" || "$MODE" == "default" ]]; then
    if [[ "$MODE" == "recommendation" ]]; then
        CTX_VAL=16384
        info "Using RECOMMENDED context length: 16384"
    else
        CTX_VAL=4096
        info "Using DEFAULT (safe) context length: 4096"
    fi
    BLOCK=$(generate_python_block "$CTX_VAL")
    echo -e "${MGN}$BLOCK${RST}"
    if $DO_UPDATE; then
        update_python_block "$PYTHON_FILE" "$BLOCK"
    fi
    exit 0
fi

# =============================================================================
# FULL CALCULATION MODE (interactive, estimates based on system RAM)
# =============================================================================
echo -e "${BLD}${CYN}🔍  Querying system resources…${RST}"
divider

OS="$(uname -s)"
if [[ "$OS" == "Darwin" ]]; then
    TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
else
    TOTAL_RAM_BYTES=$(awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo)
fi
TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM_BYTES / 1073741824" | bc)

CPU_CORES=$(nproc --all 2>/dev/null || echo "unknown")
GPU_NAME="None detected"
GPU_VRAM_GB=0
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    GPU_VRAM_GB=$(echo "scale=2; $GPU_VRAM_MB / 1024" | bc)
fi

echo -e "  ${BLD}Total RAM     :${RST} ${TOTAL_RAM_GB} GB"
echo -e "  ${BLD}CPU Cores     :${RST} $CPU_CORES"
echo -e "  ${BLD}GPU           :${RST} $GPU_NAME"

# KV cache per token
divider
echo -e "${BLD}🧮  KV Cache per token${RST}"
divider
KV_PER_TOKEN_BYTES=$(echo "$NUM_LAYERS * $NUM_KV_HEADS * $HEAD_DIM * $BYTES_PER_ELEMENT * 2" | bc)
echo "  $KV_PER_TOKEN_BYTES bytes/token"

# Memory budget
divider
echo -e "${BLD}💾  Memory Budget${RST}"
divider
RESERVED_GB=$(echo "scale=2; $OS_OVERHEAD_GB + $MODEL_WEIGHTS_GB + $OLLAMA_OVERHEAD_GB" | bc)
AVAILABLE_FOR_KV=$(echo "scale=2; $TOTAL_RAM_GB - $RESERVED_GB" | bc)
if (( $(echo "$GPU_VRAM_GB >= $MODEL_WEIGHTS_GB" | bc -l) )); then
    AVAILABLE_FOR_KV=$(echo "scale=2; $TOTAL_RAM_GB - $OS_OVERHEAD_GB - $OLLAMA_OVERHEAD_GB" | bc)
fi
echo -e "  ${BLD}Available for KV cache:${RST} ${AVAILABLE_FOR_KV} GB"

# Max context possible
divider
echo -e "${BLD}📐  Max Context Length${RST}"
divider
AVAILABLE_FOR_KV_BYTES=$(echo "$AVAILABLE_FOR_KV * 1073741824" | bc | cut -d. -f1)
MAX_CTX_RAW=$(echo "$AVAILABLE_FOR_KV_BYTES / $KV_PER_TOKEN_BYTES" | bc)

if (( MAX_CTX_RAW > MODEL_MAX_CTX )); then
    MAX_CTX=$MODEL_MAX_CTX
    CTX_NOTE="(capped by model: $MODEL_MAX_CTX)"
else
    MAX_CTX=$MAX_CTX_RAW
    CTX_NOTE="(RAM-limited)"
fi
echo -e "  Raw max tokens: ${MAX_CTX_RAW}"
echo -e "  ${BLD}${GRN}Effective max : ${MAX_CTX} tokens ${CTX_NOTE}${RST}"

# Interactive selection (default if no -r/-d and not in update mode)
if $DO_UPDATE; then
    CHOSEN_CTX=$MAX_CTX
    info "Update mode: automatically using max possible context = $CHOSEN_CTX"
else
    divider
    echo -e "${BLD}🎯  Available num_ctx Options${RST}"
    divider
    declare -a TIERS=(
        "Minimal  | 4096"
        "Standard | 16384"
        "Extended | 32768"
        "Large    | 65536"
        "XLarge   | 98304"
        "Maximum  | $MODEL_MAX_CTX"
    )
    FITTING_CTXS=()
    OPTION_NUM=1
    for tier in "${TIERS[@]}"; do
        IFS='|' read -r label ctx <<< "$tier"
        ctx=$(echo "$ctx" | xargs)
        if (( ctx <= MAX_CTX )); then
            echo -e "  ${CYN}${OPTION_NUM}.${RST} $label → ${CYN}${ctx}${RST}"
            FITTING_CTXS+=("$ctx")
            ((OPTION_NUM++))
        fi
    done
    echo ""
    read -rp "  Choose number or enter custom ctx [default $MAX_CTX]: " USER_INPUT
    if [[ -z "$USER_INPUT" ]]; then
        CHOSEN_CTX=$MAX_CTX
    elif [[ "$USER_INPUT" =~ ^[0-9]+$ ]] && (( USER_INPUT >= 1 && USER_INPUT < OPTION_NUM )); then
        CHOSEN_CTX=${FITTING_CTXS[$((USER_INPUT-1))]}
    else
        CHOSEN_CTX=$USER_INPUT
        (( CHOSEN_CTX > MODEL_MAX_CTX )) && CHOSEN_CTX=$MODEL_MAX_CTX
    fi
    echo -e "${GRN}✅ Using num_ctx = $CHOSEN_CTX${RST}"
fi

# Generate final block
BLOCK=$(generate_python_block "$CHOSEN_CTX")
divider
echo -e "${BLD}🐍  Generated Python block${RST}"
divider
echo "$BLOCK"
divider

# If update mode, write to file
if $DO_UPDATE; then
    update_python_block "$PYTHON_FILE" "$BLOCK"
fi

divider
echo -e "${DIM}Tip: Use -r for standard 16384, -d for safe 4096, -u to update a Python file.${RST}"
divider