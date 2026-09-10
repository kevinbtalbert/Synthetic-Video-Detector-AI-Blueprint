#!/usr/bin/env bash
# Launch bundled Synthetic Video Detector NIM from the runtime image.
set -euo pipefail

nim_type="${1:?synthetic-video-detector}"
project="${CDSW_PROJECT_DIR:-/home/cdsw}"
bundle_root="/opt/nvidia-nim/${nim_type}"
entrypoint_file="${bundle_root}/entrypoint"

# CAI runtime images expose GPUs via nvidia-smi but omit CUDA sample deviceQuery.
# NIM entrypoint.d/51-gpu-sm-version-check.sh requires it — provide a minimal stub.
ensure_device_query_stub() {
  local stub_dir="${project}/cai/runtime/bin"
  local stub="${stub_dir}/deviceQuery"
  mkdir -p "${stub_dir}"
  if [[ -x "${stub}" ]]; then
    export PATH="${stub_dir}:${PATH}"
    return 0
  fi
  local cap major minor name
  cap="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || true)"
  major="${cap%%.*}"
  minor="${cap##*.}"
  name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "GPU")"
  cat >"${stub}" <<EOF
#!/usr/bin/env bash
echo "Detected 1 CUDA Capable device(s)"
echo "Device 0: \"${name}\""
echo "  CUDA Capability Major/Minor version number:    ${major:-7}.${minor:-5}"
exit 0
EOF
  chmod +x "${stub}"
  export PATH="${stub_dir}:${PATH}"
}
ensure_device_query_stub

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
