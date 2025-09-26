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

# Enable/Disable tracing script messages
SILENT_MODE="false"

# Execute script name
EXE_SCRIPT_NAME=$(basename "$0")

# Define global log file path and ensure log directory exists
export LOGFILE="./logs/${EXE_SCRIPT_NAME%.*}_$(date +"%Y%m%d").log"
mkdir -p "$(dirname "$LOGFILE")"

# Ensure env directory exists
export IDOL_ENV="./env/env_variables_$(date +"%Y%m%d").env"
mkdir -p "$(dirname "$IDOL_ENV")"

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

############################
## Setup IDOL License Server
############################
# Function to get License Server IP address
get_license_server_ip() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [get_license_server_ip] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Get License Server IP address...${NC}"

    local url="$1"
    
    if [ -z "$url" ]; then
        log "${CALLING_SCRIPT} URL parameter is required: ${RED}[ERROR]${NC}"
        log "${CALLING_SCRIPT} ${RED}Aborting operation${NC}"
        return 1
    fi
    
    # Display License Server URL
    log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}License Server URL is:${ORANGE} [$url]${NC}"

    # Extract & Display License Server URL 
    local domain=$(echo "$url" | sed -E 's|https?://([^:/]+).*|\1|')
    log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}License Server Domain is:${ORANGE} [$domain]${NC}"
    
    # Get IP using Python
    local ip=$(python3 -c "
import socket
try:
    ip = socket.gethostbyname('$domain')
    print(ip)
except:
    pass
" 2>/dev/null)
    
    if [ -n "$ip" ]; then
        # Check if IP is localhost and exit if it is
        if [ "$ip" = "127.0.0.1" ]; then
            ip=$IDOL_NET_HOST_IP
        fi
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}License Server IP is:${ORANGE} [$ip]${NC}"

        update_file_row "$IDOL_ENV" "export IDOL_LICENSE_SERVER_URL" "${url}" "=" "$SILENT_MODE" "$SILENT_MODE"
        update_file_row "$IDOL_ENV" "export IDOL_LICENSE_SERVER_DOMAIN" "${domain}" "=" "$SILENT_MODE" "$SILENT_MODE"
        update_file_row "$IDOL_ENV" "export IDOL_LICENSE_SERVER_IP" "${ip}" "=" "$SILENT_MODE" "$SILENT_MODE"

        return 0
    else
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Failed to resolve IP for License Server domain:${RED} [$domain]${NC}"
        return 1
    fi
}

# Use the collected parameter values to update the [docker-compose.yml] file
update_idol_dockercompose_file(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [update_idol_dockercompose_file] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Use the collected parameter values to update the [docker-compose.yml] file...${NC}"

    # Update [docker-compose.yml] file
    TEMPLATE_PATH="./script-templates/configuration-templates/docker-compose.yml-template"
    TARGET_PATH="./${IDOL_SETUP_TYPE}/docker-compose.yml"
    cp $TEMPLATE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy [${TEMPLATE_PATH}] to [$TARGET_PATH] ${NC}"

    # Set [idol-containers-toolkit] persistent data
    if [ -d "$IDOL_PRESERVE_PATH" ]; then
        log "${CALLING_SCRIPT} ${YELLOW}Directory already exists, skipping: [${IDOL_PRESERVE_PATH}] ${NC}"
    elif [ "$IS_IDOL_PRESERVE" = "TRUE" ]; then
        sudo mkdir -p "$IDOL_PRESERVE_PATH"
        sudo chown -R $USER:$USER $IDOL_PRESERVE_PATH
        log "${CALLING_SCRIPT} ${YELLOW}Directory created: [${IDOL_PRESERVE_PATH}] ${NC}"
    fi

    # Get source [IDOL] persistence data path
    source_persistent_data_path="./persistent-data"

    mkdir -p $source_persistent_data_path

    # Copy [persistent-data/content] persistent data path
    sudo cp -r $source_persistent_data_path/content $IDOL_PRESERVE_PATH
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy preserve to local [IDOL Content] subfolders ${ORANGE}[${IDOL_PRESERVE_CONTENT_PATH}]${NC}"
    
    # Copy [persistent-data/find] persistent data path
    sudo cp -r $source_persistent_data_path/find $IDOL_PRESERVE_PATH
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Copy preserve to local [IDOL Find] subfolders ${ORANGE}[${IDOL_PRESERVE_FIND_PATH}]${NC}"


    # --------------------------------------------------------------------------

    # Update Content path Section
    update_prefix_entry_in_file "CONTENT-PATH-PLACEHOLDER" "${IDOL_PRESERVE_CONTENT_PATH}" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Preserve to local Content cfg folder ${ORANGE}[${IDOL_PRESERVE_CONTENT_PATH}]${NC}"

    # --------------------------------------------------------------------------

    # Update Find path Section 
    update_prefix_entry_in_file "FIND-PATH-PLACEHOLDER" "${IDOL_PRESERVE_FIND_PATH}" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Preserve to local Find home folder ${ORANGE}[${IDOL_PRESERVE_FIND_PATH}]${NC}"  
    
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

# Function to Pull IDOL containers toolkit
pull_idol_containers_toolkit() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [pull_idol_containers_toolkit] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Pull IDOL containers toolkit...${NC}"

    # Attempt to clone the repository
    if git clone https://github.com/opentext-idol/idol-containers-toolkit.git $IDOL_TOOLKIT_PATH; then
        log "${CALLING_SCRIPT} ${GREEN}Successfully cloned IDOL containers toolkit into /opt/idol${NC}"
    else
        log "${CALLING_SCRIPT} ${RED}Failed to clone IDOL containers toolkit${NC}"
        log "${CALLING_SCRIPT} ${RED}Aborting operation${NC}"
        exit 1
    fi
}

