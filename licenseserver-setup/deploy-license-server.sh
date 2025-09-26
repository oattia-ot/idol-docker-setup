#!/bin/bash

# Deploy License Server Script - DevOps Best Practices
# Author: DevOps Team
# Version: 1.0

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK_NAME="idol-network"
LICENSE_SERVER_PORT="20000"
HEALTH_CHECK_TIMEOUT=30
HEALTH_CHECK_INTERVAL=2

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
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
    if docker compose -f "$IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml" ps -q licenseserver 2>/dev/null | grep -q .; then
        log_info "Stopping license server container..."
        docker compose -f "$IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml" down || true
    fi
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment configuration..."
    
    if [ -z "${IDOL_LICENSE_SERVER_PATH:-}" ]; then
        log_error "IDOL_LICENSE_SERVER_PATH environment variable not set"
        log_error "Please set the variable manually or source the environment file:"
        log_error "  export IDOL_LICENSE_SERVER_PATH=$(pwd)"
        exit 1
    fi
    
    log_success "Environment loaded - License server path: $IDOL_LICENSE_SERVER_PATH"
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if docker is installed and running
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running or not accessible"
        exit 1
    fi
    
    # Check if docker compose is available
    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is not available"
        exit 1
    fi
    
    # Check if license server path exists
    if [ ! -d "$IDOL_LICENSE_SERVER_PATH" ]; then
        log_error "License server directory does not exist: $IDOL_LICENSE_SERVER_PATH"
        exit 1
    fi
    
    # Check if docker-compose.licenseserver.yml  exists
    if [ ! -f "$IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml" ]; then
        log_error "docker-compose.licenseserver.yml  not found at: $IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml"
        exit 1
    fi
    
    # Check if curl is available
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is not installed or not in PATH"
        exit 1
    fi
    
    log_success "All prerequisites validated"
}

# Function to create docker network
setup_docker_network() {
    log_info "Setting up Docker network: $NETWORK_NAME"
    
    if docker network ls | grep -q "$NETWORK_NAME"; then
        log_warning "Network '$NETWORK_NAME' already exists, skipping creation"
    else
        if docker network create "$NETWORK_NAME"; then
            log_success "Created Docker network: $NETWORK_NAME"
        else
            log_error "Failed to create Docker network: $NETWORK_NAME"
            exit 1
        fi
    fi
}

# Function to stop existing license server
stop_existing_server() {
    log_info "Stopping existing license server containers..."
    
    if docker compose -f "$IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml" ps -q licenseserver 2>/dev/null | grep -q .; then
        log_info "Found running license server, stopping..."
        docker compose -f "$IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml" down
        log_success "Stopped existing license server"
    else
        log_info "No running license server found"
    fi
}

# Function to clean license server files
clean_license_files() {
    log_info "Cleaning license server files..."
    
    local license_dir="$IDOL_LICENSE_SERVER_PATH/LicenseServer_25.3.0_LINUX_X86_64"
    
    if [ ! -d "$license_dir" ]; then
        log_warning "License directory not found: $license_dir"
        return 0
    fi
    
    # Remove lock file
    local lock_file="$license_dir/licenseserver.lck"
    if [ -f "$lock_file" ]; then
        if sudo rm -f "$lock_file"; then
            log_success "Removed lock file: $lock_file"
        else
            log_error "Failed to remove lock file: $lock_file"
            exit 1
        fi
    else
        log_info "Lock file not found (this is normal): $lock_file"
    fi
    
    # Remove uid directory
    local uid_dir="$license_dir/uid"
    if [ -d "$uid_dir" ]; then
        if sudo rm -rf "$uid_dir"; then
            log_success "Removed uid directory: $uid_dir"
        else
            log_error "Failed to remove uid directory: $uid_dir"
            exit 1
        fi
    else
        log_info "UID directory not found: $uid_dir"
    fi
    
    # Remove license directory
    local license_subdir="$license_dir/license"
    if [ -d "$license_subdir" ]; then
        if sudo rm -rf "$license_subdir"; then
            log_success "Removed license directory: $license_subdir"
        else
            log_error "Failed to remove license directory: $license_subdir"
            exit 1
        fi
    else
        log_info "License subdirectory not found: $license_subdir"
    fi
}

