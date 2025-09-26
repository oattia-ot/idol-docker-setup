#!/bin/bash

# OpenText IDOL on Ubuntu 24.04

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHTER_YELLOW='\033[38;5;228m'
BLUE='\033[0;34m'
ORANGE='\033[0;38;5;214m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Execute script name
EXE_SCRIPT_NAME=$(basename "$0")

# Define global log file path and ensure log directory exists
export LOGFILE="./logs/${EXE_SCRIPT_NAME%.*}_$(date +"%Y%m%d").log"
mkdir -p $(dirname "$LOGFILE")

###################
## Script Utilities
###################
# Copy the snippet code 
source ./module/general-utilities.code

################
## Pre Setup
################
# Copy the snippet code 
source ./module/pre-setup.code 

######################
## IDOL pre-deployment
######################
# Function to IDOL pre-deployment 
idol_predeployment() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [idol_predeployment] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}IDOL pre-deployment...${NC}"

    # Display Info
    log "${CALLING_SCRIPT} ${GREEN}#########################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}##### IDOL - Installation           #####${NC}"
    log "${CALLING_SCRIPT} ${GREEN}#########################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}##### $(date +"%Y-%m-%d")                ${NC}"

    # Init log file
    if [ -f $LOGFILE ]; then
        rm -f $LOGFILE
        log "Old log deleted"
    fi
    log "Script started. Log path: ${LOGFILE}"

    # Use the collected parameter values to update the [.env] file
    update_idol_env_file

    # Use the collected parameter values to update the [docker-compose.bindmount.yml] file
    update_idol_bindmount_file

    # Use the collected parameter values to update the [docker-compose.expose-ports.yml] file
    update_idol_exposeports_file
}

# Function to Upgrade IDOL Deployment Scripts
upgrade_idol_deployment_scripts(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [upgrade_idol_deployment_scripts] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Upgrade IDOL Deployment Scripts...${NC}"

    # Copy IDOL [nifi.properties] Script
    cp "./${IDOL_SETUP_TYPE}/nifi.properties" "${IDOL_TOOLKIT_PATH}/basic-idol/nifi/nifi.properties"
    log "${CALLING_SCRIPT} ${YELLOW}Copy script ${ORANGE}[./nifi/nifi.properties]${NC}"

    # Copy IDOL Deployment Scripts
    cp "./${IDOL_SETUP_TYPE}/deploy.sh" "${IDOL_TOOLKIT_PATH}/basic-idol/deploy.sh"
    log "${CALLING_SCRIPT} ${YELLOW}Copy script ${ORANGE}[deploy.sh]${NC}"

    cp "./${IDOL_SETUP_TYPE}/.env" "${IDOL_TOOLKIT_PATH}/basic-idol/.env"
    log "${CALLING_SCRIPT} ${YELLOW}Copy script ${ORANGE}[.env]${NC}"
    
    cp "./${IDOL_SETUP_TYPE}/docker-compose.yml" "${IDOL_TOOLKIT_PATH}/basic-idol/docker-compose.yml"
    log "${CALLING_SCRIPT} ${YELLOW}Copy script ${ORANGE}[docker-compose.yml]${NC}"

    cp "./${IDOL_SETUP_TYPE}/docker-compose.ssl.yml" "${IDOL_TOOLKIT_PATH}/basic-idol/docker-compose.ssl.yml"
    log "${CALLING_SCRIPT} ${YELLOW}Copy script ${ORANGE}[docker-compose.ssl.yml]${NC}"

    cp "./${IDOL_SETUP_TYPE}/docker-compose.bindmount.yml" "${IDOL_TOOLKIT_PATH}/basic-idol/docker-compose.bindmount.yml"
    log "${CALLING_SCRIPT} ${YELLOW}Copy script ${ORANGE}[docker-compose.bindmount.yml]${NC}"

    cp "./${IDOL_SETUP_TYPE}/docker-compose.expose-ports.yml" "${IDOL_TOOLKIT_PATH}/basic-idol/docker-compose.expose-ports.yml"
    log "${CALLING_SCRIPT} ${YELLOW}Copy script ${ORANGE}[docker-compose.expose-ports.yml]${NC}"
}