# Function to get access to IDOL License Server
setup_idol_licenseserver() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [setup_idol_licenseserver] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Setup License Server...${NC}"

    # Create a sourced script with shebang 
    (echo "#!/bin/bash"; echo ''; cat "$IDOL_ENV") > ./env/export-env-variables.sh

    # Display Info
    log "${CALLING_SCRIPT} ${GREEN}#########################################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}##### IDOL License Server - Collect Setup Parameters ####${NC}"
    log "${CALLING_SCRIPT} ${GREEN}#########################################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}##### $(date +"%Y-%m-%d")                ${NC}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Before starting the License Server setup, prepare the following information:${NC}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW}     1) Docker images access token for IDOL images.                          ${NC}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW}     2) License key for IDOL, generated specifically for your system.        ${NC}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW}        To obtain this key, you must provide:                                ${NC}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW}         2.1) Host name and full path to the licensekey.dat file             ${NC}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW}         2.2) MAC address of the host machine                                ${NC}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW}         2.3) Email address                                                  ${NC}"
    log "${CALLING_SCRIPT} ⚠️ ${YELLOW}     The setup cannot proceed without these details.                                 ${NC}"

    # Create a temporary folder to store the license server info
    TMP_DIR=$(mktemp -d)

    # Reset License Server Info file
    echo "Note: IDOL personal access token [dckr_pat_*************-*************] must be provided during setup execution." > "${TMP_DIR}/idol_licenseserver_info.txt"
    echo "Note: IDOL License Server key file [licensekey.dat] must be provided during setup execution." >> "${TMP_DIR}/idol_licenseserver_info.txt"
    echo "IDOL License Server Info" >> "${TMP_DIR}/idol_licenseserver_info.txt"
    echo "------------------------" >> "${TMP_DIR}/idol_licenseserver_info.txt"
    
    # Collect license server setup parameters
    prompt_while_valid_input "text" "Enter the host name for the IDOL license: " "$(hostname -f)" "Save IDOL licenseserver [HOSTNAME]" IDOL_LICENSE_KEY_HOSTNAME 
    echo "Host Name: ${IDOL_LICENSE_KEY_HOSTNAME}" >> "${TMP_DIR}/idol_licenseserver_info.txt"
    log "${CALLING_SCRIPT} IDOL Host Name is set to: ${YELLOW}[$IDOL_LICENSE_KEY_HOSTNAME]${NC}"
    prompt_while_valid_input "text" "Enter IDOL email" "JohnDow@address.com" "Save IDOL licenseserver [MAIL]" IDOL_LICENSE_KEY_MAIL "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"
    echo "Mail: ${IDOL_LICENSE_KEY_MAIL}" >> "${TMP_DIR}/idol_licenseserver_info.txt"
    log "${CALLING_SCRIPT} IDOL Email address is set to: ${YELLOW}[$IDOL_LICENSE_KEY_MAIL]${NC}"
    prompt_while_valid_input "text" "Enter IDOL MAC address" "00:15:5d:73:9d:03" "Save IDOL licenseserver [MAC]" IDOL_LICENSE_KEY_MAC "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
    echo "MAC : ${IDOL_LICENSE_KEY_MAC}" >> "${TMP_DIR}/idol_licenseserver_info.txt"
    log "${CALLING_SCRIPT} IDOL MAC address is set to: ${YELLOW}[$IDOL_LICENSE_KEY_MAC]${NC}"
    
    # Get IDOL personal access token
    while true; do
        prompt_while_valid_input "text" "Enter IDOL Docker Personal Access token" "dckr_pat_XXXXX" "DO NOT SAVE IDOL docker [KEY]" IDOL_LICENSE_KEY_TOKEN "^dckr[_A-Za-z0-9-]+$"
        log "${CALLING_SCRIPT} IDOL personal access token is set to: ${YELLOW}[dckr_pat_*************-*************]${NC}"

        # Validate IDOL Docker access token
echo "aaaaaaaaaaaaaaaa ---> ${IDOL_LICENSE_KEY_TOKEN}"
        if echo "$IDOL_LICENSE_KEY_TOKEN" | docker login --username microfocusidolreadonly --password-stdin; then
            echo -e "${GREEN}Docker access token is valid.${NC}"
            log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}IDOL Docker access token is: ${GREEN}[validate]${NC}"
            break
        else
            echo -e "${RED}Invalid Docker access token. Please try again.${NC}"
        fi
    done
    
    # Copy and rename [e.g LicenseServer_25.3.0_LINUX_X86_64] to [licenseserver]
    prompt_while_valid_input "file" "Enter IDOL license key file path" "licensekey.dat" "licensekey.dat" source_licensekey_file 
    log "${CALLING_SCRIPT} Source IDOL license key location path is set to: ${YELLOW}[$source_licensekey_file]${NC}"
    IDOL_LICENSE_KEY_SRC_PATH=$source_licensekey_file
    IDOL_LICENSE_SERVER_PATH="${IDOL_TOOLKIT_PATH}/licenseserver-setup"
    
    # Remove existing [idol-containers-toolkit] if it already exists
    sudo rm -rf $IDOL_TOOLKIT_PATH

     # Pull IDOL containers toolkit
    pull_idol_containers_toolkit

    # Ensure target directory exists
    mkdir -p $IDOL_LICENSE_SERVER_PATH
    cp -f "$TMP_DIR/idol_licenseserver_info.txt" "$IDOL_LICENSE_SERVER_PATH/idol_licenseserver_info.txt"

    # Update the [docker-compose.yml] file
    update_idol_dockercompose_file

    # Ensure target directory exists
    mkdir -p $IDOL_LICENSE_SERVER_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Remove existing [idol-containers-toolkit] if it already exists, recreating...${NC}"

    # Copy the entire licenseserver-setup folder
    cp -a "./licenseserver-setup/." "$IDOL_LICENSE_SERVER_PATH/"
    log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Copied licenseserver-setup and renamed License Server to: ${GREEN}[${IDOL_LICENSE_SERVER_PATH}]${NC}"

    # Update [docker-compose.licenseserver.yml] file
    TEMPLATE_PATH="./script-templates/configuration-templates/docker-compose.licenseserver.yml-template"
    TARGET_PATH="${IDOL_LICENSE_SERVER_PATH}/docker-compose.licenseserver.yml"
    cp $TEMPLATE_PATH $TARGET_PATH
    log "${CALLING_SCRIPT} ${YELLOW}Copy [${TEMPLATE_PATH}] to [$TARGET_PATH] ${NC}"

    # --------------------------------------------------------------------------

    # Update Content path Section
    update_prefix_entry_in_file "MAC-ADDRESS-PLACEHOLDER" "${IDOL_LICENSE_KEY_MAC}" "${TARGET_PATH}"
    log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Update IDOL License MAC address: ${ORANGE}[${IDOL_LICENSE_KEY_MAC}]${NC}"

    # --------------------------------------------------------------------------

    # Read source file content and pass as parameter
    source_content=$(cat "$IDOL_LICENSE_KEY_SRC_PATH")
    # Save to file
    write_to_file "$IDOL_LICENSE_SERVER_PATH/LicenseServer_25.3.0_LINUX_X86_64/licensekey.dat" "$source_content"
    log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Copy the [${IDOL_LICENSE_KEY_SRC_PATH}] file to: ${GREEN}[${IDOL_LICENSE_SERVER_PATH}]${NC}"          

    export IDOL_LICENSE_KEY_HOSTNAME=$IDOL_LICENSE_KEY_HOSTNAME
    export IDOL_LICENSE_KEY_MAIL=$IDOL_LICENSE_KEY_MAIL
    export IDOL_LICENSE_KEY_MAC=$IDOL_LICENSE_KEY_MAC
    export IDOL_LICENSE_KEY_SRC_PATH=$IDOL_LICENSE_KEY_SRC_PATH
    export IDOL_LICENSE_SERVER_PATH=$IDOL_LICENSE_SERVER_PATH
    update_file_row "$IDOL_ENV" "export IDOL_LICENSE_KEY_HOSTNAME" "${IDOL_LICENSE_KEY_HOSTNAME}" "=" "$SILENT_MODE" "$SILENT_MODE"
    update_file_row "$IDOL_ENV" "export IDOL_LICENSE_KEY_MAIL" "${IDOL_LICENSE_KEY_MAIL}" "=" "$SILENT_MODE" "$SILENT_MODE"
    update_file_row "$IDOL_ENV" "export IDOL_LICENSE_KEY_MAC" "${IDOL_LICENSE_KEY_MAC}" "=" "$SILENT_MODE" "$SILENT_MODE"
    update_file_row "$IDOL_ENV" "export IDOL_LICENSE_KEY_SRC_PATH" "${IDOL_LICENSE_KEY_SRC_PATH}" "=" "$SILENT_MODE" "$SILENT_MODE"
    update_file_row "$IDOL_ENV" "export IDOL_LICENSE_SERVER_PATH" "${IDOL_LICENSE_SERVER_PATH}" "=" "$SILENT_MODE" "$SILENT_MODE"
    echo ''
    echo -e "${YELLOW}Select the IDOL License Server Connecting Mode: ${NC}"
    echo -e "${YELLOW}1) Deploy an entirely new instance of License Server ${ORANGE}[default]  ${NC}"
    echo -e "${YELLOW}2) Provide an active License Server URL ${NC}"
    local selection
    echo -e "${BLUE}--------------------${YELLOW}"
    while true; do
        read -p "Enter selection [1]: " selection
        selection=${selection:-1}
        case $selection in
            1)
                export IDOL_LICENSE_SERVER_MODE=NEW

                IDOL_LICENSE_SERVER_URL="http://localhost:20000/a=getlicenseinfo"
                # Deploy a new IDOL License Server
                deploy_new_license_server "$IDOL_LICENSE_SERVER_PATH" "$IDOL_LICENSE_SERVER_URL"

                break
                ;;
            2)
                export IDOL_LICENSE_SERVER_MODE=URL
             
                log "${CALLING_SCRIPT} ⚠️  ${RED}Integration with an existing external IDOL License Server has not been fully validated at this stage!!!${NC}"
                # Ask if user wants to proceed with the external License Server
                if prompt_yn "Do you want to proceed with the external License Server?" "Y"; then   
                    echo -e "${PURPLE}"
                    read -p "Enter the license server URL [Format: http://<server>:<port>] (e.g., http://license.company.com:20000):  " license_server_url
                    IDOL_LICENSE_SERVER_URL="${license_server_url}/a=getlicenseinfo"

                    # Get License Server IP address
                    get_license_server_ip $license_server_url

                    break
                else 
                    echo -e "${YELLOW}"
                    continue
                fi
                ;;
            *)
                echo -e "${RED}Invalid selection. Please choose 1, or 2.${NC}"
                ;;
        esac
    done

    update_file_row "$IDOL_ENV" "export IDOL_LICENSE_SERVER_MODE" "${IDOL_LICENSE_SERVER_MODE}" "=" "$SILENT_MODE" "$SILENT_MODE"
    log "${CALLING_SCRIPT} License Server Connecting Mode: ${ORANGE}$IDOL_LICENSE_SERVER_MODE${NC}"
    update_file_row "$IDOL_ENV" "export IDOL_LICENSE_SERVER_URL" "${IDOL_LICENSE_SERVER_URL}" "=" "$SILENT_MODE" "$SILENT_MODE"
    log "${CALLING_SCRIPT} License Server Connecting URL: ${ORANGE}$IDOL_LICENSE_SERVER_URL${NC}" 

    # Check License Server validation
    if curl -s $IDOL_LICENSE_SERVER_URL | grep -q "LicenseInfo"; then
        log "${CALLING_SCRIPT} License Server info is: ${GREEN}[VALID]${NC}"
        update_file_row "$IDOL_ENV" "export IS_IDOL_VALIDATION_MET" "TRUE" "=" "$SILENT_MODE" "$SILENT_MODE"
        echo ''
    else
        log "${CALLING_SCRIPT} License Server info is: ${RED}[NOT VALID]${NC}"
        log "${CALLING_SCRIPT} ${RED}Aborting operation${NC}"
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW} Consider to copy maually the [licensekey.dat] to target: ${RED}[${IDOL_LICENSE_SERVER_KEY_PATH}/LicenseServer_25.3.0_LINUX_X86_64]${NC}"
        update_file_row "$IDOL_ENV" "export IS_IDOL_VALIDATION_MET" "ERROR" "=" "$SILENT_MODE" "$SILENT_MODE"
        exit 1
    fi
}

