#!/bin/bash
set -e

if [ -z "${R2_ACCESS_KEY}" ]; then
  echo "R2 secrets not configured, skipping cache proxy"
  exit 0
fi

# Use /tmp for bazel-remote binary to avoid permission issues if checked out readonly
CURL_DEST="/tmp/bazel-remote"
curl -fsSL -o "${CURL_DEST}" \
  "https://github.com/buchgr/bazel-remote/releases/download/v2.6.1/bazel-remote-2.6.1-linux-amd64"
echo "025d53aeb03a7fdd4a0e76262a5ae9eeee9f64d53ca510deff1c84cf3f276784  ${CURL_DEST}" | sha256sum -c -
chmod +x "${CURL_DEST}"

# Run bazel-remote in background
"${CURL_DEST}" \
  --s3.endpoint="${R2_ENDPOINT}" \
  --s3.bucket="bst-cache" \
  --s3.prefix="cas" \
  --s3.auth_method=access_key \
  --s3.access_key_id="${R2_ACCESS_KEY}" \
  --s3.secret_access_key="${R2_SECRET_KEY}" \
  --dir=/tmp/bazel-remote-cache \
  --max_size=5 \
  --http_address="0.0.0.0:${CACHE_HTTP_PORT}" \
  --grpc_address="0.0.0.0:${CACHE_GRPC_PORT}" \
  > /tmp/bazel-remote.log 2>&1 &
echo $! > /tmp/bazel-remote.pid

# Health check
for i in $(seq 1 30); do
  if curl -sf "http://localhost:${CACHE_HTTP_PORT}/status" > /dev/null 2>&1; then
    echo "bazel-remote is healthy (attempt ${i})"
    exit 0
  fi
  sleep 1
done
echo "::error::bazel-remote failed to start within 30 seconds"
cat /tmp/bazel-remote.log
exit 1