# Function to verify IDOL environment variables
verify_idol_environment() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [verify_idol_environment] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Verify IDOL environment variables...${NC}"
    
    local count=$(env | grep IDOL | wc -l)
    
    if [ $count -gt 5 ]; then
        log "${CALLING_SCRIPT} ${YELLOW}Found ${GREEN}[${count}]${YELLOW} IDOL variables${NC}"
        return 0
    else
        log "${CALLING_SCRIPT} ${YELLOW}Only ${RED}Exit - [${count}] IDOL variables found ${YELLOW}(expected more)${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}Execute ${ORANGE}[source ./env/export-env-variables.sh]${YELLOW} rerun the installation script${NC}"
        exit 1
    fi
}

###############################
## Main Upgrade IDOL Deployment
###############################
main_upgrade_idol_deployment() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [main_upgrade_idol_deployment] module${ORANGE}"

    # verify that [env | grep IDOL] returns more than 5 rows if not EXIT
    verify_idol_environment

    # IDOL pre-deployment 
    idol_predeployment

    # Upgrade IDOL Deployment Scripts
    upgrade_idol_deployment_scripts
}

#######################
## Deploy Nifi Registry 
#######################
deploy_nifi_registry() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [deploy_nifi_registry] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Deploy Nifi Registry...${NC}"


    # Get source [NIFI] persistence data path
    export source_nifi_registry_persistent_data_path="./utilities/nifi-registry-setup/registry-ver2-persistent-data"

    # Copy preparation [persistent-data/nifi-registry] persistent data path
    export target_nifi_registry_persistent_data_path="${IDOL_TOOLKIT_PATH}/persistent-data/nifi-registry"
    mkdir -p $target_nifi_registry_persistent_data_path

    # Copy [NIFI REGISTRY] persistent data path
    if [ "$IS_IDOL_NIFI_REGISTRY_PRESERVE" = "TRUE" ]; then
        # list of folders to copy
        mkdir -p $target_nifi_registry_persistent_data_path
        for d in conf database flow_storage; do
        if [ -d "$source_nifi_registry_persistent_data_path/$d" ]; then
            echo "Copying $d..."
            cp -r "$source_nifi_registry_persistent_data_path/$d" "$target_nifi_registry_persistent_data_path/"
        else
            echo "Skipping $d, not found in source."
        fi
        done
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy [NIFI REGISTRY] preserve data to local location: ${ORANGE}[${target_nifi_registry_persistent_data_path}/conf]${NC}"
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy [NIFI REGISTRY] preserve data to local location: ${ORANGE}[${target_nifi_registry_persistent_data_path}/database]${NC}"
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy [NIFI REGISTRY] preserve data to local location: ${ORANGE}[${target_nifi_registry_persistent_data_path}/flow_storage]${NC}"

        # Copy [nifi registry] deployment scripts
        cp "./utilities/nifi-registry-setup/docker-compose.nifi-registry.yml" $target_nifi_registry_persistent_data_path
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy [NIFI REGISTRY] preserve data script: ${ORANGE}[docker-compose.nifi-registry.yml]${NC}"
        cp "./utilities/nifi-registry-setup/deploy-nifi-registry.sh" $target_nifi_registry_persistent_data_path
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy [NIFI REGISTRY] preserve data script: ${ORANGE}[deploy-nifi-registry.sh]${NC}"

        # Create docker network for nifi registry
        docker network create nifi-registry-network

        # Deploy NiFi registry
        docker compose -f "${target_nifi_registry_persistent_data_path}/docker-compose.nifi-registry.yml" up -d
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
        log "${CALLING_SCRIPT} ${YELLOW} Password: ${ORANGE}Nifi-Admin1!    ${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}====================================${NC}"
        echo ''

        return 0
    fi
    log "${CALLING_SCRIPT} ${YELLOW}Setup Nif Registry is ${RED}[DISABLE]${NC}"
}

# ********************************** #
# ********** MAIN SECTION ********** #
# ********************************** #
main_upgrade_idol_deployment "$@"

# Deploy Nifi Registry
deploy_nifi_registry

echo ''
log "${CALLING_SCRIPT} ${YELLOW}Log files are located at ${ORANGE}[$(pwd)/logs] ${YELLOW}folder.${NC}"