#################################
## Deploy new IDOL License Server 
#################################
deploy_new_license_server(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [deploy_new_license_server] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Deploy new IDOL License Server...${NC}"

    local file_path="$1"
    local license_server_url="$2"
    
    docker network create idol-network 
    docker compose -f $file_path/docker-compose.licenseserver.yml down
    docker compose -f $file_path/docker-compose.licenseserver.yml up -d --build licenseserver

    sleep 3

    curl $license_server_url
}

################
## Preparation
################
# Function to verify Docker version
verify_docker() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [verify_docker] module${ORANGE}"

    if command -v docker &>/dev/null; then
        client_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null)
        if [ $? -ne 0 ]; then
            log "${CALLING_SCRIPT} ${YELLOW}Docker client exists but may not be functioning properly.${NC}"
            return 1
        fi

        client_major_version=$(echo "$client_version" | cut -d'.' -f1)
        if [ "$client_major_version" -ge 28 ]; then
            # Also verify docker daemon is running
            if docker info &>/dev/null; then
                log "${CALLING_SCRIPT} ${GREEN}Docker $client_version is installed and running correctly.${NC}"
                return 0
            else
                log "${CALLING_SCRIPT} ${YELLOW}Docker client is installed but the daemon isn't responding.${NC}"
                return 1
            fi
        else
            log "${CALLING_SCRIPT} ${YELLOW}Docker version $client_version is too old (requires version 28+).${NC}"
            return 1
        fi
    else
        log "${CALLING_SCRIPT} ${RED}Docker is not installed.${NC}"
        return 1
    fi
}

# Function to verify Docker Compose
verify_docker_compose() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [verify_docker_compose] module${ORANGE}"

    # Check for standalone docker-compose
    if command -v docker-compose &>/dev/null; then
        compose_version=$(docker-compose --version | grep -oP '(\d+\.\d+\.\d+)')
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose standalone version $compose_version is installed.${NC}"
        return 0
    fi

    # Check Docker Compose plugin (new method)
    if docker compose version &>/dev/null; then
        compose_version=$(docker compose version --short)
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose plugin version $compose_version is installed.${NC}"
        return 0
    fi

    log "${CALLING_SCRIPT} ${RED}Docker Compose is not installed.${NC}"
    return 1
}

# Function to install Docker
install_docker() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [install_docker] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Installing Docker...${NC}"

    # First remove any old versions that might exist
    apt update -y
    apt remove -y docker docker-engine docker.io containerd runc &>/dev/null || true

    # Install dependencies
    apt update -y
    apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common

    # Set up the Docker repository
    mkdir -p /etc/apt/keyrings
    chmod 755 /etc/apt/keyrings/
    if [ -f "/etc/apt/keyrings/docker.gpg" ]; then
        rm -f /etc/apt/keyrings/docker.gpg || error_exit "Failed to remove /etc/apt/keyrings/docker.gpg"
        log "${CALLING_SCRIPT} ${RED}File /etc/apt/keyrings/docker.gpg has been removed.${NC}"
    else
        log "${CALLING_SCRIPT} File /etc/apt/keyrings/docker.gpg does not exist."
    fi
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Create docker group (executed as a subshell)
    if ! groups $USER | grep -q docker; then
        log "${CALLING_SCRIPT} Added user to docker group. ${RED}Please log out and log back in for changes to take effect.${NC}"
        exit 1
    fi

    # Add permissions
    sudo chmod 666 /var/run/docker.sock

    # Set up Docker service
    systemctl enable docker
    systemctl start docker

    # Add current user to docker group
    if [ -n "$SUDO_USER" ]; then
        MAINUSER="$SUDO_USER"
    else
        MAINUSER=$(logname 2>/dev/null || echo "${USER}")
    fi

    groupadd -f docker || true
    usermod -aG docker "$MAINUSER"

    log "${CALLING_SCRIPT} ✅${GREEN}Docker installed successfully.${NC}"
}

# Function to install Docker Compose
install_docker_compose() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [install_docker_compose] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Installing Docker Compose...${NC}"

    # First check if Docker Compose plugin is already available through Docker installation
    if docker compose version &>/dev/null; then
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose plugin is already installed.${NC}"
        return 0
    fi

    # Install the standalone version
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    sudo rm /usr/local/bin/docker-compose
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    if [ $? -ne 0 ]; then
        log "${CALLING_SCRIPT} ${RED}Failed to download Docker Compose. Trying alternative method...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    fi

    chmod +x /usr/local/bin/docker-compose

    # Create symbolic link for command completion
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

    if docker-compose --version &>/dev/null; then
        log "${CALLING_SCRIPT} ✅${GREEN}Docker Compose standalone installed successfully.${NC}"
        return 0
    else
        log "${CALLING_SCRIPT} ${RED}Docker Compose installation failed.${NC}"
        return 1
    fi
}

