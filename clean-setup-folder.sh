#!/bin/bash

# OpenText IDOL on Ubuntu 24.04

# ─────────────────────────────────────────────
# Color codes
# ─────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'

# ─────────────────────────────────────────────
# Helpers — no LOG_FILE, stdout only
# ─────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "\n${BOLD}${BLUE}── $1 ──${NC}"; }

# Remove a path and report status
# Usage: remove <path> [description]
remove() {
  local target="$1"
  local label="${2:-$1}"

  # compgen -G correctly handles glob patterns
  if ! compgen -G "$target" > /dev/null 2>&1; then
    warn "$label (not found)"
    return
  fi

  # Unquoted $target allows glob expansion for rm
  if sudo rm -rf $target 2>/dev/null; then
    success "$label"
  else
    error "$label (failed to remove)"
  fi
}

# Truncate a file and report status
truncate_file() {
  local target="$1"
  local label="${2:-$1}"

  if [[ ! -f "$target" ]]; then
    warn "$label (not found)"
    return
  fi

  if sudo truncate -s 0 "$target" 2>/dev/null; then
    success "$label (truncated)"
  else
    error "$label (failed to truncate)"
  fi
}

# ─────────────────────────────────────────────
# Cleaning and Removing Setup Files
# ─────────────────────────────────────────────
source ./pre-setup.sh 
section "Cleaning and Removing Setup Files"

truncate_file "./pre-setup.sh"                                             "truncate ./pre-setup.sh"
truncate_file "utilities/ui-config/backend/setup-scripts/pre-setup.sh"     "truncate ./pre-setup.sh"
remove "./pre-setup-backup.sh"                                             "pre-setup-backup.sh"
remove "idol-containers-toolkit/basic-idol/.env"                           "basic-idol .env"
remove "idol-containers-toolkit/data-admin/.env"                           "data-admin .env"
remove "idol-containers-toolkit/rich-media/.env"                           "rich-media .env"
remove "idol-containers-toolkit/basic-idol/idol_ssl.env"                   "basic-idol idol_ssl.env"
remove "idol-containers-toolkit/data-admin/idol_ssl.env"                   "data-admin idol_ssl.env"
remove "idol-containers-toolkit/rich-media/idol_ssl.env"                   "rich-media idol_ssl.env"
remove "idol-containers-toolkit/basic-idol/docker-compose*"                "basic-idol docker-compose*"
remove "idol-containers-toolkit/data-admin/docker-compose*"                "data-admin docker-compose*"
remove "idol-containers-toolkit/rich-media/docker-compose*"                "rich-media docker-compose*"
remove "idol-containers-toolkit/basic-idol/pre-setup.sh"                   "basic-idol pre-setup.sh"
remove "idol-containers-toolkit/rich-media/pre-setup.sh"                   "rich-media pre-setup.sh"
remove "idol-containers-toolkit/data-admin/pre-setup.sh"                   "data-admin pre-setup.sh"
remove "idol-containers-toolkit/data-admin/llm-sandbox/pre-setup.sh"       "llm-sandbox pre-setup.sh"
remove ".git"                                                              ".git/*"
remove "env/*"                                                             "env/*"
remove "env/.[!.]*"                                                        "env/.[!.]*"
remove "logs/*"                                                            "logs/*"
remove "persistent-data/qms/cfg/logs/*"                                    "persistent-data/qms/cfg/logs/*"
remove "persistent-data/find/basic-idol/home/logs/*"                       "persistent-data/find/basic-idol/home/logs/*"
remove "persistent-data/find/data-admin/home/logs/*"                       "persistent-data/find/data-admin/home/logs/*"
remove "persistent-data/find/rich-media/home/logs/*"                       "persistent-data/find/rich-media/home/logs/*"
remove "persistent-data/templates/find/basic-idol/home/logs/*"             "persistent-data/templates/find/basic-idol/home/logs/*"
remove "persistent-data/templates/find/data-admin/home/logs/*"             "persistent-data/templates/find/data-admin/home/logs/*"
remove "persistent-data/templates/find/rich-media/home/logs/*"             "persistent-data/templates/find/rich-media/home/logs/*"
remove "./utilities/generate-ssl-certs/logs"                               "generate-ssl-certs logs"
remove "./utilities/generate-ssl-certs/ssl"                                "generate-ssl-certs ssl"
remove "./idol-licenseserver/ssl"                                          "idol-licenseserver ssl/*"
remove "./idol-containers-toolkit/basic-idol/ssl"                          "basic-idol ssl/*"
remove "./idol-containers-toolkit/data-admin/ssl"                          "data-admin ssl/*"
remove "./idol-containers-toolkit/rich-media/ssl"                          "rich-media ssl/*"
remove "./idol-licenseserver/docker-compose.licenseserver.yml"             "idol-licenseserver docker-compose.licenseserver.yml"
remove "./idol-licenseserver/LicenseServer_*"                              "idol-licenseserver LicenseServer_*"
remove "./templates/license-server/template-script/LicenseServer_*"        "templates/license-server/template-script LicenseServer_*"
remove "./persistent-data/nifi-registry/flow_storage"                      "nifi flow_storage/*"
remove "./persistent-data/nifi-registry/flow_storage/.git"                 "nifi flow_storage/.git"
remove "./persistent-data/nifi-flows/user-flows/*"                         "nifi-flows/user-flows/*"
remove "./utilities/nifi-registry-setup/registry/providers.xml"            "nifi-registry providers.xml"
remove "./utilities/nifi-registry-setup/docker-compose.nifi-registry.yml"  "docker-compose.nifi-registry.yml"
remove "./shared-folder/nifi-connectors/*"                                 "shared-folder/nifi-connectors/*"
remove "./shared-folder/richmedia-packages/*"                              "shared-folder/richmedia-packages/*"

