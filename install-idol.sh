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

log() {
    # Ensure log file exists
    if [ ! -f "$LOGFILE" ]; then
        touch "$LOGFILE"
    fi

    # Write log
    echo -e "${LIGHTER_YELLOW}$(date +"%Y-%m-%d %H:%M:%S")${NC} ${ORANGE}$1${NC}" | tee -a "$LOGFILE"
}

# Function to prompt user with Y/n question
prompt_yn() {
    local prompt="$1"
    local default="$2"
    local response

    echo -e "${YELLOW}"
    while true; do
        read -p "$prompt (Y/n): [default $default] " response
        response=${response:-${default}}

        # Normalize to lowercase to simplify case handling
        case "${response,,}" in
            y) return 0 ;;   # Yes
            n) return 1 ;;   # No
            *) echo -e "${RED}Please answer yes or no.${NC}" ;;  # Invalid input
        esac
    done
    echo -e "${NC}"
}

################
## Pre Setup
################
# Function to prefix entry in file
update_prefix_entry_in_file() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [update_prefix_entry_in_file] module${ORANGE}"

    local match_string="$1"
    local new_string="$2"
    local file_path="$3"

    # Check if match_string exists
    if ! grep -q -- "${match_string}" "$file_path"; then
        log "${CALLING_SCRIPT} ${RED}${match_string}' Not found in ${file_path} exiting...${NC}"
        log "${CALLING_SCRIPT} ${RED}${match_string}' Check in [nifi-templates/configuration-templates/] folder the content of [${file_path}]. exiting...${NC}"
    fi
    # Replace the whole line with match_string=new_string
    sed -i "s|${match_string}|${new_string}|g" "$file_path"
    log "${CALLING_SCRIPT} ${YELLOW}Replace match value ${ORANGE}[${match_string}]${YELLOW} with ${ORANGE}[${new_string}] ${YELLOW}in file ${ORANGE}[${file_path}]${NC}"
}

# Use the collected parameter values to update the [.env] file
update_idol_env_file(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [update_idol_env_file] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Use the collected parameter values to update the [.env] file...${NC}"

    # Update [.env] file
    TEMPLATE_PATH="./nifi-templates/configuration-templates/.env-template"
    TARGET_PATH="./${IDOL_SETUP_TYPE}/.env"
    cp $TEMPLATE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy [${TEMPLATE_PATH}] to [$TARGET_PATH] ${NC}"
    update_prefix_entry_in_file "SETUP-VERSION-PLACEHOLDER" "${IDOL_VERSION}" "${TARGET_PATH}"
    update_prefix_entry_in_file "HOST-IP-PLACEHOLDER" "${IDOL_NET_HOST_IP}" "${TARGET_PATH}"
}

# Use the collected parameter values to update the [docker-compose.bindmount.yml] file
update_idol_bindmount_file(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [update_idol_bindmount_file] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Use the collected parameter values to update the [docker-compose.bindmount.yml] file...${NC}"

    # Update [docker-compose.bindmount.yml] file
    TEMPLATE_PATH="./nifi-templates/configuration-templates/docker-compose.bindmount.yml-template"
    TARGET_PATH="./${IDOL_SETUP_TYPE}/docker-compose.bindmount.yml"
    cp $TEMPLATE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy [${TEMPLATE_PATH}] to [$TARGET_PATH] ${NC}"
    update_prefix_entry_in_file "DRIVER-PLACEHOLDER" "local" "${TARGET_PATH}"
    update_prefix_entry_in_file "DEVICE-PATH-PLACEHOLDER" "${IDOL_HOST_STORAGE_PATH}" "${TARGET_PATH}"
}