validate_idol_components(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [validate_idol_components] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Validate IDOL Components...${NC}"

    # Check if java is installed
    command_exists java || error_exit "JAVA is not installed. Please install it first. ${YELLOW}[CMD] ${ORANGE}sudo apt install openjdk-21-jdk ${NC}"

    # Check if openssl is installed
    command_exists openssl || error_exit "OpenSSL is not installed. Please install it first."

    # Check if docker is installed
    command_exists docker || error_exit "⚠️ ${LIGHTER_YELLOW} WARNING: Docker doesn't seem to be installed.\n ❌ ${RED}Certificate installation might fail.${NC}\n ❌ ${RED}This script is not running as ${YELLOW}[root]${RED} user.${NC}"

    # Check if docker-composer is installed
    command_exists docker-compose || error_exit "⚠️ ${LIGHTER_YELLOW} WARNING: Docker Compose doesn't seem to be installed.\n ❌ ${RED}Certificate installation might fail.${NC}\n ❌ ${RED}This script is not running as ${YELLOW}[root]${RED} user.${NC}"

    # Setup Docker prerequisites as root user
    if [ $? -ne 0 ]; then
        # Create a docker group if not already exist
        sudo usermod -aG docker $USER

        log "${CALLING_SCRIPT} ${YELLOW}Starting Docker and Docker Compose installation check...${NC}"

        # Verify and install Docker Compose if needed
        log "${CALLING_SCRIPT} ${YELLOW}Verify Docker Compose installation...${NC}"
        if ! verify_docker_compose; then
            log "${CALLING_SCRIPT} ${YELLOW}Docker Compose needs to be installed.${NC}"
            install_docker_compose

            # Verify installation was successful
            if ! verify_docker_compose; then
                log "${CALLING_SCRIPT} ❌${RED}Docker Compose installation failed. Please check error messages above.${NC}"
                exit 1
            fi
        fi

        # Check and install Docker if needed
        log "${CALLING_SCRIPT} ${YELLOW}Checking Docker installation...${NC}"
        if ! verify_docker; then
            log "${CALLING_SCRIPT} ${YELLOW}Docker needs to be installed or updated.${NC}"
            install_docker

            # Verify installation was successful
            if ! verify_docker; then
                log "${CALLING_SCRIPT} ❌${RED}Docker installation failed. Please check error messages above.${NC}"
                exit 1
            fi
        else
            log "${CALLING_SCRIPT} ${GREEN}Docker is already installed and up to date.${NC}"
        fi
        log "${CALLING_SCRIPT} ✅${GREEN}Installation complete! Docker and Docker Compose are ready to use.${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}NOTE: You may need to log out and log back in for group changes to take effect.${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}Alternatively, run 'newgrp docker' to use Docker without sudo in the current session.${NC}"
        echo -e "\n"


        log "${CALLING_SCRIPT} ⚠️ ${PURPLE}All prerequisites were met, to continue with the installation, log in as a sudo user and execute the desired script!${NC}"
        exit 1
    else
        log "${CALLING_SCRIPT} 🔔 ${PURPLE}Docker seem to be installed.${NC}"
    fi

    if [ $? -eq 0 ]; then
        sudo usermod -aG docker $USER
        log "${CALLING_SCRIPT} 🔔 ${PURPLE}Add sudo ${LIGHTER_YELLOW}[$USER]${PURPLE} user to the ${LIGHTER_YELLOW}[Docker] ${PURPLE}group${NC}"

        sudo systemctl enable docker
        log "${CALLING_SCRIPT} 🔔 ${PURPLE}Enable the sudo user executing the installation script to use ${LIGHTER_YELLOW}[Docker]${NC}"

        sudo systemctl restart docker
        log "${CALLING_SCRIPT} 🔔 ${PURPLE}To apply the changes, restart ${LIGHTER_YELLOW}[Docker]${NC}"
    fi
}

validate_idol_prerequisites(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [validate_idol_prerequisites] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Validate IDOL Prerequisites...${NC} ${YELLOW}"

    # Validate IDOL Prerequisites is Met
    update_file_row "$IDOL_ENV" "export IS_IDOL_VALIDATION_MET" "UNVALIDATION" "=" "$SILENT_MODE" "$SILENT_MODE"
    if prompt_yn "Are you considering validate IDOL prerequisites?" "Y"; then
        echo ''
        log "${CALLING_SCRIPT} ${GREEN}validate IDOL prerequisites is confirmed. ${ORANGE}Continuing with the current configuration.${NC}"
        update_file_row "$IDOL_ENV" "export IS_IDOL_VALIDATION_MET" "TRUE" "=" "$SILENT_MODE" "$SILENT_MODE"
        validate_idol_components
    fi
    echo -e "${NC}"
}

