#!/bin/bash
# =============================================================
# Script: copy-nifi-extensions.sh
# Purpose: Copy IDOL NiFi extensions from the official image
#          to your host directory for persistent volume mount
# =============================================================

set -e  # Exit on any error

# Set default values for environment variables (can be overridden)
IDOL_REGISTRY="${IDOL_REGISTRY:-microfocusidolserver}"
IDOL_RICH_MEDIA_VERSION="${IDOL_RICH_MEDIA_VERSION:-26.1}"

echo "=== OpenText IDOL NiFi Extensions Copy Script ==="

echo "ℹ️  Using IDOL_REGISTRY=${IDOL_REGISTRY}"
echo "ℹ️  Using IDOL_RICH_MEDIA_VERSION=${IDOL_RICH_MEDIA_VERSION}"

# Define variables
IMAGE="${IDOL_REGISTRY}/nifi-ver2-full:${IDOL_RICH_MEDIA_VERSION}"
TEMP_CONTAINER="temp-nifi"
TARGET_DIR="./nifi/data/extensions"

echo "📦 Using image: ${IMAGE}"
echo "📁 Target directory: ${TARGET_DIR}"

# Create target directory if it doesn't exist
mkdir -p "${TARGET_DIR}"
echo "✅ Target directory created/verified."

# Remove old temp container if it exists
if docker ps -a --format '{{.Names}}' | grep -q "^${TEMP_CONTAINER}$"; then
    echo "🗑️  Removing old temporary container..."
    docker rm -f "${TEMP_CONTAINER}" >/dev/null 2>&1
fi

# Run temporary container
echo "🚀 Starting temporary NiFi container..."
docker run --rm -d --name "${TEMP_CONTAINER}" "${IMAGE}"

# Wait a few seconds for container to be ready
sleep 5

# Copy extensions
echo "📋 Copying extensions from container to host..."
docker cp "${TEMP_CONTAINER}:/opt/nifi/nifi-current/extensions/." "${TARGET_DIR}/"

echo "✅ Extensions successfully copied to ${TARGET_DIR}"

# Stop and remove the temporary container
echo "🛑 Stopping temporary container..."
docker stop "${TEMP_CONTAINER}" >/dev/null

echo ""
echo "🎉 Done! You can now use this volume mount in docker-compose:"
echo "   - ${TARGET_DIR}:/opt/nifi/nifi-current/extensions"
echo ""
echo "Next steps:"
echo "   1. docker compose down"
echo "   2. Uncomment the extensions volume in your docker-compose.yml"
echo "   3. docker compose up -d"