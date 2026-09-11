#!/usr/bin/env bash
# Build SyntheticVideoDetector runtime image with baked NIM weights.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${root}"

source "${root}/scripts/docker/nim-gpu-arch.sh"

VERSION="${SVD_RUNTIME_VERSION:-1.4}"
REPO="${SVD_RUNTIME_REPO:-synthetic-video-detector}"
REGISTRY="${SVD_RUNTIME_REGISTRY:-}"

if [[ -z "${NGC_API_KEY:-}" ]]; then
  echo "ERROR: export NGC_API_KEY before building." >&2
  exit 1
fi

echo "Step 1/2: Prefetch model cache (optional on non-GPU hosts) ..."
if command -v nvidia-smi >/dev/null 2>&1; then
  "${root}/scripts/docker/prefetch-nim-model-cache.sh" || true
fi

arch="$(nim_read_gpu_arch "${root}/build/nim-model-cache" "${NIM_PREFETCH_GPU:-all}")"
tags=("${REPO}:${VERSION}")
[[ "${arch}" != "unknown" ]] && tags+=("${REPO}:${VERSION}-${arch}")
if [[ -n "${REGISTRY}" ]]; then
  tags+=("${REGISTRY}/${REPO}:${VERSION}")
  [[ "${arch}" != "unknown" ]] && tags+=("${REGISTRY}/${REPO}:${VERSION}-${arch}")
fi

build_args=(docker build --platform linux/amd64)
for tag in "${tags[@]}"; do
  build_args+=(-t "${tag}")
done
build_args+=("$@" .)

echo "Step 2/2: docker build ..."
"${build_args[@]}"
echo "Built: ${tags[*]}"
