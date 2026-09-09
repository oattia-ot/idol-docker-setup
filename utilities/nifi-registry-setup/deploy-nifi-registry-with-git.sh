#!/bin/bash

# OpenText IDOL on Ubuntu 24.04
# Deploy NiFi Registry + GitHub Integration Setup Script

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

docker_compose_file="docker-compose.nifi-registry.yml"
providers_xml_file="registry/providers.xml"
bootstrap_conf_file="registry/bootstrap.conf"
container_name="nifi-registry"
network_name="nifi-registry-network"
health_check_timeout=30
health_check_interval=2

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO] $1 ${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1 ${NC}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1 ${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1 ${NC}" >&2
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Cleaning up..."
    cleanup_on_error
    exit 1
}

# Set error trap
trap 'error_handler $LINENO' ERR

# Cleanup function for error cases
cleanup_on_error() {
    log_info "Performing error cleanup..."
    # Stop any running containers
    if docker compose -f "./$docker_compose_file" ps -q licenseserver 2>/dev/null | grep -q .; then
        log_info "Stopping license server container..."
        docker compose -f "./$docker_compose_file" down || true
    fi
}

# Function to create docker network
setup_docker_network() {
    log_info "Setting up Docker network: $network_name"
    
    if docker network ls | grep -q "$network_name"; then
        log_warning "Network '$network_name' already exists, skipping creation"
    else
        if docker network create "$network_name"; then
            log_success "Created Docker network: $network_name"
        else
            log_error "Failed to create Docker network: $network_name"
            exit 1
        fi
    fi
}

echo -e "${YELLOW}===================================${NC}"
echo -e "${YELLOW}Deploy NiFi Registry + GitHub Setup${NC}"
echo -e "${YELLOW}===================================${NC}"
echo ""

# Prompt for GitHub credentials only if not already set
if [ "$IS_IDOL_NIFI_GITHUB_INTEGRATION" = "TRUE" ]; then
    if [ -z "${GITHUB_USER:-}" ] || [ -z "${GITHUB_REPO:-}" ] || [ -z "${GITHUB_TOKEN:-}" ]; then
        echo "📝 Please provide your GitHub information:"
        echo ""
        [ -z "${GITHUB_USER:-}" ] && read -p "GitHub Username: " GITHUB_USER
        [ -z "${GITHUB_REPO:-}" ] && read -p "GitHub Repository Name (e.g., nifi-flows): " GITHUB_REPO
        [ -z "${GITHUB_TOKEN:-}" ] && read -sp "GitHub Personal Access Token: " GITHUB_TOKEN && echo ""
        echo ""
    fi

    # Validate inputs
    if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_REPO" ] || [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${RED} ❌ Error: All fields are required ${NC}"
        exit 1
    fi

    GITHUB_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

    echo -e "${GREEN} ✅ Configuration has successfully finished. ${NC}"
    echo -e "${GREEN}    Repository: ${GITHUB_URL} ${NC}"
    echo ""
fi

# Copy [docker-compose.nifi-registry.yml-template] file to [docker-compose.nifi-registry.yml]
cp -f "../../templates/nifi-registry/docker-compose.nifi-registry.yml-template" "$docker_compose_file"
echo -e "${LIGHTER_YELLOW} 📝 Copying ${ORANGE}[../../templates/nifi-registry/docker-compose.nifi-registry.yml-template] ${LIGHTER_YELLOW}to current folder with your GitHub credentials...${NC}"
# Copy [providers.xml-template] file to [registry/providers.xml]
cp -f "../../templates/nifi-registry/providers.xml-template" "$providers_xml_file"
echo -e "${LIGHTER_YELLOW} 📝 Copying ${ORANGE}[../../templates/nifi-registry/providers.xml-template] ${LIGHTER_YELLOW}to current folder with your GitHub credentials...${NC}"

# Check if required files exist
if [ ! -f "$docker_compose_file" ]; then
    echo -e "${RED} ❌ Error: ${docker_compose_file} not found ${NC}"
    exit 1
fi

if [ ! -f "$providers_xml_file" ]; then
    echo -e "${RED} ❌ Error: ${providers_xml_file} not found ${NC}"
    exit 1
fi

if [ ! -f "$bootstrap_conf_file" ]; then
    echo -e "${RED} ❌ Error: ${bootstrap_conf_file} not found ${NC}"
    exit 1
fi

if [ "$IS_IDOL_NIFI_GITHUB_INTEGRATION" = "TRUE" ]; then
    # Update providers.xml with GitHub credentials
    echo -e "${LIGHTER_YELLOW} 🔨 Updating ${ORANGE}${providers_xml_file} ${LIGHTER_YELLOW}with your GitHub credentials...${NC}"
    sed -i.bak \
        -e "s|GIT-ACCESS-USER-PLACEHOLDER|${GITHUB_USER}|" \
        -e "s|GIT-ACCESS-TOKEN-PLACEHOLDER|${GITHUB_TOKEN}|" \
        -e "s|GIT-REMOTE-URL-PLACEHOLDER|${GITHUB_URL}|" \
        $providers_xml_file
    echo ""
    echo -e "${GREEN} ✅ ${providers_xml_file} updated ${NC}"
    echo ""
    # Update docker-compose.nifi-registry.yml with GitHub credentials
    echo -e "${LIGHTER_YELLOW} 🔨 Updating ${ORANGE}${docker_compose_file} ${LIGHTER_YELLOW}with your GitHub credentials...${NC}"
    sed -i.bak \
        -e "s|GIT-ACCESS-USER-PLACEHOLDER|${GITHUB_USER}|" \
        -e "s|GIT-ACCESS-TOKEN-PLACEHOLDER|${GITHUB_TOKEN}|" \
        -e "s|GIT-REMOTE-URL-PLACEHOLDER|${GITHUB_URL}|" \
        $docker_compose_file
    echo ""    
    echo -e "${GREEN} ✅ ${docker_compose_file} updated ${NC}"
    echo ""
fi

# Setup docker network
setup_docker_network

# Stop any existing containers
echo -e "${RED} 🛑 Stopping existing containers...${NC}"
docker compose -f $docker_compose_file down -v 2>/dev/null || true
echo ""

# Check if container is running
if docker ps -q -f name="^${container_name}$" | grep -q .; then
    echo "🛑 Stopping running container: $container_name"
    docker stop "$container_name"
fi

# Check if container exists (stopped) and remove
if docker ps -a -q -f name="^${container_name}$" | grep -q .; then
    echo "🗑️  Removing container: $container_name"
    docker rm "$container_name"
    echo "✓ Container removed"
fi

# Start services
echo -e "${LIGHTER_YELLOW} 🚀 Starting NiFi Registry ${ORANGE}[${docker_compose_file}]...${NC}"
docker compose -f $docker_compose_file up -d 

# Wait for container to be created
sleep 5

# Get source link path
get_source_link_path=$(readlink -f nifi-registry)
flow_storage_path="flow_storage"

# Create directory if it doesn't exist
mkdir -p "$get_source_link_path/$flow_storage_path"

# Change ownership to current user
sudo chown "$USER:$USER" "$get_source_link_path/$flow_storage_path"
echo -e "${GREEN} ✅ Directory [${flow_storage_path}] created and configured successfully ${NC}"

# Check if container is running 
if docker ps -q -f name="^${container_name}$" | grep -q .; then
    echo -e "${GREEN} ✅ Container found: $container_name ${NC}"
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "$container_name"; then
    echo -e "${RED} ❌ Error: Container exists but is not running"
    echo -e "${RED}   Checking logs..."
    docker logs "$container_name"
    echo -e "${NC}"
    exit 1
fi

# Wait for NiFi Registry to be ready
echo -e "${LIGHTER_YELLOW} ⏳ Waiting for NiFi Registry to start (20 seconds)...${NC}"
sleep 20

# Check if NiFi Registry is healthy
if ! docker exec "$container_name" curl -f http://localhost:18080/nifi-registry > /dev/null 2>&1; then
    echo -e "${RED} ❌ Error: NiFi Registry failed to start properly"
    echo -e "${RED}  Check logs: docker logs $container_name ${NC}"
    exit 1
fi

echo -e "${GREEN} ✅ NiFi Registry is running ${NC}"
echo ""

echo -e "${GREEN} ✅ NiFi Registry configured with GitHub integration ${NC}"
echo ""

# Install git in the container
docker exec -u root nifi-registry bash -c "apt-get update && apt-get install -y git"

if [ "$IS_IDOL_NIFI_GITHUB_INTEGRATION" = "TRUE" ]; then
    # Initialize Git repository inside container
    echo -e "${ORANGE} 🔧 Initializing Git repository...${NC}"
    if ! docker exec "$container_name" bash -c "
        cd /opt/nifi-registry/nifi-registry-current/flow_storage && \
        git init && \
        git config user.name '${GITHUB_USER}' && \
        git config user.email '${GITHUB_USER}@users.noreply.github.com' && \
        if git remote get-url origin >/dev/null 2>&1; then
            git remote set-url origin https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git
        else
            git remote add origin https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git
        fi && \
        git branch -M main
    "; then
        echo "❌ Failed to initialize git repository"
        exit 1
    fi

    echo -e "${GREEN} ✅ Git repository initialized ${NC}"
    echo ""
fi

echo ""
echo -e "${GREEN}============================================"
echo -e "${GREEN}✅ Setup Complete!"
echo -e "${GREEN}============================================"
echo ""
echo -e "${ORANGE}🌐 Access URLs:"
echo -e "${ORANGE}   NiFi Registry: http://localhost:18080/nifi-registry"
echo ""
#echo "🔐 NiFi Credentials:"
#echo "   Username: admin"
#echo "   Password: ctsBtRBKHRAx69EqUghvvgEvjnaLjFEB"
#echo ""
echo -e "${ORANGE} 📚 Next Steps:"
echo -e "${ORANGE}   1. Open NiFi: https://localhost:8443/nifi"
echo -e "${ORANGE}   2. Login with credentials above"
echo -e "${ORANGE}   3. Click menu (☰) → Controller Settings → Registry Clients"
echo -e "${ORANGE}   4. Add new Registry Client:"
echo -e "${ORANGE}      - Name: NiFi Registry"
echo -e "${ORANGE}      - URL: http://nifi-registry:18080"
echo -e "${ORANGE}   5. Create a bucket in NiFi Registry"
echo -e "${ORANGE}   6. Version control your process groups"
echo -e "${ORANGE}   7. Check your GitHub repository for committed flows!"
echo ""
echo -e "${ORANGE} 📋 Useful Commands:"
echo -e "${ORANGE}    View Registry logs:      docker logs -f nifi-registry"
echo -e "${ORANGE}    Stop all:                docker compose down"
echo -e "${ORANGE}    Restart Registry:        docker restart nifi-registry"
echo ""
