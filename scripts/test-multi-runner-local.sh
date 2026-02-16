#!/bin/bash
set -e

# Default to 3 parallel chunks for local testing
CHUNKS=${1:-3}
BST2_IMAGE="registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:f89b4aef847ef040b345acceda15a850219eb8f1"

# Prepare directories
WORK_DIR="$(pwd)"
CACHE_BASE="${WORK_DIR}/.cache/test-multi-runner"
rm -rf "${CACHE_BASE}"
mkdir -p "${CACHE_BASE}"
mkdir -p "${CACHE_BASE}/gen"

echo "=== Generating Build Matrix ($CHUNKS chunks) ==="
# We use a separate cache for generation to avoid polluting the chunk caches
podman run --rm \
    -v "${WORK_DIR}:/src:rw,z" \
    -v "${CACHE_BASE}/gen:/root/.cache/buildstream:rw,z" \
    -w /src \
    "$BST2_IMAGE" \
    python3 scripts/generate-build-matrix.py oci/bluefin.bst "$CHUNKS" > matrix.json

cat matrix.json

echo "=== Launching Builds ==="
# We run these sequentially in the script loop for simplicity of log output, 
# but in CI they run in parallel (different runners). To test isolation, we give each a FRESH cache.
# This simulates the "Fresh Runner" aspect of the CI plan.

python3 -c "
import json
import subprocess
import sys
import os

with open('matrix.json') as f:
    data = json.load(f)

for chunk_name, elements in data.items():
    if not elements.strip():
        print(f'Skipping empty {chunk_name}')
        continue
        
    print(f'Starting build for {chunk_name}...')
    # FRESH CACHE for each chunk simulation
    cache_dir = f'{os.environ[\"CACHE_BASE\"]}/{chunk_name}'
    os.makedirs(cache_dir, exist_ok=True)
    
    cmd = [
        'podman', 'run', '--rm', '--privileged', '--device', '/dev/fuse',
        '-v', f'{os.environ[\"WORK_DIR\"]}:/src:rw',
        '-v', f'{cache_dir}:/root/.cache/buildstream:rw',
        '-w', '/src',
        '${BST2_IMAGE}',
        'bash', '-c',
        f'ulimit -n 1048576; bst --no-interactive --config buildstream-ci.conf --log-file logs/build-{chunk_name}.log build {elements}'
    ]
    
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print(f'Build failed for {chunk_name}', file=sys.stderr)
        sys.exit(1)
        
    # Simulate artifact upload (creating tarball)
    print(f'Archiving CAS for {chunk_name}...')
    # We tar the contents of .cache/buildstream from the host perspective
    subprocess.run(['tar', '-cf', f'cas-{chunk_name}.tar', '-C', cache_dir, 'cas', 'artifacts', 'source_protos'], check=True)

"

if [ $? -ne 0 ]; then
    echo "Build failed."
    exit 1
fi

echo "=== Merging CAS Chunks ==="
MERGE_CACHE="${CACHE_BASE}/merged"
mkdir -p "${MERGE_CACHE}"

for tar in cas-*.tar; do
    if [ -f "$tar" ]; then
        echo "Merging $tar..."
        tar -xf "$tar" -C "${MERGE_CACHE}"
    fi
done

echo "=== Exporting Final Image ==="
podman run --rm --privileged --device /dev/fuse \
    -v "${WORK_DIR}:/src:rw" \
    -v "${MERGE_CACHE}:/root/.cache/buildstream:rw" \
    -w /src \
    "$BST2_IMAGE" \
    bash -c 'ulimit -n 1048576; bst --no-interactive --config buildstream-ci.conf artifact checkout --tar - oci/bluefin.bst' | podman load

echo "=== Build Complete ==="
# Cleanup
rm -f matrix.json cas-*.tar
