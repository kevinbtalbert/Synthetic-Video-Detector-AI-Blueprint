#!/usr/bin/env bash
# Prefetch SVD NIM model cache on build host (requires GPU + docker + NGC login).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cache="${root}/build/nim-model-cache/synthetic-video-detector"
image="${SVD_NIM_IMAGE:-nvcr.io/nim/nvidia/synthetic-video-detector:latest}"

if [[ -z "${NGC_API_KEY:-}" ]]; then
  echo "ERROR: export NGC_API_KEY before prefetch." >&2
  exit 1
fi

mkdir -p "${cache}"
echo "Prefetching SVD models into ${cache} ..."

docker run --rm --gpus all \
  -e NGC_API_KEY="${NGC_API_KEY}" \
  -v "${cache}:/opt/nim/.cache" \
  "${image}" \
  bash -lc 'test -d /opt/nim/.cache && ls -la /opt/nim/.cache | head -20'

if [[ -z "$(ls -A "${cache}" 2>/dev/null || true)" ]]; then
  echo "WARNING: cache directory is empty — first runtime start will download models." >&2
fi

echo "Prefetch complete."
