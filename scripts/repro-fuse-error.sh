#!/bin/bash
set -e

BST2_IMAGE="registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:f89b4aef847ef040b345acceda15a850219eb8f1"
WORK_DIR="$(pwd)"
CACHE_DIR="${WORK_DIR}/.cache/repro-bug"

# Clean start
rm -rf "${CACHE_DIR}"
mkdir -p "${CACHE_DIR}"

echo "=== Attempt 1: Current CI Configuration ==="
# Matches CI: --privileged --device /dev/fuse, volume mounts with :rw (CI doesn't use :z but I needed it locally)
# I will use :z here because I am on Fedora.
podman run --rm --privileged --device /dev/fuse \
    -v "${WORK_DIR}:/src:rw,z" \
    -v "${CACHE_DIR}:/root/.cache/buildstream:rw,z" \
    -w /src \
    "$BST2_IMAGE" \
    bst show oci/bluefin.bst

if [ $? -eq 0 ]; then
    echo "SUCCESS: Current config works locally?"
else
    echo "FAILURE: Reproduced FUSE error."
fi