# Use the collected parameter values to update the [docker-compose.expose-ports.yml] file
update_idol_exposeports_file(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [update_idol_exposeports_file] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Use the collected parameter values to update the [docker-compose.expose-ports.yml] file...${NC}"

    # Update [docker-compose.expose-ports.yml] file
    TEMPLATE_PATH="./nifi-templates/configuration-templates/docker-compose.expose-ports.yml-template"
    TARGET_PATH="./${IDOL_SETUP_TYPE}/docker-compose.expose-ports.yml"
    cp $TEMPLATE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy [${TEMPLATE_PATH}] to [$TARGET_PATH] ${NC}"
    
    # Check if IDOL_ENABLE_SSL is NOT [TRUE]
    if [ "${IDOL_ENABLE_SSL}" != "TRUE" ]; then
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} IDOL SSL is ${RED}[DISABLE]${NC}"
    else
        update_prefix_entry_in_file "NIFI-PORT-PLACEHOLDER" "${IDOL_NIFI_PORT_NUMBER}" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Nifi port number is ${GREEN}[${IDOL_NIFI_PORT_NUMBER}].${NC}"
        update_prefix_entry_in_file "#DISABLE-PLACEHOLDER" "" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW} IDOL SSL is ${GREEN}[ENABLE]${NC}"
    fi
}

# Use the collected parameter values to update the [docker-compose.yml] file
update_idol_dockercompose_file(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [update_idol_dockercompose_file] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Use the collected parameter values to update the [docker-compose.yml] file...${NC}"

    # Update [docker-compose.yml] file
    TEMPLATE_PATH="./nifi-templates/configuration-templates/docker-compose.yml-template"
    TARGET_PATH="./${IDOL_SETUP_TYPE}/docker-compose.yml"
    cp $TEMPLATE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy [${TEMPLATE_PATH}] to [$TARGET_PATH] ${NC}"
    
    # Set [idol-containers-toolkit] persistent data
    if [ -d "$IDOL_PRESERVE_PATH" ]; then
        log "${CALLING_SCRIPT} ${YELLOW}Directory already exists, skipping: [${IDOL_PRESERVE_PATH}] ${NC}"
    else
        mkdir -p "$IDOL_PRESERVE_PATH"
        sudo chown $USER:$USER $IDOL_PRESERVE_PATH
        log "${CALLING_SCRIPT} ${YELLOW}Directory created: [${IDOL_PRESERVE_PATH}] ${NC}"
    fi

    # Get source [IDOL] persistence data path
    export source_persistent_data_path="./persistent-data"

    mkdir -p source_persistent_data_path

    # Copy [persistent-data/content] persistent data path
    cp -r $source_persistent_data_path/content $IDOL_PRESERVE_PATH
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy preserve to local [IDOL Content] subfolders ${ORANGE}[${IDOL_CONTENT_PATH}]${NC}"
    
    # Copy [persistent-data/find] persistent data path
    cp -r $source_persistent_data_path/find $IDOL_PRESERVE_PATH
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy preserve to local [IDOL Find] subfolders ${ORANGE}[${IDOL_FIND_PATH}]${NC}"


    # --------------------------------------------------------------------------

    # Update Content path Section
    update_prefix_entry_in_file "CONTENT-PATH-PLACEHOLDER" "${IDOL_CONTENT_PATH}" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Preserve to local Content cfg folder ${ORANGE}[${IDOL_CONTENT_PATH}]${NC}"

    # --------------------------------------------------------------------------

    # Update Find path Section 
    update_prefix_entry_in_file "FIND-PATH-PLACEHOLDER" "${IDOL_FIND_PATH}" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Preserve to local Find home folder ${ORANGE}[${IDOL_FIND_PATH}]${NC}"  
    
    # --------------------------------------------------------------------------
    
    # IDOL nifi persistence is [ENABLED]
    if [ "${IS_IDOL_NIFI_PRESERVE}" = "TRUE" ]; then
        update_prefix_entry_in_file "#IS-IDOL-NIFI-PRESERVE" "" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} IDOL nifi persistence is ${GREEN}[ENABLED]${NC}"

        update_prefix_entry_in_file "NIFI-PATH-PLACEHOLDER" "${IDOL_PRESERVE_NIFI_PATH}" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Nifi persistence path: ${GREEN}[${IDOL_PRESERVE_NIFI_PATH}].${NC}"
    else
        update_prefix_entry_in_file "- NIFI-PATH-PLACEHOLDER" "#HTTPS-DISABLE- NIFI-PATH-PLACEHOLDER" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Disable Nifi persistence path: ${GREEN}[Nif persistent is DISABLED].${NC}"   
    fi  

    # --------------------------------------------------------------------------

    # recursive, applying $USER to all files and subdirectories.
    sudo chown -R $USER:$USER $IDOL_PRESERVE_PATH

    # --------------------------------------------------------------------------

    # Update NIFI Section 
    update_prefix_entry_in_file "NIFI-IMAGE-NAME-PLACEHOLDER" "${IDOL_NIFI_DEPLOY_TYPE}" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} IDOL deployment type is ${ORANGE}[${IDOL_NIFI_DEPLOY_TYPE}]${NC}"

    update_prefix_entry_in_file "NIFI-FQDN-PLACEHOLDER" "${IDOL_HOST_FQDN}" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} IDOL FQDN is ${ORANGE}[${IDOL_HOST_FQDN}]${NC}"

    # Check if IDOL_ENABLE_SSL is [TRUE]
    if [ "${IDOL_ENABLE_SSL}" != "TRUE" ]; then
        update_prefix_entry_in_file "#HTTP-PLACEHOLDER" "" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} IDOL SSL is ${RED}[DISABLE]${NC}"
    else
        update_prefix_entry_in_file "#HTTPS-PLACEHOLDER" "" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW} IDOL SSL is ${GREEN}[ENABLE]${NC}"
        update_prefix_entry_in_file "NIFI-PORT-PLACEHOLDER" "${IDOL_NIFI_PORT_NUMBER}" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Nifi port number is ${GREEN}[${IDOL_NIFI_PORT_NUMBER}].${NC}"
       
        CERTS_PATH="./certs"
        update_prefix_entry_in_file "CERTS-PATH-PLACEHOLDER" "${CERTS_PATH}" "${TARGET_PATH}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Nifi port number is ${GREEN}[${IDOL_NIFI_PORT_NUMBER}].${NC}"

        # Copy updated secure nifi.properties file
        update_idol_secure_nifi_properties_file

        # Copy docker.compose.ssl.yml file
        update_idol_dockercompose_ssl_file

        # Copy ssl certificates files
        copy_ssl_certificates_to_idol_toolkit
    fi
}

