#!/bin/bash
# import-llm-models.sh - v5.6.0 (Pre-load with robust dummy-prompt + clearer fallback)
#
# Key improvements in v5.6.0:
#   • Pre-load now uses a short dummy prompt + NO --keep-alive flag.
#     This reliably loads the model into memory on ANY Ollama version
#     and avoids "unknown flag: --keep-alive" errors.
#   • Much clearer pre-load failure messages with possible causes + suggestions.
#   • Fallback model selector now shows richer info (size + age) from `ollama list`.
#   • Added note explaining that only *imported* models appear in the list
#     (the initial 7 are .gguf files on disk, not yet registered in Ollama).
#   • Minor robustness & comment updates.
#
# v5.5.1 (previous):
#   • Removed stray heredoc that caused syntax errors.
#   • Pre-load redirects stdin from /dev/null.
#
# Core behavior preserved:
#   - Imports .gguf via Modelfile into Ollama (docker exec only)
#   - Auto smart-match or interactive choice for IDOL_ANSWERSERVER_LLM_MODEL_NAME
#   - Pre-load after create (with interactive fallback on failure)
#   - Full non-interactive / CI support
#   - GGUF corruption detection

# ─────────────────────────────────────────────
# Color codes
# ─────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
ORANGE='\033[0;38;5;214m'
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
║                LLM Model Importer (Ollama) v5.6.0                ║
╚══════════════════════════════════════════════════════════════════╝${NC}

${BOLD}SYNOPSIS${NC}
    $(basename "$0") [OPTIONS] [MODEL1.gguf] [MODEL2.gguf] ...

${BOLD}DESCRIPTION${NC}
    Imports .gguf models into Ollama using a reliable Modelfile approach.
    After successful import, the model is automatically pre-loaded into memory
    using a quick non-interactive inference (works on any Ollama version).
    If pre-loading fails, the script offers an interactive fallback to choose
    another available model as the default for AnswerServer.

${BOLD}OPTIONS${NC}
    ${CYAN}-h, --help${NC}        Show this help message and exit
    ${CYAN}-v, --version${NC}     Show script version
    ${CYAN}-l, --list${NC}        List all available .gguf models in the model directory and exit

${BOLD}ENVIRONMENT VARIABLES${NC}
    ${CYAN}IDOL_LLM_MODEL_PATH${NC}               Directory containing your .gguf model files (required)

    ${CYAN}IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC}  (optional) Preferred default model.
                                          The script will try to match it and will
                                          ask for confirmation / fallback on preload failure.

${BOLD}BEHAVIOR ON PRE-LOAD FAILURE${NC}
    • Interactive mode   → Shows list of successfully created + existing models
                           (with size/age) and lets you pick a different default.
    • Non-interactive    → Warns and continues with the last successfully created model.
"
  exit 0
}

version() {
  echo -e "${BOLD}import-llm-models.sh${NC} version ${CYAN}5.6.0${NC} (Robust pre-load + clearer fallback UI)"
  exit 0
}

# ─────────────────────────────────────────────
# Normalize model name for smart matching
# ─────────────────────────────────────────────
normalize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' \
             | sed 's/\.gguf$//i' \
             | tr '_ )(:' '-' \
             | tr -cd 'a-z0-9-' \
             | sed 's/-\+/-/g; s/^-//; s/-$//'
}

