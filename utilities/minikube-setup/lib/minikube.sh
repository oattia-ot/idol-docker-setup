#!/bin/bash
# Functions to start Minikube, enable addons, configure registry

# IDOL OS detection (Ubuntu / macOS) — loads module/os-compat.sh when present
if [ -z "${IDOL_OS_COMPAT_LOADED:-}" ]; then
  _idol_os_src=""
  if [ -n "${IDOL_BASE_PATH:-}" ] && [ -f "${IDOL_BASE_PATH}/module/os-compat.sh" ]; then
    _idol_os_src="${IDOL_BASE_PATH}/module/os-compat.sh"
  else
    _idol_os_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    _idol_os_probe="$_idol_os_dir"
    _idol_os_i=0
    while [ -n "$_idol_os_probe" ] && [ "$_idol_os_probe" != "/" ] && [ "$_idol_os_i" -lt 20 ]; do
      if [ -f "$_idol_os_probe/module/os-compat.sh" ]; then
        _idol_os_src="$_idol_os_probe/module/os-compat.sh"
        break
      fi
      _idol_os_probe="$(dirname "$_idol_os_probe")"
      _idol_os_i=$((_idol_os_i + 1))
    done
  fi
  if [ -n "$_idol_os_src" ]; then
    # shellcheck source=/dev/null
    . "$_idol_os_src"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin)
        export IDOL_HOST_OS=macos IDOL_OS_FAMILY=macos
        ;;
      Linux)
        export IDOL_OS_FAMILY=linux
        if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release 2>/dev/null; then
          export IDOL_HOST_OS=ubuntu
        else
          export IDOL_HOST_OS=linux
        fi
        ;;
      *)
        export IDOL_HOST_OS=unknown IDOL_OS_FAMILY=unknown
        ;;
    esac
  fi
  unset _idol_os_src _idol_os_dir _idol_os_probe _idol_os_i
fi

start_minikube_profile() {
    local profile_key="$1"
    # Use the actual profile name from environment (set from JSON's Profile_Name)
    local profile_name="${MINIKUBE_PROFILE_NAME:-$profile_key}"

    # Check if already running
    if minikube status -p "$profile_name" &>/dev/null; then
        log "INFO" "Minikube profile '$profile_name' is already running."
        return 0
    fi

    log "INFO" "Starting Minikube profile '$profile_name'..."

    local cmd=(minikube start -p "$profile_name")
    [[ -n "${MINIKUBE_CPUS:-}" ]] && cmd+=(--cpus="$MINIKUBE_CPUS")
    [[ -n "${MINIKUBE_MEMORY:-}" ]] && cmd+=(--memory="${MINIKUBE_MEMORY}")
    [[ -n "${MINIKUBE_DISK_SIZE:-}" ]] && cmd+=(--disk-size="${MINIKUBE_DISK_SIZE}")
    [[ -n "${MINIKUBE_CONTAINER_RUNTIME:-}" ]] && cmd+=(--container-runtime="${MINIKUBE_CONTAINER_RUNTIME}")
    [[ -n "${MINIKUBE_NETWORK_POLICY:-}" ]] && cmd+=(--cni="${MINIKUBE_NETWORK_POLICY}")
    [[ -n "${MINIKUBE_INSECURE_REGISTRY:-}" ]] && cmd+=(--insecure-registry="${MINIKUBE_INSECURE_REGISTRY}")
    [[ -n "${MINIKUBE_KUBERNETES_VERSION:-}" ]] && cmd+=(--kubernetes-version="${MINIKUBE_KUBERNETES_VERSION}")
    cmd+=(--addons=ingress --install-addons=true)

    if ! "${cmd[@]}"; then
        die "Failed to start Minikube profile '$profile_name'"
    fi
    log "INFO" "Minikube profile '$profile_name' started."
}

configure_minikube_addons() {
    local profile_key="$1"
    # Use the actual profile name from environment (set from JSON's Profile_Name)
    local profile_name="${MINIKUBE_PROFILE_NAME:-$profile_key}"

    log "INFO" "Enabling addons for profile '$profile_name'..."
    minikube -p "$profile_name" addons enable ingress
    minikube -p "$profile_name" addons enable metrics-server
    minikube -p "$profile_name" addons enable dashboard

    # Set as active profile
    minikube profile "$profile_name"

    # Registry secret creation (example – adapt to your needs)
    if [[ -n "${REGISTRY_URL:-}" && -n "${REGISTRY_PROJECT:-}" ]]; then
        kubectl create namespace "${REGISTRY_PROJECT}" --dry-run=client -o yaml | kubectl apply -f -
        if kubectl get secret -n "$REGISTRY_PROJECT" registry-secret &>/dev/null; then
            kubectl delete secret -n "$REGISTRY_PROJECT" registry-secret
        fi
        kubectl create secret docker-registry registry-secret \
            --docker-server="$REGISTRY_URL/$REGISTRY_PROJECT" \
            --docker-username="${REGISTRY_USERNAME:-admin}" \
            --docker-password="${REGISTRY_PASSWORD:-Harbor12345}" \
            -n "$REGISTRY_PROJECT"
    fi
}
