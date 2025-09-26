#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<EOF
Usage: $(basename "$0") EXPORTED_NAME [REGISTRY] [IMAGE_NAME] [IMAGE_TAG]

Builds a custom NiFi Docker image with your nifi.properties baked in.

Arguments (preferred) or environment variables:
  [*] IDOL_EXPORTED_NAME  Exported name/alias for the image (mandatory)
  [*] IDOL_REGISTRY       Registry name (e.g. microfocusidolserver:<port>)
  [*] IDOL_IMAGE_NAME     Image name    (e.g. nifi-ver2-full)
  [?] IDOL_IMAGE_TAG      Image tag     (default: latest, e.g. 25.2)

Examples:
  ./$(basename "$0") idol-custom-nifi-secure microfocusidolserver:5000 nifi-ver2-full 25.2
  export IDOL_EXPORTED_NAME=my-nifi
  export IDOL_REGISTRY=microfocusidolserver:5000
  export IDOL_IMAGE_NAME=nifi-ver2-full
  export IDOL_IMAGE_TAG=25.2
  ./$(basename "$0")
EOF
}

# Handle -h flag
if [[ "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

# Assign variables from args or env vars
IDOL_EXPORTED_NAME="${1:-${IDOL_EXPORTED_NAME:-}}"
IDOL_REGISTRY="${2:-${IDOL_REGISTRY:-}}"
IDOL_IMAGE_NAME="${3:-${IDOL_IMAGE_NAME:-}}"
IDOL_IMAGE_TAG="${4:-${IDOL_IMAGE_TAG:-latest}}"

# Validate required vars
if [[ -z "$IDOL_EXPORTED_NAME" || -z "$IDOL_REGISTRY" || -z "$IDOL_IMAGE_NAME" ]]; then
  show_help
  exit 1
fi

# Define image name
IMAGE_TAG="${IDOL_REGISTRY}/${IDOL_IMAGE_NAME}:${IDOL_IMAGE_TAG}"

# Define export image name
EXPORTED_IMAGE_TAG="${IDOL_EXPORTED_NAME}/${IDOL_IMAGE_NAME}:${IDOL_IMAGE_TAG}"

echo "Checking if base image is accessible: $IMAGE_TAG"
if ! docker pull "$IMAGE_TAG" > /dev/null 2>&1; then
    echo "ERROR: Base image $IMAGE_TAG is not accessible. exiting without build failure."
    exit 1
else
    echo "Base image accessible. Proceeding with Docker build."
fi
# Define Nifi home path & default Nifi persistent volumes
NIFI_HOME=/opt/nifi/nifi-current
NIFI_DEFAULT_PERSISTENT=./nifi-persistent-volumes

# Generate dockerfile
cat > dockerfile <<EOF
FROM ${IMAGE_TAG}

# Copy custom NiFi properties
COPY ./nifi.properties ${NIFI_HOME}/conf/nifi.properties

# Copy persistent NiFi directories from prepared host folders
COPY ${NIFI_DEFAULT_PERSISTENT}/conf/ ${NIFI_HOME}/conf/
COPY ${NIFI_DEFAULT_PERSISTENT}/content_repository/ ${NIFI_HOME}/content_repository/
COPY ${NIFI_DEFAULT_PERSISTENT}/database_repository/ ${NIFI_HOME}/database_repository/
COPY ${NIFI_DEFAULT_PERSISTENT}/flowfile_repository/ ${NIFI_HOME}/flowfile_repository/
COPY ${NIFI_DEFAULT_PERSISTENT}/provenance_repository/ ${NIFI_HOME}/provenance_repository/
EOF

echo
echo "Generated dockerfile:"
cat dockerfile

# Build image
echo "Building Docker image: ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" .

# Optionally tag with exported name for convenience
echo "Tagging image as: ${EXPORTED_IMAGE_TAG}"
docker tag "${IMAGE_TAG}" "${EXPORTED_IMAGE_TAG}"

echo "Build complete."