# Use the collected parameter values to update the [nifi.properties] file
update_idol_secure_nifi_properties_file(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [update_idol_secure_nifi_properties_file] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Use the collected parameter values to update the [nifi.properties] file...${NC}"

    # Update [nifi.properties] file
    TEMPLATE_PATH="./nifi-templates/configuration-templates/nifi.properties-secure-template"
    TARGET_PATH="./${IDOL_SETUP_TYPE}/nifi.properties"
    cp $TEMPLATE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy [${TEMPLATE_PATH}] to [$TARGET_PATH] ${NC}"
 
    update_prefix_entry_in_file "#HTTPS-PLACEHOLDER" "" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ${LIGHTER_YELLOW} IDOL SSL is ${GREEN}[ENABLE]${NC}"

    update_prefix_entry_in_file "NIFI-PORT-PLACEHOLDER" "${IDOL_NIFI_PORT_NUMBER}" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Nifi port number is ${GREEN}[${IDOL_NIFI_PORT_NUMBER}].${NC}"
}

# Use the collected parameter values to update the [docker-compose.ssl.yml] file
update_idol_dockercompose_ssl_file(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [update_idol_dockercompose_ssl_file] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Use the collected parameter values to update the [docker-compose.ssl.yml] file...${NC}"

    # Update [docker-compose.ssl.yml] file
    TEMPLATE_PATH="./nifi-templates/configuration-templates/docker-compose.ssl.yml-template"
    TARGET_PATH="./${IDOL_SETUP_TYPE}/docker-compose.ssl.yml"
    cp $TEMPLATE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy [${TEMPLATE_PATH}] to [$TARGET_PATH] ${NC}"
 
    ### THIS SECTION IS DISABLE AS NO CHAGES NEED TO BE TO [docker-compose.ssl.yml] FILE
    ### update_prefix_entry_in_file "NIFI-IMAGE-NAME-PLACEHOLDER" "${IDOL_NIFI_DEPLOY_TYPE}" "${TARGET_PATH}"
    ### log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} IDOL deployment type is ${ORANGE}[${IDOL_NIFI_DEPLOY_TYPE}]${NC}"
}