# Function to validate IPv4
is_valid_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        for octet in ${ip//./ }; do
            if ((octet < 0 || octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Function to check IP responsiveness
is_ip_responding() {
    local ip="$1"
    local timeout="${2:-1}"  # Default 1 second timeout
    
    if ping -c 1 -W "$timeout" "$ip" > /dev/null 2>&1; then
        return 0  # IP is responding
    else
        return 1  # IP is not responding
    fi
}

# Function to get network interfaces with MAC and IP addresses 
get_network_address() {
    # Collect all iface:ip:mac tuples
    interfaces=$(ip -o -4 addr show | awk '/scope global/ {
        # Extract interface name and IP
        iface = $2
        ip = $4
        gsub(/\/.*/, "", ip)  # Remove CIDR notation
        
        # Get MAC address for this interface
        cmd = "ip link show " iface " | awk \"/link\\/ether/ {print \\$2}\""
        cmd | getline mac
        close(cmd)
        
        if (mac == "") mac = "N/A"
        print iface "#" ip "#" mac
    }')

    # Pick default (prioritize eth interfaces, then interfaces starting with 'e')
    default=$(echo "$interfaces" | grep '^eth' | head -n1)
    if [ -z "$default" ]; then
        default=$(echo "$interfaces" | grep '^e' | head -n1)
    fi
    if [ -z "$default" ]; then
        default="custom:$custom_ip:N/A"
    fi

    echo "Default -> $default"
    echo "$interfaces"
}

# Function: Get routing table for host + guests
get_network_routes() {
    # Parse all route information into structured format
    ip route show | while read -r line; do
        dest=$(echo "$line" | awk '{print $1}')
        
        # Extract fields using pattern matching
        via=$(echo "$line" | grep -o 'via [0-9.]*' | awk '{print $2}')
        dev=$(echo "$line" | grep -o 'dev [^ ]*' | awk '{print $2}')
        proto=$(echo "$line" | grep -o 'proto [^ ]*' | awk '{print $2}')
        scope=$(echo "$line" | grep -o 'scope [^ ]*' | awk '{print $2}')
        metric=$(echo "$line" | grep -o 'metric [0-9]*' | awk '{print $2}')
        src=$(echo "$line" | grep -o 'src [0-9.]*' | awk '{print $2}')
        if [[ -z "$src" ]] || ! is_valid_ip "$src"; then
            src=$(echo "$line" | grep '^default' | grep -o 'via [0-9.]*' | awk '{print $2}')
        fi
        
        # Output in custom format
        echo "$dest # ${via:-direct} # $dev # $proto # $src # $metric"
    done
}

# Function to Get IDOL cluster_ip to accept a prompt parameter
get_idol_cluster_ip() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [get_idol_cluster_ip] module${ORANGE}"
    local prompt_msg="$1"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Get IDOL [${ORANGE}${prompt_msg}]${YELLOW} ip address...${NC}"

    # Only run if prompt_msg is Guest or Host
    if [[ "$prompt_msg" != "Guest" && "$prompt_msg" != "Host" ]]; then
        echo -e "${RED}Only [Host,Guest] are allowed as parameters. Try once more.${LIGHTER_YELLOW}"
        return
    else
        echo -e "${YELLOW}------------------------------${NC}"
        echo -e "${YELLOW}Select IDOL ${ORANGE}[${prompt_msg}]${YELLOW} ip address${NC}"
        echo -e "${YELLOW}------------------------------${NC}"
    fi

    local routes=()
    local interfaces=()
    local ip_addresses=()
    local selected_ip

    routes=()
    interfaces=()
    ip_addresses=()

    counter=1
    # Access WSL guest from Windows host
    if [[ "$prompt_msg" = "Host" ]]; then
        echo -e "${YELLOW}$(printf '%-3s %-20s %-20s  %-20s' "No" "Interface" "Mac Address" "IP Address")${NC}"
        echo -e "${YELLOW}--------------------------------------------------------------${NC}"

        while IFS= read -r line; do
            iface=$(echo "$line" | cut -d'#' -f1)
            ip_addr=$(echo "$line" | cut -d'#' -f2)
            mac=$(echo "$line" | cut -d'#' -f3)
            interfaces+=("$iface")
            ip_addresses+=("$ip_addr")
            echo -e "${LIGHTER_YELLOW}$(printf '%-3s %-20s %-20s  %s' "$counter:" "$iface" "$mac" "$ip_addr")${NC}"
            ((counter++))
        done < <(get_network_address)
    fi
    # Access Windows host from WSL guest
    if [[ "$prompt_msg" = "Guest" ]]; then
        echo -e "${YELLOW}$(printf '%-3s %-20s %-20s %-20s  %s' "No" "Route" "Gateway" "Interface" "Source")${NC}"
        echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

        while IFS= read -r line; do
            route=$(echo "$line" | cut -d'#' -f1)
            gateway=$(echo "$line" | cut -d'#' -f2)
            iface=$(echo "$line" | cut -d'#' -f3)
            ip_addr=$(echo "$line" | cut -d'#' -f5)
            routes+=("$route")
            interfaces+=("$iface")
            ip_addresses+=("$ip_addr")
            echo -e "${LIGHTER_YELLOW}$(printf '%-3s %-20s %-20s %-20s' "$counter:" "$route" "$gateway" "$iface" "$ip_addr")${NC}"
            ((counter++))
        done < <(get_network_routes)
    fi

    # Create a temp file to store interfaces + IPs
    tmp_file=$(mktemp)
    counter=1
    for i in "${!interfaces[@]}"; do
        printf "%-3s %-20s : %s\n" "$counter:" "${interfaces[$i]}" "${ip_addresses[$i]}" >> "$tmp_file"
        ((counter++))
    done

    # Add custom IP option to [tmp_file] file
    if [[ "$prompt_msg" = "Host" ]]; then
        custom_line=$counter
        printf "%-3s %-20s : %s\n" "$counter:" "custom" "1.2.3.4" >> "$tmp_file"
    fi

    # Count the number of lines in the input file
    num_rows=$(wc -l < "$tmp_file")

    # Determine default selection
    default_selection=1
    count=0
    while IFS= read -r line; do
        count=$((count+1))
        iface=$(echo "$line" | awk -F':' '{gsub(/^[ \t]+/, "", $2); print $2}')
        # First interface starting with 'eth0'
        if [[ "$iface" == eth0* ]]; then
            default_selection=$count
            break
        fi
    done < "$tmp_file"

    # If none matched eth0*, try e*0
    if (( default_selection == 1 )); then
        count=0
        while IFS= read -r line; do
            count=$((count+1))
            iface=$(echo "$line" | awk -F':' '{gsub(/^[ \t]+/, "", $2); print $2}')
            if [[ "$iface" == e*0* ]]; then
                default_selection=$count
                break
            fi
        done < "$tmp_file"
    fi

    # If still none, pick first non-loopback
    if (( default_selection == 1 )); then
        count=0
        while IFS= read -r line; do
            count=$((count+1))
            iface=$(echo "$line" | awk -F':' '{gsub(/^[ \t]+/, "", $2); print $2}')
            if [[ "$iface" != lo ]]; then
                default_selection=$count
                break
            fi
        done < "$tmp_file"
    fi
    
    # Add custom ip line to display
    if [[ "$prompt_msg" = "Host" ]]; then
        echo -e "${YELLOW}${custom_line}:  Enter custom IP${NC}"
    fi
    
    # Selection prompt 
    selection=""  
    echo ''
    echo -e "${ORANGE}The default selection is ${YELLOW}[${default_selection}] ${LIGHTER_YELLOW}"
    while true; do
        read -p "Enter selection [1-$num_rows]: " selection
        selection=${selection:-$default_selection}
        if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= num_rows )); then
            break
        else
            echo -e "${RED}Invalid selection. Try again.${LIGHTER_YELLOW}"
        fi
    done

    # Extract IP
    selected_line=$(sed -n "${selection}p" "$tmp_file")
    selected_ip=$(echo "$selected_line" | awk -F':' '{gsub(/^[ \t]+/, "", $3); print $3}')

    # If no valid IP, prompt for custom
    if [[ "$selection" == "$custom_line" ]]; then
        while true; do
            read -p "Enter custom IP: " selected_ip
            if ! is_valid_ip "$selected_ip" || [ -z "$selected_ip" ]; then
                break
            else
                echo -e "${RED}Invalid IP. Try again.${LIGHTER_YELLOW}"
            fi
        done
    fi

    # Display the selected IP
    echo -e "${LIGHTER_YELLOW}Selected Line Number: ${ORANGE}[${selection}]${LIGHTER_YELLOW} IP: ${ORANGE}[${selected_ip}]${NC}"

    # Select ip address of [HOST] or [GUEST] environment
    case "$prompt_msg" in
        Host)
            # Selected Host IP
            export IDOL_NET_HOST_IP=$selected_ip
            echo "export IDOL_NET_HOST_IP=$selected_ip" >> "$IDOL_ENV"
            ;;
        Guest)
            # Selected Guest IP
            export IDOL_NET_GUEST_IP=$selected_ip
            echo "export IDOL_NET_GUEST_IP=$selected_ip" >> "$IDOL_ENV"
            ;;
        *)
            # Only [Host,Guest] are allowed as parameters. Try once more
            echo -e "${RED}Invalid selection - only [Host,Guest] are allowed as parameters. Try once more.${LIGHTER_YELLOW}"
            ;;
    esac 

    # check IP responsiveness
    if is_ip_responding $selected_ip; then
        log "${CALLING_SCRIPT} Selected ${prompt_msg} IP is ${GREEN}[UP] $selected_ip${NC}"
    else
        log "${CALLING_SCRIPT} Selected ${prompt_msg} IP is ${RED}[DOWN] $selected_ip${NC}"
    fi
}

# Function to get IDOL host FQDN
get_idol_host_fqdn() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [get_idol_host_fqdn] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Get IDOL host FQDN...${NC}"
    IDOL_HOST_FQDN=$(hostname -f)
    log "${CALLING_SCRIPT} IDOL host FQDN: ${ORANGE}$IDOL_HOST_FQDN${NC}"
    echo "export IDOL_HOST_FQDN=${IDOL_HOST_FQDN}" >> "$IDOL_ENV"
    echo ''
}

