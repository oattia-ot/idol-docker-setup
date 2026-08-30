#!/bin/bash
# Functions to verify/install Docker, kubectl, helm, minikube, jq

check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    # Docker
    if ! check_command docker; then
        log "WARN" "Docker not found. Installing..."
        install_docker
    else
        log "INFO" "Docker is already installed."
    fi

    # kubectl
    if ! check_command kubectl; then
        log "WARN" "kubectl not found. Installing..."
        install_kubectl
    fi

    # helm
    if ! check_command helm; then
        log "WARN" "helm not found. Installing..."
        install_helm
    fi

    # minikube
    if ! check_command minikube; then
        log "WARN" "minikube not found. Installing..."
        install_minikube
    fi

    # jq (for JSON parsing)
    if ! check_command jq; then
        log "WARN" "jq not found. Installing..."
        sudo apt-get update && sudo apt-get install -y jq
    fi

    log "INFO" "All prerequisites satisfied."
}

install_docker() {
    # Official Docker install script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    sudo usermod -aG docker "$USER"
    log "WARN" "You may need to log out and back in for docker group changes to take effect."
    # Restart docker service
    sudo systemctl enable docker && sudo systemctl start docker
}

install_kubectl() {
    local version
    version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo install -o "$USER" -g "$USER" -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
}

install_helm() {
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
}

install_minikube() {
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
    sudo dpkg -i minikube_latest_amd64.deb
    rm minikube_latest_amd64.deb
}
