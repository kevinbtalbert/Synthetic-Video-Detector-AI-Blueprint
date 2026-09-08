#!/usr/bin/env bash
# Launch bundled Synthetic Video Detector NIM from the runtime image.
set -euo pipefail

nim_type="${1:?synthetic-video-detector}"
bundle_root="/opt/nvidia-nim/${nim_type}"
entrypoint_file="${bundle_root}/entrypoint"

if [[ ! -f "${entrypoint_file}" ]]; then
  echo "ERROR: NIM bundle not found at ${bundle_root}" >&2
  exit 1
fi

cache_root="${CDSW_PROJECT_DIR:-/home/cdsw}/volumes/models/${nim_type}"
baked_root="/opt/nvidia-nim/baked-model-cache/${nim_type}"
export NIM_CACHE_PATH="${NIM_CACHE_PATH:-${cache_root}}"
mkdir -p "${NIM_CACHE_PATH}"

if [[ "${NVIDIA_VISIBLE_DEVICES:-}" == "void" || "${NVIDIA_VISIBLE_DEVICES:-}" == "none" || -z "${NVIDIA_VISIBLE_DEVICES:-}" ]]; then
  gpu_uuid="$(nvidia-smi -L 2>/dev/null | sed -n 's/.*UUID: \([^)]*\)).*/\1/p' | head -1 || true)"
  if [[ -n "${gpu_uuid}" ]]; then
    export NVIDIA_VISIBLE_DEVICES="${gpu_uuid}"
  else
    export NVIDIA_VISIBLE_DEVICES=0
  fi
fi

if [[ -d "${baked_root}" && "$(ls -A "${baked_root}" 2>/dev/null || true)" != "" ]]; then
  if [[ ! -d "${NIM_CACHE_PATH}" || "$(ls -A "${NIM_CACHE_PATH}" 2>/dev/null || true)" == "" ]]; then
    echo "Seeding model cache from baked weights..."
    cp -a "${baked_root}/." "${NIM_CACHE_PATH}/"
  fi
fi

export NVCF_MODELS_DIR="${NIM_CACHE_PATH}"
export PYTHONPATH="${bundle_root}/opt/nim:${PYTHONPATH:-}"
export LD_LIBRARY_PATH="${bundle_root}/usr/local/lib:${bundle_root}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

cd "${bundle_root}"
exec bash "${entrypoint_file}"