# ─────────────────────────────────────────────
# List all available models (on disk)
# ─────────────────────────────────────────────
list_models() {
  echo -e "\n${BOLD}${BLUE}── Available .gguf Models on Disk ──${NC}"

  if [ -z "${IDOL_LLM_MODEL_PATH:-}" ]; then
    DEFAULT_MODEL_PATH="$HOME/llm-models"
    IDOL_LLM_MODEL_PATH="$DEFAULT_MODEL_PATH"
    echo -e "${DIM}→ Using default model path: ${IDOL_LLM_MODEL_PATH}${NC}"
  fi

  if [ ! -d "$IDOL_LLM_MODEL_PATH" ]; then
    echo -e "${YELLOW}⚠️  Directory does not exist yet: $IDOL_LLM_MODEL_PATH${NC}"
    echo -e "   ${DIM}Run the script without -l to create it and configure the path.${NC}"
    echo ""
    exit 0
  fi

  shopt -s nullglob
  local gguf_files=("$IDOL_LLM_MODEL_PATH"/*.gguf)

  if [ ${#gguf_files[@]} -eq 0 ]; then
    echo -e "${YELLOW}No .gguf files found in:${NC}"
    echo -e "   ${CYAN}$IDOL_LLM_MODEL_PATH${NC}"
    echo -e "${DIM}   (Place your .gguf models in this folder and run again)${NC}"
  else
    echo -e "${GREEN}📦 Found ${#gguf_files[@]} model(s) ready to import:${NC}"
    for f in "${gguf_files[@]}"; do
      local size=$(du -h "$f" 2>/dev/null | cut -f1)
      echo -e "   ${CYAN}•${NC} $(basename "$f") ${YELLOW}(${size})${NC}"
    done
    echo -e "\n${DIM}Note: These are source .gguf files on disk. They become available in Ollama only after import.${NC}"
  fi
  echo ""
  exit 0
}

# ─────────────────────────────────────────────
# Option parsing (early exit for help/version/list)
# ─────────────────────────────────────────────
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage
[[ "${1:-}" == "-v" || "${1:-}" == "--version" ]] && version
[[ "${1:-}" == "-l" || "${1:-}" == "--list" ]] && list_models

# ─────────────────────────────────────────────
# Detect non-interactive mode
# ─────────────────────────────────────────────
NON_INTERACTIVE=false
if [ ! -t 0 ] || [ -n "${LLM_DEPLOY_MODE:-}" ]; then
    NON_INTERACTIVE=true
fi

# ─────────────────────────────────────────────
# INTERACTIVE PATH SETUP
# ─────────────────────────────────────────────
if [ -z "${IDOL_LLM_MODEL_PATH:-}" ]; then
  DEFAULT_MODEL_PATH="$HOME/llm-models"
  echo -e "\n${BOLD}${BLUE}── LLM Model Path Configuration ──${NC}"
  echo -e "${CYAN}→ Where do you want to save the LLM models?${NC}"
  echo -e "${DIM}   (press Enter to accept the default shown in [...])${NC}${YELLOW}"
  read -r -p "Path [default: ${DEFAULT_MODEL_PATH}]: " MODEL_ANSWER

  if [ -n "$MODEL_ANSWER" ]; then
    export IDOL_LLM_MODEL_PATH="$MODEL_ANSWER"
  else
    export IDOL_LLM_MODEL_PATH="$DEFAULT_MODEL_PATH"
  fi
  echo -e "${GREEN}[OK]${NC}    Using model path: ${IDOL_LLM_MODEL_PATH}"
fi

# ─────────────────────────────────────────────
# Directory check / creation
# ─────────────────────────────────────────────
if [ ! -d "$IDOL_LLM_MODEL_PATH" ]; then
  echo -e "${YELLOW}⚠️  Directory not found: $IDOL_LLM_MODEL_PATH${NC}"
  echo -e "   Creating it now..."
  mkdir -p "$IDOL_LLM_MODEL_PATH"
  echo -e "${GREEN}✅ Directory created.${NC}"
  echo -e "${YELLOW}   Please place your .gguf model files there and run again.${NC}"
  exit 0
fi

# ─────────────────────────────────────────────
# Determine which models to import
# ─────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── Selecting Models ──${NC}"

if [ $# -gt 0 ]; then
  echo -e "${CYAN}→ Importing ${#} selected model(s):${NC}"
  gguf_files=()
  for arg in "$@"; do
    [[ "$arg" != *.gguf ]] && arg="${arg}.gguf"
    fullpath="$IDOL_LLM_MODEL_PATH/$arg"
    if [ -f "$fullpath" ]; then
      gguf_files+=("$fullpath")
      echo -e "   ${GREEN}✓${NC} $arg"
    else
      echo -e "   ${RED}✗${NC} $arg ${YELLOW}(not found)${NC}"
    fi
  done
else
  echo -e "${CYAN}→ No specific models given → importing ALL .gguf files${NC}"
  shopt -s nullglob
  gguf_files=("$IDOL_LLM_MODEL_PATH"/*.gguf)
fi

if [ ${#gguf_files[@]} -eq 0 ]; then
  echo -e "${RED}❌ No .gguf files to import.${NC}"
  exit 1
fi

echo -e "${GREEN}📦 Will import ${#gguf_files[@]} model(s):${NC}"
for f in "${gguf_files[@]}"; do
  echo "   • $(basename "$f")"
done
echo ""

# ─────────────────────────────────────────────
# Smart default for IDOL_ANSWERSERVER_LLM_MODEL_NAME
# ─────────────────────────────────────────────
echo -e "${BOLD}${BLUE}── Default Answer Server Model ──${NC}"

if [ -n "${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-}" ]; then
  REQUESTED="${IDOL_ANSWERSERVER_LLM_MODEL_NAME}"
  REQ_NORM=$(normalize_name "$REQUESTED")

  echo -e "${CYAN}→ IDOL_ANSWERSERVER_LLM_MODEL_NAME is already set to: ${BOLD}${IDOL_ANSWERSERVER_LLM_MODEL_NAME}${NC}"
  echo -e "   Normalized search: ${REQ_NORM}"

  BEST_FILE=""
  BEST_NORM_NAME=""
  BEST_SCORE=0

  for f in "${gguf_files[@]}"; do
    BASENAME=$(basename "$f")
    FILE_NORM=$(normalize_name "$BASENAME")

    if [[ "$FILE_NORM" == "$REQ_NORM" ]]; then
      SCORE=200
    elif [[ "$FILE_NORM" == *"$REQ_NORM"* ]] || [[ "$REQ_NORM" == *"$FILE_NORM"* ]]; then
      SCORE=100
    else
      SCORE=0
    fi

    if [ "$SCORE" -gt "$BEST_SCORE" ]; then
      BEST_SCORE=$SCORE
      BEST_FILE="$f"
      BEST_NORM_NAME=$(basename "$f" .gguf | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    fi
  done

  if [ -n "$BEST_FILE" ] && [ "$BEST_SCORE" -gt 0 ]; then
    PROPOSED_FILE=$(basename "$BEST_FILE")
    echo -e "${GREEN}✓ Best match found:${NC} ${PROPOSED_FILE} → ${BOLD}${BEST_NORM_NAME}${NC}"

    if [ "$BEST_SCORE" -eq 200 ]; then
      export IDOL_ANSWERSERVER_LLM_MODEL_NAME="$BEST_NORM_NAME"
      echo "IDOL_ANSWERSERVER_LLM_MODEL_NAME=${IDOL_ANSWERSERVER_LLM_MODEL_NAME}" > /tmp/idol-answerserver-model.env
      echo -e "${GREEN}✅ Exact match.${NC} ${BOLD}IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC} updated to: ${BOLD}${GREEN}$IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC}"
    else
      CONFIRM=""

      if [ "$NON_INTERACTIVE" = true ]; then
          CONFIRM="y"
          echo -e "   ${YELLOW}Non-interactive mode detected → auto-accepting best match${NC}"
      else
          for i in 5 4 3 2 1; do
              echo -ne "\r   ${BOLD}Auto-confirming ${CYAN}[Y]${NC}${BOLD} in ${ORANGE}${i}s ${NC}${BOLD}— or enter your choice ${CYAN}[Y/n] ${NC}   "
              if read -t 1 -rsn1 CONFIRM; then
                  echo ""
                  break
              fi
          done
          echo ""
      fi

      CONFIRM="${CONFIRM:-y}"
      CONFIRM="${CONFIRM^^}"

      if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        export IDOL_ANSWERSERVER_LLM_MODEL_NAME="$BEST_NORM_NAME"
        echo "IDOL_ANSWERSERVER_LLM_MODEL_NAME=${IDOL_ANSWERSERVER_LLM_MODEL_NAME}" > /tmp/idol-answerserver-model.env
        echo -e "${GREEN}✅ Confirmed.${NC} ${BOLD}IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC} updated to: ${BOLD}${GREEN}$IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC}"
      else
        echo -e "${YELLOW}⚠️  Match rejected. Please select a model from the list:${NC}\n"
        declare -a MODEL_NAMES=()
        idx=1
        for f in "${gguf_files[@]}"; do
          NORM=$(basename "$f" .gguf | tr '[:upper:]' '[:lower:]' | tr '_' '-')
          MODEL_NAMES+=("$NORM")
          echo -e "   ${CYAN}[$idx]${NC} $NORM  ${DIM}($(basename "$f"))${NC}"
          (( idx++ ))
        done
        echo ""
        SELECTED_IDX=""
        while true; do
          read -r -p "$(echo -e "${YELLOW}→ Enter number [1-${#MODEL_NAMES[@]}]: ${NC}")" SELECTED_IDX
          if [[ "$SELECTED_IDX" =~ ^[0-9]+$ ]] && \
             [ "$SELECTED_IDX" -ge 1 ] && \
             [ "$SELECTED_IDX" -le "${#MODEL_NAMES[@]}" ]; then
            break
          fi
          echo -e "${RED}   Invalid choice. Enter a number between 1 and ${#MODEL_NAMES[@]}.${NC}"
        done
        export IDOL_ANSWERSERVER_LLM_MODEL_NAME="${MODEL_NAMES[$((SELECTED_IDX - 1))]}"
        echo "IDOL_ANSWERSERVER_LLM_MODEL_NAME=${IDOL_ANSWERSERVER_LLM_MODEL_NAME}" > /tmp/idol-answerserver-model.env
        echo -e "${GREEN}✅ Selected.${NC} ${BOLD}IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC} updated to: ${BOLD}${GREEN}$IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC}"
      fi
    fi
  else
    echo -e "${YELLOW}⚠️  No good match found for '${REQUESTED}'. Falling back to first model.${NC}"
  fi
fi

# Fallback: if still not set
if [ -z "${IDOL_ANSWERSERVER_LLM_MODEL_NAME:-}" ]; then
  echo -e "${CYAN}→ IDOL_ANSWERSERVER_LLM_MODEL_NAME was not set${NC}"

  if [ "$NON_INTERACTIVE" = true ]; then
    FIRST_MODEL_PATH="${gguf_files[0]}"
    DEFAULT_MODEL_NAME=$(basename "$FIRST_MODEL_PATH" .gguf)
    DEFAULT_MODEL_NAME="${DEFAULT_MODEL_NAME,,}"
    DEFAULT_MODEL_NAME=$(echo "$DEFAULT_MODEL_NAME" | tr '_' '-')

    export IDOL_ANSWERSERVER_LLM_MODEL_NAME="$DEFAULT_MODEL_NAME"
    echo "IDOL_ANSWERSERVER_LLM_MODEL_NAME=${IDOL_ANSWERSERVER_LLM_MODEL_NAME}" > /tmp/idol-answerserver-model.env
    echo -e "   ${YELLOW}Non-interactive mode detected →${NC} ${GREEN}IDOL_ANSWERSERVER_LLM_MODEL_NAME updated to: ${BOLD}${GREEN}$IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC}"
  else
    echo -e "${YELLOW}   Please select the default Answer Server model from the list:${NC}\n"
    declare -a MODEL_NAMES=()
    idx=1
    for f in "${gguf_files[@]}"; do
      NORM=$(basename "$f" .gguf | tr '[:upper:]' '[:lower:]' | tr '_' '-')
      MODEL_NAMES+=("$NORM")
      echo -e "   ${CYAN}[$idx]${NC} $NORM  ${DIM}($(basename "$f"))${NC}"
      (( idx++ ))
    done
    echo ""
    SELECTED_IDX=""
    while true; do
      read -r -p "$(echo -e "${YELLOW}→ Enter number [1-${#MODEL_NAMES[@]}] (default: 1): ${NC}")" SELECTED_IDX
      SELECTED_IDX="${SELECTED_IDX:-1}"
      if [[ "$SELECTED_IDX" =~ ^[0-9]+$ ]] && \
         [ "$SELECTED_IDX" -ge 1 ] && \
         [ "$SELECTED_IDX" -le "${#MODEL_NAMES[@]}" ]; then
        break
      fi
      echo -e "${RED}   Invalid choice. Enter a number between 1 and ${#MODEL_NAMES[@]}.${NC}"
    done
    export IDOL_ANSWERSERVER_LLM_MODEL_NAME="${MODEL_NAMES[$((SELECTED_IDX - 1))]}"
    echo "IDOL_ANSWERSERVER_LLM_MODEL_NAME=${IDOL_ANSWERSERVER_LLM_MODEL_NAME}" > /tmp/idol-answerserver-model.env
    echo -e "${GREEN}✅ Selected.${NC} ${BOLD}IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC} updated to: ${BOLD}${GREEN}$IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC}"
  fi
fi

echo ""

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
TEMPERATURE=0.2
TOP_P=0.9
NUM_CTX=4096

# Array to track successfully created models (for fallback selection)
declare -a SUCCESSFUL_MODELS=()

# ─────────────────────────────────────────────
# Run any command with nice spinner animation
# ─────────────────────────────────────────────
run_with_spinner() {
  local message="$1"
  shift

  echo -ne "${CYAN}📤 ${message}...${NC}"

  "$@" &
  local pid=$!

  local delay=0.08
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0

  while kill -0 $pid 2>/dev/null; do
    i=$(( (i + 1) % 10 ))
    printf "\b${spin:$i:1}"
    sleep $delay
  done

  wait $pid
  local status=$?

  if [ $status -eq 0 ]; then
    printf "\r${GREEN}✅ ${message} — Complete!${NC}                          \n"
  else
    printf "\r${RED}❌ ${message} — Failed!${NC}                          \n"
  fi

  return $status
}

# ─────────────────────────────────────────────
# Function: Pre-load model (robust, no --keep-alive flag)
# ─────────────────────────────────────────────
preload_model_or_fallback() {
  local MODEL_NAME="$1"
  local PRELOAD_SUCCESS=false

  echo -e "🔥 Pre-loading ${BOLD}${MODEL_NAME}${NC} into memory (quick warmup, ~10-60s)..."

  # Robust pre-load method:
  # - Provide a short dummy prompt so the CLI always has [PROMPT] before any flags (if we add them later)
  # - No --keep-alive flag → works on every Ollama version (old or new)
  # - Model gets loaded into RAM during the short generation
  # - Default Ollama keep-alive (usually 5m) keeps it warm for AnswerServer startup
  # - timeout protects against hangs; </dev/null prevents any stdin blocking
  PRELOAD_OUTPUT=$(docker exec ollama timeout 120 ollama run "$MODEL_NAME" "Hi, warming up." </dev/null 2>&1)
  PRELOAD_EXIT=$?

  if [ $PRELOAD_EXIT -eq 0 ] && ! echo "$PRELOAD_OUTPUT" | grep -qiE 'error|failed|not found|connection refused|unknown flag'; then
    echo -e "${GREEN}✅ Model pre-loaded successfully and kept in memory.${NC}"
    PRELOAD_SUCCESS=true
  else
    echo -e "${RED}❌ Pre-load failed for model: ${BOLD}$MODEL_NAME${NC}"
    echo "$PRELOAD_OUTPUT" | tail -8 | sed 's/^/   /'
  fi

  if [ "$PRELOAD_SUCCESS" = true ]; then
    SUCCESSFUL_MODELS+=("$MODEL_NAME")
    return 0
  fi

  # ── PRE-LOAD FAILED ─────────────────────────────────────────────
  if [ "$NON_INTERACTIVE" = true ]; then
    echo -e "${YELLOW}⚠️  Non-interactive mode → continuing without pre-load for this model.${NC}"
    SUCCESSFUL_MODELS+=("$MODEL_NAME")   # still mark as created
    return 0
  fi

  # Interactive fallback: let user choose another model
  echo ""
  echo -e "${BOLD}${ORANGE}────────────────────────────────────────────────────────────${NC}"
  echo -e "${BOLD}${RED}Pre-load failed for '${MODEL_NAME}'.${NC}"
  echo -e "Please select a different model to use as the default for AnswerServer."
  echo -e "${BOLD}${ORANGE}────────────────────────────────────────────────────────────${NC}"
  echo ""
  echo -e "${DIM}Possible causes for pre-load failure:${NC}"
  echo -e "  ${DIM}• Model is very large and does not fit in available RAM/GPU memory${NC}"
  echo -e "  ${DIM}• Temporary resource contention or slow disk I/O during first load${NC}"
  echo -e "  ${DIM}• Ollama container needs more CPU/memory limits (check docker stats)${NC}"
  echo -e "  ${DIM}• The chosen model may have issues (try another if available)${NC}"
  echo ""

  # Get current list of models from Ollama with nice formatting (name + size + modified)
  echo -e "${CYAN}Available models currently registered in Ollama:${NC}"
  echo -e "${DIM}(Only models that were successfully imported/created appear here.
 The 7 models shown in the initial scan are .gguf files on disk — they must be imported first to become selectable.)${NC}"
  echo ""

  # Use ollama list and format nicely
  mapfile -t OLLAMA_LIST_LINES < <(docker exec ollama ollama list | tail -n +2 | grep -v '^$')

  if [ ${#OLLAMA_LIST_LINES[@]} -eq 0 ]; then
    echo -e "${RED}No models available in Ollama. Cannot select fallback.${NC}"
    return 1
  fi

  declare -a AVAILABLE_MODELS=()
  idx=1
  for line in "${OLLAMA_LIST_LINES[@]}"; do
    # line format: NAME ID SIZE MODIFIED
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $3}')
    modified=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf $i" "; print ""}' | sed 's/ $//')
    AVAILABLE_MODELS+=("$name")
    printf "   ${CYAN}[%d]${NC} %-35s ${YELLOW}%8s${NC}  ${DIM}%s${NC}\n" "$idx" "$name" "$size" "$modified"
    (( idx++ ))
  done
  echo ""

  SELECTED=""
  while true; do
    read -r -p "$(echo -e "${YELLOW}→ Enter number of model to use as default [1-${#AVAILABLE_MODELS[@]}]: ${NC}")" SELECTED
    if [[ "$SELECTED" =~ ^[0-9]+$ ]] && \
       [ "$SELECTED" -ge 1 ] && \
       [ "$SELECTED" -le "${#AVAILABLE_MODELS[@]}" ]; then
      break
    fi
    echo -e "${RED}   Invalid choice. Please enter a number between 1 and ${#AVAILABLE_MODELS[@]}.${NC}"
  done

  NEW_DEFAULT="${AVAILABLE_MODELS[$((SELECTED-1))]}"
  export IDOL_ANSWERSERVER_LLM_MODEL_NAME="$NEW_DEFAULT"
  echo "IDOL_ANSWERSERVER_LLM_MODEL_NAME=${IDOL_ANSWERSERVER_LLM_MODEL_NAME}" > /tmp/idol-answerserver-model.env
  echo -e "${GREEN}✅ New default selected: ${BOLD}${GREEN}$IDOL_ANSWERSERVER_LLM_MODEL_NAME${NC}"

  # Also add the newly chosen model to successful list if not already there
  if [[ ! " ${SUCCESSFUL_MODELS[*]} " =~ " ${NEW_DEFAULT} " ]]; then
    SUCCESSFUL_MODELS+=("$NEW_DEFAULT")
  fi

  return 0
}

# ─────────────────────────────────────────────
# Import each model
# ─────────────────────────────────────────────
for GGUF_PATH in "${gguf_files[@]}"; do
  FILENAME=$(basename "$GGUF_PATH")
  MODEL_NAME="${FILENAME%.gguf}"
  MODEL_NAME="${MODEL_NAME,,}"
  MODEL_NAME=$(echo "$MODEL_NAME" | tr '_' '-')

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "📄 File : $FILENAME"
  echo -e "🏷️  Name : $MODEL_NAME"

  run_with_spinner "Copying GGUF → Ollama container" \
    docker cp "$GGUF_PATH" ollama:/tmp/"$FILENAME"

  MODELFILE_TMP="/tmp/Modelfile.$MODEL_NAME"
  cat > "$MODELFILE_TMP" <<EOF
FROM /tmp/${FILENAME}

PARAMETER temperature ${TEMPERATURE}
PARAMETER top_p ${TOP_P}
PARAMETER num_ctx ${NUM_CTX}

SYSTEM """
You are a helpful assistant.
"""
EOF

  run_with_spinner "Copying Modelfile → Ollama container" \
    docker cp "$MODELFILE_TMP" ollama:/tmp/Modelfile."$MODEL_NAME"

  echo -e "🔎 Files in container /tmp/:"
  docker exec ollama ls -lh /tmp/ | grep -E "(Modelfile|${FILENAME})"

  echo -e "⚙️  Creating model in Ollama..."

  CREATE_LOG=$(docker exec ollama ollama create "$MODEL_NAME" -f "/tmp/Modelfile.$MODEL_NAME" 2>&1)
  CREATE_EXIT=$?

  if [ $CREATE_EXIT -eq 0 ]; then
    echo -e "${GREEN}✅ Successfully registered: $MODEL_NAME${NC}"

    # Pre-load (with interactive fallback on failure)
    preload_model_or_fallback "$MODEL_NAME"

  else
    echo -e "${RED}❌ Failed to register: $MODEL_NAME${NC}"
    echo "$CREATE_LOG" | head -12 | sed 's/^/   /'

    # GGUF corruption detection
    if echo "$CREATE_LOG" | grep -qiE 'offset\+size.*exceeds file size|tensor.*exceeds file size|offset.*exceeds'; then
      echo ""
      echo -e "${RED}🚨 CORRUPTED / INCOMPLETE .gguf FILE DETECTED!${NC}"
      echo -e "   Location: ${CYAN}$GGUF_PATH${NC}   Size: $(du -h "$GGUF_PATH" 2>/dev/null | cut -f1)"

      if [ "$NON_INTERACTIVE" = true ]; then
        echo -e "${YELLOW}   Non-interactive mode → skipping this model (file is NOT deleted automatically).${NC}"
      else
        echo ""
        echo -ne "${YELLOW}🗑️  Delete this corrupted file now? ${NC}[${GREEN}y${NC}/${RED}N${NC}] "
        read -r -n 1 DELETE_ANS
        echo ""
        DELETE_ANS="${DELETE_ANS,,}"

        if [[ "$DELETE_ANS" == "y" ]]; then
          rm -f "$GGUF_PATH"
          echo -e "${GREEN}✅ Deleted: $FILENAME${NC}"
        else
          echo -e "${YELLOW}⏭️  Keeping the file. You can try re-downloading it manually.${NC}"
        fi
      fi
    fi
  fi

  # Cleanup temp files
  docker exec ollama rm -f "/tmp/$FILENAME" "/tmp/Modelfile.$MODEL_NAME" 2>/dev/null || true
  rm -f "$MODELFILE_TMP"

  echo ""
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${YELLOW}Final registered models in Ollama:${NC}"
docker exec ollama ollama list
echo -e "${NC}"

# =============================================================================
# Updating default-models.json (optional)
# =============================================================================
UPDATER_SCRIPT="update-llm-json-models.sh"
if [ -f "./$UPDATER_SCRIPT" ]; then
    echo -e "${CYAN}→ Running $UPDATER_SCRIPT on default-models.json${NC}"
    ./"$UPDATER_SCRIPT" default-models.json || echo -e "${YELLOW}⚠️  JSON updater finished with warnings${NC}"
fi

# ─────────────────────────────────────────────
# Final summary
# ─────────────────────────────────────────────
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}IDOL_ANSWERSERVER_LLM_MODEL_NAME = ${GREEN}${BOLD}${IDOL_ANSWERSERVER_LLM_MODEL_NAME}${NC}"
if [ -f /tmp/idol-answerserver-model.env ]; then
  echo -e "${DIM}   (To export into current shell: ${NC}${CYAN}source /tmp/idol-answerserver-model.env${NC}${DIM})${NC}"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ ${#SUCCESSFUL_MODELS[@]} -gt 0 ]; then
  echo -e "${GREEN}✅ Successfully processed models: ${SUCCESSFUL_MODELS[*]}${NC}"
fi
