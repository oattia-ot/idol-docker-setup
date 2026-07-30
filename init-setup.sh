#!/bin/bash
# OpenText IDOL on Ubuntu 24.04
set -euo pipefail

# Colors
BOLD='\033[1m'; LIGHTER_YELLOW='\033[38;5;228m'; RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; ORANGE='\033[0;38;5;214m'; YELLOW='\033[1;33m'; NC='\033[0m'

###################
## Script Utilities
###################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXE_SCRIPT_NAME=$(basename "$0")

# Shared resolution steps — pass the base path or falls back to a placeholder
_print_ui_config_resolution() {
    local base="${1:-.}"
    echo ""
    echo -e "${YELLOW}🔧 Resolution steps:${NC}"
    echo -e "    ${YELLOW}1)${ORANGE} cd ${base}/utilities/ui-config/${NC}"
    echo -e "    ${YELLOW}2)${ORANGE} ./deploy-setup-manager-ui.sh --clean${NC}"
    echo -e "    ${YELLOW}3)${ORANGE} ./deploy-setup-manager-ui.sh --deploy${NC}"
    echo -e "    ${YELLOW}    Execute --> ${RED}cd ${base}/utilities/ui-config/ && ./deploy-setup-manager-ui.sh --clean && ./deploy-setup-manager-ui.sh --deploy${NC}"
    echo -e "    ${YELLOW}4)${CYAN} On your client web browser, press: Ctrl + Shift + R.${NC}"
    echo ""
}

# Guard — must come before any use of IDOL_BASE_PATH
if [ -z "${IDOL_BASE_PATH:-}" ]; then
    echo -e "${RED}❌ [ERROR] IDOL_BASE_PATH is not set or empty. Cannot define log file path.${NC}" >&2
    echo -e "${RED}   Export it first: export IDOL_BASE_PATH=/<your_base_path>${NC}" >&2
    _print_ui_config_resolution          # no arg → prints <IDOL_BASE_PATH> placeholder
    exit 1
fi

# Safe to use IDOL_BASE_PATH from here on
export LOGFILE="$IDOL_BASE_PATH/logs/${EXE_SCRIPT_NAME%.*}_$(date +"%Y%m%d").log"
mkdir -p "$(dirname "$LOGFILE")"

source "$SCRIPT_DIR/module/general-utilities.code"

check_pre_setup_file() {
    if [ ! -s "$PRE_SETUP_FILE" ]; then
        echo -e "${RED}❌ ${BOLD}Error: $PRE_SETUP_FILE is missing or empty.${NC}"
        echo -e "${RED}   The file was either never created or has been truncated.${NC}"
        _print_ui_config_resolution "$IDOL_BASE_PATH"   # real path available here
        echo -e "${YELLOW}Then run the setup script again.${NC}"
        exit 1
    fi
}

# Define global log file path and ensure log directory exists
export LOGFILE="$IDOL_BASE_PATH/logs/${EXE_SCRIPT_NAME%.*}_$(date +"%Y%m%d").log"
mkdir -p "$(dirname "$LOGFILE")"

# Source our utilities (now works from any path)
source "$SCRIPT_DIR/module/general-utilities.code"