# Function to start license server
start_license_server() {
    log_info "Starting license server..."
    
    if docker compose -f "$IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml" up -d --build licenseserver; then
        log_success "License server container started"
    else
        log_error "Failed to start license server container"
        exit 1
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    log_info "Waiting for license server to be ready..."
    
    local count=0
    local max_attempts=$((HEALTH_CHECK_TIMEOUT / HEALTH_CHECK_INTERVAL))
    
    while [ $count -lt $max_attempts ]; do
        if curl -s --connect-timeout 5 "http://localhost:$LICENSE_SERVER_PORT/a=getlicenseinfo" >/dev/null 2>&1; then
            log_success "License server is ready!"
            return 0
        fi
        
        count=$((count + 1))
        log_info "Attempt $count/$max_attempts - Service not ready yet, waiting ${HEALTH_CHECK_INTERVAL}s..."
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    log_error "License server failed to become ready within ${HEALTH_CHECK_TIMEOUT} seconds"
    
    # Show container logs for debugging
    log_info "Container logs for debugging:"
    docker compose -f "$IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml" logs licenseserver --tail=20 || true
    
    return 1
}

# Function to test license server
test_license_server() {
    log_info "Testing license server functionality..."
    
    local response
    if response=$(curl -s --connect-timeout 10 "http://localhost:$LICENSE_SERVER_PORT/a=getlicenseinfo" 2>&1); then
        log_success "License server is responding"
        log_info "Response preview: ${response:0:200}..."
        return 0
    else
        log_error "License server test failed: $response"
        return 1
    fi
}

# Function to show deployment status
show_status() {
    log_info "Deployment Status:"
    echo "===================="
    
    # Show container status
    log_info "Container Status:"
    docker compose -f "$IDOL_LICENSE_SERVER_PATH/docker-compose.licenseserver.yml" ps
    
    # Show network info
    log_info "Network Status:"
    docker network ls | grep "$NETWORK_NAME" || log_warning "Network $NETWORK_NAME not found"
    
    # Show port status
    log_info "Port Status:"
    if netstat -ln 2>/dev/null | grep ":$LICENSE_SERVER_PORT " >/dev/null; then
        log_success "Port $LICENSE_SERVER_PORT is listening"
    else
        log_warning "Port $LICENSE_SERVER_PORT not found in netstat"
    fi
    
    echo "===================="
}

# Main deployment function
main() {
    log_info "Starting License Server Deployment"
    echo "===================================="
    
    # Load environment
    load_environment
    
    # Validate prerequisites
    validate_prerequisites
    
    # Setup Docker network
    setup_docker_network
    
    # Stop existing server
    stop_existing_server
    
    # Clean license files
    clean_license_files
    
    # Start license server
    start_license_server
    
    # Wait for service to be ready
    if ! wait_for_service; then
        log_error "License server deployment failed - service not ready"
        show_status
        exit 1
    fi
    
    # Test license server
    if ! test_license_server; then
        log_error "License server deployment failed - service test failed"
        show_status
        exit 1
    fi
    
    # Show final status
    show_status
    
    log_success "License Server Deployment Completed Successfully!"
    log_info "License server is available at: http://localhost:$LICENSE_SERVER_PORT"
    log_info "Test URL: http://localhost:$LICENSE_SERVER_PORT/a=getlicenseinfo"
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy IDOL License Server using Docker Compose"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --version  Show version information"
    echo ""
    echo "Environment:"
    echo "  Requires: IDOL_LICENSE_SERVER_PATH environment variable to be set"
    echo "  Example: export IDOL_LICENSE_SERVER_PATH=/opt/idol/licenseserver-setup"
    echo ""
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    -v|--version)
        echo "License Server Deployment Script v1.0"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
esac