# Function to collect IDOL setup parameters and related variables
collect_idol_setup_version() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [collect_idol_setup_version] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Collect IDOL setup parameters and related variables...${NC}"
    echo -e "${YELLOW}Select IDOL version: ${NC}"
    echo -e "${YELLOW}1) 25.2 ${ORANGE}[default] ${NC}"
    echo -e "${YELLOW}2) 25.1 ${NC}"
    local selection
    echo -e "${BLUE}--------------------${YELLOW}"
    while true; do
        read -p "Enter selection [1]: " selection
        selection=${selection:-1}
        case $selection in
            1)
                export IDOL_VERSION=25.2
                break
                ;;
            2)
                export IDOL_VERSION=25.1
                break
                ;;
            *)
                echo -e "${RED}Invalid selection. Please choose 1, or 2.${NC}"
                ;;
        esac
    done
    log "${CALLING_SCRIPT} IDOL version: ${ORANGE}$IDOL_VERSION${NC}"
    echo "export IDOL_VERSION=${IDOL_VERSION}" >> "$IDOL_ENV"
}

# Function to collect IDOL setup type
collect_idol_setup_type() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [collect_idol_setup_type] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Collect IDOL setup type...${NC}"
    echo -e "${YELLOW}Select IDOL type:                                ${NC}"
    echo -e "${YELLOW}1) Standard                                      ${NC}"
    echo -e "${YELLOW}2) Secure all IDOL components ${ORANGE}[default] ${NC}"
    local selection
    echo -e "${BLUE}--------------------${YELLOW}"
    while true; do
        read -p "Enter selection [2]: " selection
        selection=${selection:-2}
        case $selection in
            1)
                export IDOL_SETUP_TYPE=idol-standard-setup
                export IDOL_ENABLE_SSL=FALSE
                break
                ;;
            2)
                export IDOL_SETUP_TYPE=idol-secure-setup   
                export IDOL_ENABLE_SSL=TRUE
                break
                ;;
            *)
                echo -e "${RED}Invalid selection. Please choose 1, 2, or 3.${YELLOW}"
                ;;
        esac
    done
    echo "export IDOL_SETUP_TYPE=${IDOL_SETUP_TYPE}" >> "$IDOL_ENV"

    # Collect IDOL Nifi port
    collect_idol_nifi_port
}

# Set IDOL nifi persistence path
set_idol_nifi_persistence_path(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [set_idol_nifi_persistence_path] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Set IDOL nifi persistence path...${NC}"
    # Define IDOL nifi persistence path
    while [ "$IS_IDOL_NIFI_PRESERVE" = "TRUE" ]; do
        echo -e "${LIGHTER_YELLOW}Enter IDOL nifi persistence path:${ORANGE}"
        read -p "   [default /opt/idol/backup-nifi-folder/nifi-current Or type a custom path] " host_nifi_persistence_path
        host_nifi_persistence_path=${host_nifi_persistence_path:-"/opt/idol/backup-nifi-folder/nifi-current"}

        if [ -d "$host_nifi_persistence_path" ]; then
            echo -e "${LIGHTER_YELLOW}Folder exists:${GREEN} [$host_nifi_persistence_path]${LIGHTER_YELLOW}"
            break
        else
            echo -e "${LIGHTER_YELLOW}Folder ${RED}[$host_nifi_persistence_path] ${LIGHTER_YELLOW}does not exist, please try again.${LIGHTER_YELLOW}"
        fi
    done

    # Get IDOL nifi persistence path
    if [ "$IS_IDOL_NIFI_PRESERVE" = "TRUE" ]; then
        log "${CALLING_SCRIPT} ${ORANGE}IDOL nifi persistence path is: ${GREEN}[${host_nifi_persistence_path}]${NC}"
        echo "export IDOL_PRESERVE_NIFI_PATH=${host_nifi_persistence_path}" >> "$IDOL_ENV"
    fi
}

# Set IDOL toolkit path
set_idol_toolkit_path(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [set_idol_toolkit_path] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Set IDOL toolkit path...${NC}"
    # Define IDOL toolkit path
    while true; do
        echo -e "${LIGHTER_YELLOW}Enter IDOL toolkit path:${PURPLE}" 
        read -p "   [default /opt/idol/idol-containers-toolkit Or type a custom path] " host_toolkit_path
        host_toolkit_path=${host_toolkit_path:-"/opt/idol/idol-containers-toolkit"}

        if [ -d "$host_toolkit_path" ]; then
            echo -e "${LIGHTER_YELLOW}Folder exists:${GREEN} [$host_toolkit_path]${LIGHTER_YELLOW}"
            break
        else
            echo -e "${LIGHTER_YELLOW}Folder ${RED}[$host_toolkit_path] ${LIGHTER_YELLOW}does not exist, please try again.${LIGHTER_YELLOW}"
            mkdir -p $host_toolkit_path
            echo -e "${LIGHTER_YELLOW}Folder created:${GREEN} [$host_toolkit_path]${LIGHTER_YELLOW}"
            break
        fi
    done
    log "${CALLING_SCRIPT} ${ORANGE}IDOL toolkit path is: ${GREEN}[${host_toolkit_path}]${NC}"
    export IDOL_TOOLKIT_PATH=$host_toolkit_path
    echo "export IDOL_TOOLKIT_PATH=${host_toolkit_path}" >> "$IDOL_ENV"
}

# Set IDOL preserve data outside the container status
get_idol_preserve_status() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [get_idol_preserve_status] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Configuring IDOL data preservation...${NC}"

    # Info section
    log "${CALLING_SCRIPT}📌 ${YELLOW}Data Preservation Options:${NC}"
    log "${CALLING_SCRIPT}📌   ${PURPLE}1. Preserve data OUTSIDE container (Recommended - Select ${YELLOW}YES${PURPLE})${NC}"
    log "${CALLING_SCRIPT}📌      - Data persists if container is removed or recreated${NC}"
    log "${CALLING_SCRIPT}📌      - NIFI requires an ${YELLOW}existing${PURPLE} backup path${NC}"
    log "${CALLING_SCRIPT}📌   ${PURPLE}2. Keep data INSIDE container (Select ${YELLOW}NO${PURPLE})${NC}"
    log "${CALLING_SCRIPT}📌      - Data is lost when container is removed${NC}"

    # Main decision: preserve outside or not
    if prompt_yn "Do you want to enable IDOL preserve data folders outside the containers?" "Y"; then  
        export IS_IDOL_PRESERVE="TRUE"

        # Ask if user wants to override default path
        if prompt_yn "Do you want to change the default preserve path?" "n"; then
            # Set IDOL local Preserve Content cfg path 
            set_idol_preserve_content_path 

            # Set IDOL local Preserve Find home path 
            set_idol_preserve_find_path
        else
            export IDOL_PRESERVE_CONTENT_PATH="/opt/idol/persistent-data/content"
            export IDOL_PRESERVE_FIND_PATH="/opt/idol/persistent-data/find"
            export IDOL_PRESERVE_PATH="/opt/idol/persistent-data"
        fi
        update_file_row "$IDOL_ENV" "export IDOL_PRESERVE_PATH" "${IDOL_PRESERVE_PATH}" "=" "$SILENT_MODE" "$SILENT_MODE"
        log "${CALLING_SCRIPT} IDOL preserve data path: ${YELLOW}[$IDOL_PRESERVE_PATH]${NC}"

        # NIFI persistence decision
        if prompt_yn "Do you want to preserve NIFI data outside the container?" "n"; then  
            export IS_IDOL_NIFI_PRESERVE="TRUE"
            set_idol_nifi_persistence_path
        else   
            export IS_IDOL_NIFI_PRESERVE="FALSE"
        fi

        update_file_row "$IDOL_ENV" "export IS_IDOL_NIFI_PRESERVE" "${IS_IDOL_NIFI_PRESERVE}" "=" "$SILENT_MODE" "$SILENT_MODE"
        log "${CALLING_SCRIPT} IDOL preserve NIFI data outside container: ${YELLOW}[$IS_IDOL_NIFI_PRESERVE]${NC}"

    else  
        export IS_IDOL_PRESERVE="FALSE"
    fi

    # Finalize env updates
    update_file_row "$IDOL_ENV" "export IS_IDOL_PRESERVE" "${IS_IDOL_PRESERVE}" "=" "$SILENT_MODE" "$SILENT_MODE"
    log "${CALLING_SCRIPT} IDOL preserve data outside container: ${YELLOW}[$IS_IDOL_PRESERVE]${NC}"
}