# ─────────────────────────────────────────────
# Delete Docker images & Harbor registry data
# ─────────────────────────────────────────────
section "Delete Docker images"

remove "./utilities/minikube-setup/logs"                                   "minikube-setup logs"
remove "./utilities/build-idol-images/input-files"                         "utilities/build-idol-images/input-files/*"
remove "./utilities/build-idol-images/output-image"                        "utilities/build-idol-images/output-image/*"
remove "./utilities/harbor-setup/env/*"                                    "utilities/harbor-setup/env/*"
remove "./llm-models"                                                      "llm-models*"

# ─────────────────────────────────────────────
# Delete LLAMA Resources
# ─────────────────────────────────────────────
section "Delete LLAMA Resources"

remove "./idol-containers-toolkit/data-admin/llm-sandbox/logs"                      "idol-containers-toolkit/data-admin/llm-sandbox/logs/*"
remove "./idol-containers-toolkit/data-admin/llm-sandbox/default-models.json.bak.*" "idol-containers-toolkit/data-admin/llm-sandbox/default-models.json.bak.*"
remove "./idol-containers-toolkit/data-admin/llm-sandbox/models"                    "idol-containers-toolkit/data-admin/llm-sandbox models/*"
remove "./idol-containers-toolkit/data-admin/llm-sandbox/open-webui"                "idol-containers-toolkit/data-admin/llm-sandbox/open-webui/*"
remove "./persistent-data/llm-sandbox/logs"                                         "llm-sandbox logs/*" 
remove "./persistent-data/nifi-flows/default-models.json"                           "temporary default-models.json in [nifi-flows] folder" 

remove "./persistent-data/answerserver/cfg/answerserver.cfg"                        "answerserver/cfg/answerserver.cfg"
remove "./persistent-data/answerserver/rag/ollama_server.py"                        "answerserver/rag/ollama_server.py"

section "Delete Public LLM API KEY"
sed -i 's/^API_KEY[[:space:]]*=.*$/API_KEY = "LLM-API-KEY-PLACEHOLDER"  # Replace with your actual API key in production/' ./persistent-data/answerserver/rag/grok/grok4.py

# Force delete LLM model path (bypasses remove() function)
if [[ -n "$IDOL_LLM_MODEL_PATH" ]]; then
    if [[ "$IDOL_LLM_MODEL_PATH" == "." ]]; then
        warn "IDOL_LLM_MODEL_PATH=. (current directory) - skipping deletion for safety"
    #elif sudo rm -rf "$IDOL_LLM_MODEL_PATH" 2>/dev/null; then
    #    success "llm-sandbox llm-models folder/* ($IDOL_LLM_MODEL_PATH)"
    #else
    #    error "llm-sandbox llm-models folder/* (failed)"
    fi
else
    warn "IDOL_LLM_MODEL_PATH is empty - cannot delete"
fi

# ─────────────────────────────────────────────
# Remove IDOL Docker Volumes
# ─────────────────────────────────────────────
section "Remove IDOL Docker Volumes"
 
REMOVE_SCRIPT="$(dirname "$0")/remove-idol-volumes.sh"
VOLUMES=$(docker volume ls -q 2>/dev/null | grep idol-demo || true)
 
if [ -z "$VOLUMES" ]; then
    warn "No idol-demo Docker volumes found. Nothing to clean up."
elif [ -f "$REMOVE_SCRIPT" ]; then
    info "Found idol-demo volumes:"
    docker volume ls 2>/dev/null | grep idol-demo
    echo ""
    echo -e "${YELLOW}[?]${NC}     idol-demo volumes detected. Run remove-idol-volumes.sh now? [y/N]"
    read -rp "      " RUN_SCRIPT
    if [[ "$RUN_SCRIPT" == "y" || "$RUN_SCRIPT" == "Y" ]]; then
        info "Executing remove-idol-volumes.sh..."
        bash "$REMOVE_SCRIPT"
        SCRIPT_EXIT=$?
        if [ $SCRIPT_EXIT -eq 0 ]; then
            success "remove-idol-volumes.sh completed"
        else
            error "remove-idol-volumes.sh exited with code $SCRIPT_EXIT"
        fi
    else
        warn "Skipped remove-idol-volumes.sh — volumes were not removed."
    fi
else
    warn "remove-idol-volumes.sh not found next to this script — skipping volume removal."
fi

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────
section "Done"