##########################
## Initial Cleanup Section
##########################
cleanup_old_license_server() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [initial-cleanup]${ORANGE}"

    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Starting cleanup of old LicenseServer_* files...${NC}"

    local LICENSE_DIR="$IDOL_BASE_PATH/idol-licenseserver"

    if [ -d "$LICENSE_DIR" ]; then
        # Safely delete only LicenseServer_* files (keep directory and any other files)
        shopt -s nullglob
        local old_files=("$LICENSE_DIR"/LicenseServer_*)
        if [ ${#old_files[@]} -gt 0 ]; then
            sudo rm -fr "$LICENSE_DIR"/LicenseServer_* 2>/dev/null || true
            log "${CALLING_SCRIPT} ✅ Removed ${#old_files[@]} old LicenseServer_* file(s) from ${ORANGE}$LICENSE_DIR${NC}"
            echo -e "${GREEN}✅ Old LicenseServer_* files cleaned up.${NC}"
        else
            log "${CALLING_SCRIPT} No LicenseServer_* files found to clean."
            echo -e "${YELLOW}ℹ No old LicenseServer_* files found.${NC}"
        fi
        shopt -u nullglob
    else
        log "${CALLING_SCRIPT} ⚠ LicenseServer directory does not exist yet at $LICENSE_DIR — nothing to clean."
        echo -e "${YELLOW}⚠ LicenseServer directory not found yet (will be created later if needed).${NC}"
    fi
}

##################################
## Dangling Docker Volume Cleanup
##################################
cleanup_dangling_docker_volumes() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [cleanup_dangling_docker_volumes]${ORANGE}"

    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Checking for dangling (unused) Docker volumes...${NC}"

    local dangling_volumes
    dangling_volumes=$(docker volume ls -f dangling=true)

    # Count actual volume rows (subtract 1 for the header line)
    local volume_count
    volume_count=$(( $(echo "$dangling_volumes" | wc -l) - 1 ))

    if [ "$volume_count" -le 0 ]; then
        log "${CALLING_SCRIPT} ✅ No dangling Docker volumes found."
        echo -e "${GREEN}✅ No dangling Docker volumes found.${NC}"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}${BOLD}⚠ Dangling (unused) Docker volumes detected:${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
    echo -e "${LIGHTER_YELLOW}${dangling_volumes}${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
    echo -e "${ORANGE}   ${volume_count} dangling volume(s) found.${NC}"
    echo ""
    echo -e "${RED}${BOLD}⚠ WARNING:${NC} ${RED}This will permanently delete all unused volumes and any data they contain.${NC}"
    echo ""

    read -p "$(echo -e "${CYAN}Do you want to delete all dangling volumes now? (y/n): ${NC}")" CONFIRM_VOLUME_PRUNE

    if [[ "$CONFIRM_VOLUME_PRUNE" =~ ^[Yy]$ ]]; then
        log "${CALLING_SCRIPT} ${YELLOW}User confirmed — running 'docker volume prune -f'...${NC}"
        if docker volume prune -f; then
            log "${CALLING_SCRIPT} ✅ Dangling Docker volumes removed successfully."
            echo -e "${GREEN}✅ Dangling Docker volumes removed successfully.${NC}"
        else
            log "${CALLING_SCRIPT} ❌ 'docker volume prune -f' failed."
            echo -e "${RED}❌ Failed to remove dangling Docker volumes.${NC}"
            return 1
        fi
    else
        log "${CALLING_SCRIPT} ⚠ User declined — skipping dangling volume cleanup."
        echo -e "${YELLOW}⚠ Skipped — dangling volumes were left untouched.${NC}"
    fi
}

# Run cleanup at the very beginning of the script execution
cleanup_old_license_server
cleanup_dangling_docker_volumes


#################################
## Deploy Nifi Registry
#################################
deploy_nifi_registry() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [deploy_nifi_registry] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Deploy Nifi Registry...${NC}"

    # Copy [NIFI REGISTRY] persistent data path
    if [ "$IS_IDOL_NIFI_REGISTRY_PRESERVE" = "TRUE" ]; then
        # Deploy NiFi registry
        cd "$SCRIPT_DIR/utilities/nifi-registry-setup/"
        ./deploy-nifi-registry-with-git.sh up -d
        cd $IDOL_BASE_PATH
        cd -
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Deploy [NIFI REGISTRY] executed ${NC}"

        log "${CALLING_SCRIPT} ${YELLOW}Setup Nif Registry is ${GREEN}[ENABLE]${NC}"
        echo ''
        # --- end of script output ---
        echo ''
        log "${CALLING_SCRIPT} ${YELLOW}====================================================         ${NC}"
        log "${CALLING_SCRIPT} ${YELLOW} NiFi registry access information                            ${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}----------------------------------------------------         ${NC}"
        log "${CALLING_SCRIPT} ${YELLOW} URL: ${ORANGE}http://idol-docker-host:18080/nifi-registry   ${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}====================================================         ${NC}"
        echo ''
        log "${CALLING_SCRIPT} ${YELLOW}====================================${NC}"
        log "${CALLING_SCRIPT} ${YELLOW} NiFi access information            ${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}------------------------------------${NC}"
        log "${CALLING_SCRIPT} ${YELLOW} Username: ${ORANGE}admin           ${NC}"
        log "${CALLING_SCRIPT} ${YELLOW} Password: ${ORANGE}OpenText2026!   ${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}====================================${NC}"
        echo ''

        return 0
    fi
    log "${CALLING_SCRIPT} ${YELLOW}Setup Nif Registry is ${RED}[DISABLE]${NC}"
}

