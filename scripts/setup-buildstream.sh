#!/bin/bash
set -e

mkdir -p logs
cat > buildstream-ci.conf <<'BSTCONF'
scheduler:
  on-error: continue
  fetchers: 12
  builders: 1
  network-retries: 3

logging:
  message-format: '[%{wallclock}][%{elapsed}][%{key}][%{element}] %{action} %{message}'
  error-lines: 80

build:
  max-jobs: 0
  retry-failed: True

cache:
  cache-buildtrees: never
BSTCONF

# If cache proxy is running, add it as an artifact remote.
if [ -f /tmp/bazel-remote.pid ]; then
  cat >> buildstream-ci.conf <<BSTPUSH
artifacts:
  servers:
    - url: "grpc://localhost:${CACHE_GRPC_PORT}"
      type: storage
      push: true
BSTPUSH
fi

cat buildstream-ci.conf
