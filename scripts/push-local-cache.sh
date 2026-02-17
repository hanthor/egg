#!/bin/bash
set -e

# Configuration
REPO=${1:-"hanthor/egg"}
CACHE_DIR="$HOME/.cache/buildstream"
CORE_TAG="ghcr.io/${REPO}/cache-core:latest"

echo "Pushing local cache to $CORE_TAG..."

# 1. Verify Cache Directory
if [ ! -d "$CACHE_DIR" ]; then
    echo "Error: Local cache directory not found at $CACHE_DIR"
    exit 1
fi

# 2. Archive CAS (Use podman to handle permissions + excludes)
echo "Archiving local CAS (this may take a while)..."
# We use a container to run tar so we can handle root-owned files in the cache if necessary
# and to ensure consistent behavior with CI.
podman run --rm \
    -v "$CACHE_DIR:/input:ro" \
    -v "${PWD}:/output:rw" \
    docker.io/library/busybox:latest \
    sh -c "tar -cf /output/cas-core.tar -C /input --exclude 'cas/staging' --exclude 'cas/tmp' . || [ \$? -eq 1 ]"

# 3. Create Dockerfile (Busybox based)
echo "Creating Dockerfile..."
echo -e "FROM docker.io/library/busybox:latest\nCOPY cas-core.tar /cas.tar" > Dockerfile.cache

# 4. Build Image
echo "Building cache image..."
podman build -f Dockerfile.cache -t "$CORE_TAG" .

# 5. Push Image
echo "Pushing image to GHCR..."
echo "Ensure you are logged in: 'echo \$CR_PAT | podman login ghcr.io -u USERNAME --password-stdin'"
podman push "$CORE_TAG"

# Cleanup
rm cas-core.tar Dockerfile.cache

echo "Done! Cache pushed to $CORE_TAG"