#################################
## Run Ollama Resource Estimator
#################################
run_ollama_resource_estimator() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [run_ollama_resource_estimator] module${ORANGE}"

    if [ "${IDOL_LLM_INTEGRATION:-}" != "TRUE" ]; then
        log "${CALLING_SCRIPT} ${YELLOW}IDOL_LLM_INTEGRATION is not TRUE — skipping Ollama resource estimator.${NC}"
        return 0
    fi

    # IDOL_LLM_INTEGRATION is TRUE — proceed with LLM API key handling
    if [ "${IDOL_LLM_ENABLE_APIKEY:-}" = "TRUE" ]; then
        # Enable Grok by uncommenting the line in the config
        local ANSWERSERVER_CFG="$IDOL_BASE_PATH/persistent-data/answerserver/cfg/answerserver.cfg"

        if [ -f "$ANSWERSERVER_CFG" ]; then
            sed -i 's|^//[[:space:]]*2[[:space:]]*=[[:space:]]*Grok|2=Grok|' "$ANSWERSERVER_CFG"
            log "${CALLING_SCRIPT} ${GREEN}IDOL_LLM_ENABLE_APIKEY=TRUE — Grok LLM API key support ENABLED.${NC}"
        else
            log "${CALLING_SCRIPT} ${RED}❌ answerserver.cfg not found at: $ANSWERSERVER_CFG${NC}"
            return 1
        fi
    else
        # Disable Grok by commenting out the line
        local ANSWERSERVER_CFG="$IDOL_BASE_PATH/persistent-data/answerserver/cfg/answerserver.cfg"

        if [ -f "$ANSWERSERVER_CFG" ]; then
            sed -i 's|^[[:space:]]*2[[:space:]]*=[[:space:]]*Grok|//2=Grok|' "$ANSWERSERVER_CFG"
            log "${CALLING_SCRIPT} ${YELLOW}IDOL_LLM_ENABLE_APIKEY is not TRUE — Grok LLM API key support DISABLED.${NC}"
        else
            log "${CALLING_SCRIPT} ${RED}❌ answerserver.cfg not found at: $ANSWERSERVER_CFG${NC}"
            return 1
        fi
    fi

    # Resolve the ollama_server.py path
    local OLLAMA_SERVER_PATH="${IDOL_PRESERVE_ANSWERSERVER_PATH}/rag/ollama_server.py"
    if [ -z "$OLLAMA_SERVER_PATH" ]; then
        echo -e "${RED}❌ OLLAMA_SERVER_PATH is not set. Cannot run ollama-resource-estimator.${NC}"
        return 1
    fi
    if [ ! -f "$OLLAMA_SERVER_PATH" ]; then
        echo -e "${RED}❌ ollama_server.py not found at: ${ORANGE}${OLLAMA_SERVER_PATH}${NC}"
        return 1
    fi

    local ESTIMATOR_SCRIPT="${IDOL_BASE_PATH}/idol-containers-toolkit/data-admin/llm-sandbox/ollama-resource-estimator.sh"
    if [ ! -f "$ESTIMATOR_SCRIPT" ]; then
        echo -e "${RED}❌ ollama-resource-estimator.sh not found at: ${ORANGE}${ESTIMATOR_SCRIPT}${NC}"
        return 1
    fi

    echo ''
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}▶ Ollama Resource Estimator — LLM Integration Detected${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "   ${ORANGE}IDOL_LLM_INTEGRATION=TRUE${NC} — Ollama resource estimation required."
    echo ''
    echo -e "   ${YELLOW}Use the default/recommended context window size ${BOLD}[4096]${NC}${YELLOW}?${NC}"
    echo -e "   ${GREEN}[D]${NC} Default  — runs with ${BOLD}-d${NC} flag (recommended, context=4096)"
    echo -e "   ${ORANGE}[R]${NC} Custom   — runs with ${BOLD}-r${NC} flag (interactive resource selection)"
    echo ''

    local USER_CHOICE
    while true; do
        # Interruptible countdown — breaks instantly on any keypress
        for i in 5 4 3 2 1; do
            echo -ne "\r   ${BOLD}Auto-selecting ${GREEN}[D]${NC}${BOLD} in ${ORANGE}${i}s${NC}${BOLD} — or enter your choice [D/R]: ${NC}   "
            read -t 1 -rsn1 USER_CHOICE && break   # key pressed → exit loop immediately
        done
        echo ""

        # If nothing was typed during countdown, prompt one final time
        if [[ -z "$USER_CHOICE" ]]; then
            read -t 0.1 -rp "$(echo -e "   ${GREEN}[D]${NC}/${ORANGE}[R]${NC} ${BOLD}Enter your choice [D/R]: ${NC}")" USER_CHOICE
        fi

        USER_CHOICE="${USER_CHOICE:-D}"   # default to D on timeout/empty
        USER_CHOICE="${USER_CHOICE^^}"    # normalize to uppercase

        case "$USER_CHOICE" in
            D)
                log "${CALLING_SCRIPT} ${GREEN}User selected DEFAULT mode (-d, context=4096).${NC}"
                echo -e "\n   ${BOLD}${ORANGE}▸ Running estimator (default mode)...${NC}\n"
                bash "$ESTIMATOR_SCRIPT" -d -u "$OLLAMA_SERVER_PATH"
                local exit_code=$?
                echo ""
                if (( exit_code == 0 )); then
                    echo -e "${GREEN}✅ Ollama resource estimator (default) completed successfully.${NC}"
                else
                    echo -e "${RED}❌ Ollama resource estimator (default) failed with exit code [$exit_code].${NC}"
                    return 1
                fi
                break
                ;;
            R)
                log "${CALLING_SCRIPT} ${ORANGE}User selected CUSTOM mode (-r, interactive).${NC}"
                echo -e "\n   ${BOLD}${ORANGE}▸ Running estimator (custom mode)...${NC}\n"
                bash "$ESTIMATOR_SCRIPT" -r -u "$OLLAMA_SERVER_PATH"   # run directly — interactive, needs live stdin
                local exit_code=$?
                echo ""
                if (( exit_code == 0 )); then
                    echo -e "${GREEN}✅ Ollama resource estimator (custom) completed successfully.${NC}"
                else
                    echo -e "${RED}❌ Ollama resource estimator (custom) failed with exit code [$exit_code].${NC}"
                    return 1
                fi
                break
                ;;
            *)
                echo -e "${RED}   ⚠ Invalid input. Please enter ${BOLD}D${NC}${RED} for Default or ${BOLD}R${NC}${RED} for Custom.${NC}"
                ;;
        esac
    done

    # Print header once — outside the loop
    echo -e "\n   ${BOLD}Ollama Resource Estimator${NC}"
    echo -e "   ${ORANGE}▸${NC} ${ORANGE}${ESTIMATOR_SCRIPT}${NC}\n"

    # Countdown overwrites a single clean line
    for i in 5 4 3 2 1; do
        echo -ne "\r   ${BOLD}Starting in ${ORANGE}${i}s${NC}${BOLD} — press ${RED}Ctrl+C${NC}${BOLD} to abort...${NC}   "
        sleep 1
    done
    echo -e "\n"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ''
}