# Set IDOL local Preserve [CONTENT] path
set_idol_preserve_content_path(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [set_idol_preserve_content_path] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Set IDOL local Preserve [CONTENT] path...${NC}"
    # Define IDOL local Preserve [CONTENT] path
    while true; do
        echo -e "\n${LIGHTER_YELLOW}Enter IDOL local Preserve ${ORANGE}[CONTENT]${LIGHTER_YELLOW} path:${PURPLE}"
        read -p "   default /opt/idol/persistent-data Or type a custom path] " host_content_path
        host_content_path=${host_content_path:-"/opt/idol/persistent-data"}

        if [ -d "$host_content_path" ]; then
            echo -e "${LIGHTER_YELLOW}Folder exists:${GREEN} [$host_content_path]${LIGHTER_YELLOW}"
            break
        else
            echo -e "${LIGHTER_YELLOW}Folder ${RED}[$host_content_path] ${LIGHTER_YELLOW}does not exist, please try again.${LIGHTER_YELLOW}"
            mkdir -p $host_content_path
            echo -e "${LIGHTER_YELLOW}Folder created:${GREEN} [$host_content_path]${LIGHTER_YELLOW}"
            break
        fi
    done

    # Set MAIN Preserve path
    line="export IDOL_PRESERVE_PATH=${host_content_path}"
    if ! grep -Fxq "$line" "$IDOL_ENV"; then 
        update_file_row "$IDOL_ENV" "export ${line}" "${host_content_path}" "=" "$SILENT_MODE" "$SILENT_MODE"
        log "${CALLING_SCRIPT} ${ORANGE}IDOL local Preserve [MAIN] path: ${GREEN}[${host_content_path}]${NC}"
    fi

    export IDOL_PRESERVE_CONTENT_PATH="${host_content_path}/content"
    update_file_row "$IDOL_ENV" "export IDOL_PRESERVE_CONTENT_PATH" "${IDOL_PRESERVE_CONTENT_PATH}" "=" "$SILENT_MODE" "$SILENT_MODE"
    log "${CALLING_SCRIPT} ${ORANGE}IDOL local Preserve [CONTENT] path: ${GREEN}[${IDOL_PRESERVE_CONTENT_PATH}]${NC}"
}

# Set IDOL local Preserve Find cfg path
set_idol_preserve_find_path(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [set_idol_preserve_find_path] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Set IDOL local Preserve Find home path...${NC}"
    # Define IDOL local Preserve Find [HOME] path
    while true; do
        echo -e "\n${LIGHTER_YELLOW}Enter IDOL local Preserve ${ORANGE}[FIND]${LIGHTER_YELLOW} home path:${PURPLE}"
        read -p "   default /opt/idol/persistent-data Or type a custom path] " host_find_path
        host_find_path=${host_find_path:-"/opt/idol/persistent-data"}

        if [ -d "$host_find_path" ]; then
            echo -e "${LIGHTER_YELLOW}Folder exists:${GREEN} [$host_find_path]${LIGHTER_YELLOW}"
            break
        else
            echo -e "${LIGHTER_YELLOW}Folder ${RED}[$host_find_path] ${LIGHTER_YELLOW}does not exist, please try again.${LIGHTER_YELLOW}"
            mkdir -p $host_find_path
            echo -e "${LIGHTER_YELLOW}Folder created:${GREEN} [$host_find_path]${LIGHTER_YELLOW}"
            break
        fi
    done

    # Set MAIN Preserve path
    line="export IDOL_PRESERVE_PATH=${host_find_path}"
    if ! grep -Fxq "$line" "$IDOL_ENV"; then 
        update_file_row "$IDOL_ENV" "export ${line}" "${host_find_path}" "=" "$SILENT_MODE" "$SILENT_MODE"
        log "${CALLING_SCRIPT} ${ORANGE}IDOL local Preserve [MAIN] path: ${GREEN}[${host_find_path}]${NC}"
    fi

    export IDOL_PRESERVE_FIND_PATH="${host_find_path}/find"
    update_file_row "$IDOL_ENV" "export IDOL_PRESERVE_FIND_PATH" "${IDOL_PRESERVE_FIND_PATH}" "=" "$SILENT_MODE" "$SILENT_MODE"
    log "${CALLING_SCRIPT} ${ORANGE}IDOL local Preserve [FIND] path: ${GREEN}[${IDOL_PRESERVE_FIND_PATH}]${NC}"
}

# Create IDOL host storage mapping
create_idol_host_storage_mapping(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [create_idol_host_storage_mapping] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Create idol host storage mapping...${NC}"
    # Define IDOL host storage mapping 
    while true; do
        echo -e "${LIGHTER_YELLOW}Enter IDOL host storage mapping path:${PURPLE}"
        read -p "   [default /mnt/c/OpenText/hotfolder Or type a custom path] " host_path
        host_path=${host_path:-"/mnt/c/OpenText/hotfolder"}

        if [ -d "$host_path" ]; then
            echo -e "${LIGHTER_YELLOW}Folder exists:${GREEN} [$host_path]${LIGHTER_YELLOW}"
            break
        else
            echo -e "${LIGHTER_YELLOW}Folder ${RED}[$host_path] ${LIGHTER_YELLOW}does not exist, please try again.${LIGHTER_YELLOW}"
            mkdir -p $host_path
            echo -e "${LIGHTER_YELLOW}Folder created:${GREEN} [$host_path]${LIGHTER_YELLOW}"
            break
        fi
    done

    log "${CALLING_SCRIPT} ${ORANGE}IDOL host storage path is: ${GREEN}[${host_path}]${NC}"
    echo "export IDOL_HOST_STORAGE_PATH=${host_path}" >> "$IDOL_ENV"
}

# Function to collect IDOL Nifi secure port
collect_idol_nifi_port() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [collect_idol_nifi_port] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Collect IDOL Nifi secure port...${YELLOW}"
    # Enabling the IDOL Nifi secure port - HTTPS
    if [ "$IDOL_ENABLE_SSL" = "TRUE" ]; then
        if prompt_yn "Enter IDOL Nifi secure port? [default 8443]" "y"; then
            response=8443
        else
            echo -e "${LIGHTER_YELLOW}"
            # Set Nifi secure port number
            read -p "Enter Nifi secure port number: " response
            response=${response:-8443}
        fi
        update_file_row "$IDOL_ENV" "export IDOL_ENABLE_SSL" "TRUE" "=" "$SILENT_MODE" "$SILENT_MODE"
    fi

    # Enabling the IDOL Nifi port - HTTP
    if [ "$IDOL_ENABLE_SSL" = "FALSE" ]; then
        response=8080
        update_file_row "$IDOL_ENV" "export IDOL_ENABLE_SSL" "FALSE" "=" "$SILENT_MODE" "$SILENT_MODE"
    fi
    
    update_file_row "$IDOL_ENV" "export IDOL_NIFI_PORT_NUMBER" "${response}" "=" "$SILENT_MODE" "$SILENT_MODE"
    log "${CALLING_SCRIPT}  Nifi secure port number is: ${GREEN}[$response]${NC}"
    echo ''
}