# Copy ssl certificates files to [./idol-containers-toolkit/basic-idol/certs] folder
copy_ssl_certificates_to_idol_toolkit(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [copy_ssl_certificates_to_idol_toolkit] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Copy ${ORANGE}[SSL certificates files to [./idol-containers-toolkit/basic-idol/certs]${YELLOW} folder...${NC}"

    # Update [docker-compose.ssl.yml] file
    SOURCE_PATH="./idol-secure-setup/certs/"
    TARGET_PATH="${IDOL_TOOLKIT_PATH}/basic-idol/"
    cp -r $SOURCE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy ssl certificates from ${ORANGE}[${SOURCE_PATH}]${YELLOW} to ${ORANGE}[$TARGET_PATH] ${NC}"
}

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

# Function to Pull IDOL containers toolkit
pull_idol_containers_toolkit() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [pull_idol_containers_toolkit] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Pull IDOL containers toolkit...${NC}"

    # Ensure target directory exists
    mkdir -p $IDOL_TOOLKIT_PATH

    # Remove existing [idol-containers-toolkit] if it already exists
    rm -rf $IDOL_TOOLKIT_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Remove existing [idol-containers-toolkit] if it already exists, removing...${NC}"

    # Attempt to clone the repository
    if git clone https://github.com/opentext-idol/idol-containers-toolkit.git $IDOL_TOOLKIT_PATH; then
        log "${CALLING_SCRIPT} ${GREEN}Successfully cloned IDOL containers toolkit into /opt/idol${NC}"
    else
        log "${CALLING_SCRIPT} ${RED}Failed to clone IDOL containers toolkit${NC}"
        log "${CALLING_SCRIPT} ${RED}Aborting operation${NC}"
        exit 1
    fi

    # Update the [docker-compose.yml] file
    update_idol_dockercompose_file
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

###############################
## Main Upgrade IDOL Deployment
###############################
main_upgrade_idol_deployment() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [main_upgrade_idol_deployment] module${ORANGE}"

    # IDOL pre-deployment 
    idol_predeployment

    # Pull IDOL containers toolkit
    pull_idol_containers_toolkit

    # Upgrade IDOL Deployment Scripts
    upgrade_idol_deployment_scripts
}

#####################
## Setup Nif Registry 
#####################
setup_nifi_registry() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [setup_nifi_registry] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Setup Nif Registry...${NC}"


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

        # Deploy NiFi registry
        docker compose -f "${target_nifi_registry_persistent_data_path}/docker-compose.nifi-registry.yml" up -d
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Deploy [NIFI REGISTRY] executed ${NC}"

        log "${CALLING_SCRIPT} ${YELLOW}Setup Nif Registry is ${GREEN}[ENABLE]${NC}"
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

#############################
## Deploy IDOL License Server 
#############################
deploy_license_server() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [deploy_license_server] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Deploy IDOL License Server...${NC}"

    # Execute IDOL License Server deployment
    $IDOL_LICENSE_SERVER_PATH/deploy-license-server.sh
    rc=$?

    if [ $rc -eq 0 ]; then
        log "${CALLING_SCRIPT} ${YELLOW}Deploy IDOL License Server ${GREEN}[successfully]${NC}"
    else
        log "${CALLING_SCRIPT} ${RED}Failed to deploy IDOL License Server ${RED}failed with exit code: [$rc]${NC}"
        log "${CALLING_SCRIPT} ${RED}Aborting operation${NC}"
        exit 1
    fi
}

# ********************************** #
# ********** MAIN SECTION ********** #
# ********************************** #
main_upgrade_idol_deployment "$@"

setup_nifi_registry

deploy_license_server

echo ''
log "${CALLING_SCRIPT} ${YELLOW}Log files are located at ${ORANGE}[$(pwd)/logs] ${YELLOW}folder.${NC}"