# Validate all IDOL _PATH variables
echo "=== Validating IDOL _PATH variables ==="
PASS=0
FAIL=0
EXISTING=()
MISSING=()

while IFS= read -r LINE; do
    VAR="${LINE%%=*}"
    VAL="${LINE#*=}"

    if [ -e "$VAL" ]; then
        EXISTING+=("${ORANGE}${SCRIPT_DIR}${GREEN}  ✓ EXISTS   [${VAR}]${NC} → $VAL")
        PASS=$((PASS + 1))
    else
        MISSING+=("${ORANGE}${SCRIPT_DIR}${RED}  ✗ MISSING  [${VAR}]${NC} → $VAL")
        FAIL=$((FAIL + 1))
    fi
done < <(env | grep 'IDOL.*_PATH=' \
    | grep -v '^IDOL_TOOLKIT_PATH=' \
    | grep -v '^IDOL_MEDIASERVER_NIFI_PATH=' \
    | grep -v '^IDOL_MEDIASERVER_STATICDATA_PATH=' \
    | sort)

# Print existing first
for LINE in "${EXISTING[@]}"; do
    echo -e "$LINE"
done

# Separator only if both groups have entries
if [ ${#EXISTING[@]} -gt 0 ] && [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}  ──────────────────────────────────────────────────${NC}"
fi

# Print missing at the bottom
for LINE in "${MISSING[@]}"; do
    echo -e "$LINE"
done

echo ""
echo -e "=== Results: ${GREEN}${PASS} exist${NC} | ${RED}${FAIL} missing${NC} ==="

# =============================================================================
# FLAG STATUS
# =============================================================================

# Write flag to env file, creating it if IDOL_ENV is not set or file doesn't exist
_write_validation_flag() {
    local status="$1"
    local count="$2"

    # If IDOL_ENV is not set, define a default path
    if [ -z "${IDOL_ENV:-}" ]; then
        export IDOL_ENV="$IDOL_BASE_PATH/logs/idol_env_$(date +"%Y%m%d").env"
        echo -e "${YELLOW}⚠  IDOL_ENV was not set — defaulting to: ${ORANGE}${IDOL_ENV}${NC}"
    fi

    # Create the directory and file if they don't exist
    if [ ! -f "$IDOL_ENV" ]; then
        mkdir -p "$(dirname "$IDOL_ENV")" && touch "$IDOL_ENV"
        echo -e "${GREEN}✅ Created IDOL_ENV file: ${ORANGE}${IDOL_ENV}${NC}"
    fi

    # Write the flags
    echo "export IDOL_PATH_VALIDATION_STATUS=${status}"       >> "$IDOL_ENV"
    echo "export IDOL_PATH_VALIDATION_MISSING_COUNT=${count}" >> "$IDOL_ENV"

    # Color based on validation status
    if [ "${IDOL_PATH_VALIDATION_STATUS}" = "PASSED" ]; then
        STATUS_COLOR="${GREEN}"
    else
        STATUS_COLOR="${RED}"
    fi

    echo -e "${STATUS_COLOR}   File Paths Validation Status: [${IDOL_PATH_VALIDATION_STATUS}]${NC}"
}

# Sourcing .bashrc to ensure any environment variables it sets are available immediately
source "$(realpath ~/.bashrc)"

# Deploy Nifi Registry
deploy_nifi_registry

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ PATH VALIDATION FAILED — ${FAIL} missing path(s) detected.${NC}"
    echo -e "${YELLOW}   Please create the missing directories/files before proceeding.${NC}"

    echo ""
    echo -e "${RED}   Missing paths:${NC}"
    env | grep 'IDOL.*_PATH=' | grep -v '^IDOL_TOOLKIT_PATH=' | while IFS='=' read -r var val; do
        [ ! -e "$val" ] && echo -e "${RED}   ✗ [$var] → $val${NC}"
    done || true

    echo -e ""
    echo -e "${YELLOW}${BOLD}⚠  Missing Path Detected${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────${ORANGE}"
    echo -e "   For any missing paths, ensure the folder exists"
    echo -e "   and that you have the proper permissions by running."
    echo -e "   for example:"
    echo -e "   ${LIGHTER_YELLOW}sudo mkdir -p ${BOLD}\$IDOL_LLM_MODEL_PATH${NC}"
    echo -e "   ${LIGHTER_YELLOW}sudo chown ${BOLD}\$USER:\$USER \$IDOL_LLM_MODEL_PATH${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
    echo -e ""

    export IDOL_PATH_VALIDATION_STATUS="FAILED"
    export IDOL_PATH_VALIDATION_MISSING_COUNT="$FAIL"
    _write_validation_flag "FAILED" "$FAIL"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ PATH VALIDATION PASSED — all paths exist.${NC}"

    export IDOL_PATH_VALIDATION_STATUS="PASSED"
    export IDOL_PATH_VALIDATION_MISSING_COUNT="0"
    _write_validation_flag "PASSED" "0"

    # =============================================================================
    # PRE-SETUP CHECK — Ensure ./pre-setup.sh is NOT empty
    # =============================================================================
    PRE_SETUP_FILE="${IDOL_BASE_PATH}/pre-setup.sh"

    check_pre_setup_file

    # =============================================================================
    # STEP 1/5 — Detect IDOL deployment subtypes (moved up so pre-setup.sh
    #            can be copied to each subtype before it is sourced/truncated)
    # =============================================================================
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}▶ STEP 1/5 — Detecting IDOL deployment subtypes...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    SCRIPT_PATH="$SCRIPT_DIR/utilities/config-placeholders/placeholders-replacement.sh"

    if [ ! -f "$SCRIPT_PATH" ]; then
        echo -e "${RED}❌ Error: placeholders-replacement.sh not found.${NC}"
        exit 1
    fi

    # ====================== SUPPORT SINGULAR + PLURAL + COMMA-SEPARATED ======================
    IDOL_DEPLOYMENT_SUBTYPES=()

    if [ -n "${IDOL_DEPLOYMENT_SUBTYPES:-}" ]; then
        echo -e "${YELLOW}⚙️ Using plural override: IDOL_DEPLOYMENT_SUBTYPES=${IDOL_DEPLOYMENT_SUBTYPES}${NC}"
        IFS=' ,' read -ra IDOL_DEPLOYMENT_SUBTYPES <<< "${IDOL_DEPLOYMENT_SUBTYPES}"
    elif [ -n "${IDOL_DEPLOYMENT_SUBTYPE:-}" ]; then
        echo -e "${YELLOW}⚙️ Using singular override: IDOL_DEPLOYMENT_SUBTYPE=${IDOL_DEPLOYMENT_SUBTYPE}${NC}"
        # Split on comma or space and trim whitespace
        IFS=' ,' read -ra TEMP_SUBTYPES <<< "${IDOL_DEPLOYMENT_SUBTYPE}"
        for item in "${TEMP_SUBTYPES[@]}"; do
            trimmed=$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$trimmed" ]; then
                IDOL_DEPLOYMENT_SUBTYPES+=("$trimmed")
            fi
        done
    else
        echo -e "${YELLOW}🔍 Fetching available deployment subtypes from -l ...${NC}"

        MAP_OUTPUT=$("$SCRIPT_PATH" -l 2>&1)
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Failed to retrieve subtype list.${NC}"
            echo "$MAP_OUTPUT"
            exit 1
        fi

        echo -e "${YELLOW}Raw output from -l:${NC}"
        echo "$MAP_OUTPUT"
        echo ""

        # Bullet-aware parsing
        IDOL_DEPLOYMENT_SUBTYPES=()
        while IFS= read -r line; do
            if [[ "$line" == *•* ]]; then
                subtype=$(echo "$line" | sed 's/•//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk '{print $1}')
                if [[ "$subtype" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    IDOL_DEPLOYMENT_SUBTYPES+=("$subtype")
                fi
            fi
        done <<< "$MAP_OUTPUT"
    fi

    echo -e "${GREEN}✅ Will process ${#IDOL_DEPLOYMENT_SUBTYPES[@]} subtype(s):${NC}"
    for subtype in "${IDOL_DEPLOYMENT_SUBTYPES[@]}"; do
        echo -e "   ${ORANGE}•${NC} ${BOLD}${subtype}${NC}"
    done
    echo ""

    if [ ${#IDOL_DEPLOYMENT_SUBTYPES[@]} -eq 0 ]; then
        echo -e "${RED}❌ No valid subtypes found.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ STEP 1/5 PASSED — Subtype detection complete.${NC}"


    # =============================================================================
    # STEP 2/5 — Source IDOL environment variables
    # =============================================================================
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}▶ STEP 2/5 — Sourcing IDOL environment variables...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # =====================================================================
    # COPY pre-setup.sh to each detected subtype directory
    # =====================================================================
    echo -e "${YELLOW}📦 Backup pre-setup.sh to pre-setup-backup.sh...${NC}"
    BACKUP_DEST="${IDOL_BASE_PATH}/pre-setup-backup.sh"
    if cp -f "${IDOL_BASE_PATH}/pre-setup.sh" "$BACKUP_DEST"; then
        if [ -s "$BACKUP_DEST" ]; then
            echo -e "${GREEN}   ✅ Copied pre-setup.sh → ${ORANGE}${BACKUP_DEST}${NC}"
        else
            echo -e "${RED}   ❌ cp reported success but ${BACKUP_DEST} is missing or empty!${NC}"
            exit 1
        fi
    else
        echo -e "${RED}   ❌ Failed to copy pre-setup.sh → ${ORANGE}${BACKUP_DEST}${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ pre-setup.sh backuped to all ${BACKUP_DEST}.${NC}"
    echo ""

    source "${IDOL_BASE_PATH}/pre-setup.sh" && \
    echo -e "${GREEN}✅ STEP 2/5 PASSED — IDOL environment variables loaded.${NC}" || \
    { echo -e "${RED}❌ STEP 2/5 FAILED — Could not source pre-setup.sh. Aborting.${NC}"; exit 1; }

        # =====================================================================
        # SELF-TRUNCATE: Empty this file after it has been sourced
        # =====================================================================
        echo -e "${YELLOW}🧹 Truncating pre-setup.sh (self-cleanup)...${NC}"
        > "${IDOL_BASE_PATH}/pre-setup.sh"

        echo -e "${GREEN}✅ Pre-setup completed and file truncated.${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"


    # =============================================================================
    # STEP 3/5 — Initialise IDOL UI
    # =============================================================================
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}▶ STEP 3/5 — Initialising IDOL UI...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    bash "$IDOL_BASE_PATH/prepare-env.sh" --config && \
    echo -e "${GREEN}✅ STEP 3/5 PASSED — IDOL UI initialised successfully.${NC}" || \
    { echo -e "${RED}❌ STEP 3/5 FAILED — IDOL UI initialisation failed. Aborting.${NC}"; exit 1; }


    # =============================================================================
    # STEP 4/5 — Configure IDOL ports (Dynamic Multi-Subtype Support)
    # =============================================================================
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}▶ STEP 4/5 — Configuring IDOL ports for multiple deployment subtypes...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # NOTE: Subtype detection now happens in STEP 1/5 — IDOL_DEPLOYMENT_SUBTYPES
    # is already populated by this point.

    # ====================== EXECUTE FOR EACH SUBTYPE ======================
    echo -e "${YELLOW}🚀 Starting configuration for all subtypes...${NC}"

    for subtype in "${IDOL_DEPLOYMENT_SUBTYPES[@]}"; do
        echo -e "   ${ORANGE}→${NC} Processing subtype: ${BOLD}${YELLOW}${subtype}${NC}"

        if bash "$SCRIPT_PATH" -d "$subtype"; then
            echo -e "   ${GREEN}✅ Successfully configured ${subtype}${NC}"
        else
            echo -e "   ${RED}❌ Failed to configure ${subtype} (exit code: $?)${NC}"
            echo -e "${RED}   Aborting multi-subtype deployment.${NC}"
            exit 1
        fi
    done

    echo -e "${GREEN}✅ STEP 4/5 PASSED — All deployment subtypes configured successfully.${NC}"


    # =============================================================================
    # STEP 5/5 — Ollama Resource Estimator (LLM Integration)
    # =============================================================================
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}▶ STEP 5/5 — Ollama Resource Estimator (LLM Integration)...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    run_ollama_resource_estimator || \
    { echo -e "${RED}❌ STEP 5/5 FAILED — Ollama resource estimation failed. Aborting.${NC}"; exit 1; }
    echo -e "${GREEN}✅ STEP 5/5 PASSED — Ollama resource estimator finished.${NC}"


    # =============================================================================
    # COMPLETED SUCCESSFULLY
    # =============================================================================
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}🎉 ALL STEPS COMPLETED SUCCESSFULLY${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    exit 0
fi