# Function to collect IDOL Nifi deployment info
collect_idol_nifi_deployment_info() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [collect_idol_nifi_deployment_info] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Collect IDOL Nifi deployment info...${NC}"

    echo ''
    echo -e "${YELLOW}Select IDOL Nifi deployment: ${NC}"
    echo -e "${YELLOW}1) Full    Nifi Version 2 ${NC}"
    echo -e "${YELLOW}2) Minimal Nifi Version 2 ${ORANGE}[default]${NC}"
    echo -e "${YELLOW}3) Full    Nifi Version 1 ${NC}"
    echo -e "${YELLOW}4) Minimal Nifi Version 1 ${NC}"
    local selection
    echo -e "${BLUE}--------------------${YELLOW}"
    while true; do
        read -p "Enter selection [2]: " selection
        selection=${selection:-2}
        case $selection in
            1)
                export IDOL_NIFI_DEPLOY_TYPE="nifi-ver2-full"
                export IDOL_NIFI_DEPLOY_VERSION="nifi-ver2"
                break
                ;;
            2)
                export IDOL_NIFI_DEPLOY_TYPE="nifi-ver2-minimal"
                export IDOL_NIFI_DEPLOY_VERSION="nifi-ver2"
                break
                ;;
            3)
                export IDOL_NIFI_DEPLOY_TYPE="nifi-ver1-full"
                export IDOL_NIFI_DEPLOY_VERSION="nifi-ver1"
                break
                ;;
            4)
                export IDOL_NIFI_DEPLOY_TYPE="nifi-ver1-minimal"
                export IDOL_NIFI_DEPLOY_VERSION="nifi-ver1"
                break
                ;;
            *)
                echo -e "${RED}Invalid selection. Please choose 1, 2, 3, or 4.${NC}"
                ;;
        esac
    done
    echo ''
    log "${CALLING_SCRIPT} IDOL Nifi deployment: ${ORANGE}$IDOL_NIFI_DEPLOY_TYPE${NC}"
    echo "export IDOL_NIFI_DEPLOY_TYPE=${IDOL_NIFI_DEPLOY_TYPE}" >> "$IDOL_ENV"

    log "${CALLING_SCRIPT} IDOL Nifi version: ${ORANGE}$IDOL_NIFI_DEPLOY_VERSION${NC}"
    echo "export IDOL_NIFI_DEPLOY_VERSION=${IDOL_NIFI_DEPLOY_VERSION}" >> "$IDOL_ENV"
}

# Function to previewing environment related variables
show_env_variables(){
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [show_env_variables] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Previewing environment related variables...${NC}"

    # apply IDOL environment variables
    last_line=$(tail -n 1 "$IDOL_ENV")

    while IFS= read -r line; do
        if [ "$line" = "$last_line" ]; then
            log "${CALLING_SCRIPT} ${YELLOW}└── [ENV] ${PURPLE}$line ${NC}"
        else
            log "${CALLING_SCRIPT} ${YELLOW}├── [ENV] ${PURPLE}$line ${NC}"
        fi
    done < "$IDOL_ENV"

    # Create a sourced script with shebang 
    (echo "#!/bin/bash"; echo ''; cat "$IDOL_ENV") > ./env/export-env-variables.sh
}

##############################
## IDOL deployment preparation
##############################
# Function to IDOL deployment preparation
idol_deployment_preparation() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [idol_deployment_preparation] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}IDOL deployment preparation...${NC}"

    # Display Info
    log "${CALLING_SCRIPT} ${GREEN}###########################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}##### IDOL - Collect Setup Parameters #####${NC}"
    log "${CALLING_SCRIPT} ${GREEN}###########################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}##### $(date +"%Y-%m-%d")                ${NC}"

    # Init log file
    if [ -f $LOGFILE ]; then
        rm -f $LOGFILE
        log "Old log deleted"
    fi
    log "Script started. Log path: ${LOGFILE}"

    # validate idol prerequisites components
    validate_idol_prerequisites

    # Get IDOL host FQDN
    get_idol_host_fqdn

    # Set IDOL cluster ip for both [Host] and [Guest]
    get_idol_cluster_ip "Host"
    get_idol_cluster_ip "Guest"

    # Collect IDOL setup version 
    collect_idol_setup_version

    # Collect IDOL setup type
    collect_idol_setup_type

    # Collect IDOL Nifi deployment info
    collect_idol_nifi_deployment_info

    # Get IDOL preserve data outside the container status
    get_idol_preserve_status

    # Set IDOL toolkit path
    set_idol_toolkit_path

    # Create IDOL host storage mapping
    create_idol_host_storage_mapping
}

#############################
## Collect Nifi Registry info
#############################
# Function to Collect Nifi Registry info
collect_nifi_registry_setup_info() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [collect_nifi_registry_setup_info] module${ORANGE}"
    echo ''
    log "${CALLING_SCRIPT} ${YELLOW}Collect Nifi Registry info...${NC}"

    # Considered of enabling the IDOL [NIFI] preserve registry [Yes/No]
    if prompt_yn "Do you want to preserve [NIFI REGISTRY] data outside the container?" "Y"; then  
        export IS_IDOL_NIFI_REGISTRY_PRESERVE="TRUE"
        export IDOL_NIFI_REGISTRY_PATH="$(pwd)/utilities/nifi-registry-setup"

        # Display Info
        log "${CALLING_SCRIPT} ${GREEN}####################################################${NC}"
        log "${CALLING_SCRIPT} ${GREEN}##### Nifi Registry - Collect Setup Parameters #####${NC}"
        log "${CALLING_SCRIPT} ${GREEN}####################################################${NC}"
        log "${CALLING_SCRIPT} ${GREEN}##### $(date +"%Y-%m-%d")                ${NC}"
    else   
        export IS_IDOL_NIFI_REGISTRY_PRESERVE="FALSE"
    fi
    
    update_file_row "$IDOL_ENV" "export IS_IDOL_NIFI_REGISTRY_PRESERVE" "${IS_IDOL_NIFI_REGISTRY_PRESERVE}" "=" "$SILENT_MODE" "$SILENT_MODE"
    log "${CALLING_SCRIPT} Enable IDOL preserve [NIFI REGISTRY] data outside the container set to: ${YELLOW}[$IS_IDOL_NIFI_REGISTRY_PRESERVE]${NC}"
    update_file_row "$IDOL_ENV" "export IDOL_NIFI_REGISTRY_PATH" "${IDOL_NIFI_REGISTRY_PATH}" "=" "$SILENT_MODE" "$SILENT_MODE"
    log "${CALLING_SCRIPT} Path to [NIFI REGISTRY] setup folder is set to: ${YELLOW}[$IDOL_NIFI_REGISTRY_PATH]${NC}"
    echo ''
}

################
## Main Function
################
main() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [main] module${ORANGE}"

    # IDOL deployment preparation
    idol_deployment_preparation

    # Collect Nifi Registry info
    collect_nifi_registry_setup_info

    # Setup License Server
    setup_idol_licenseserver

    # Previewing environment related variables
    show_env_variables
}

# ********************************** #
# ********** MAIN SECTION ********** #
# ********************************** #
echo "export IS_IDOL_VALIDATION_MET=INIT" > $IDOL_ENV 

main "$@"

echo ''
log "${CALLING_SCRIPT} ${YELLOW}Log files are located at ${ORANGE}[$(pwd)/logs] ${YELLOW}folder.${NC}"