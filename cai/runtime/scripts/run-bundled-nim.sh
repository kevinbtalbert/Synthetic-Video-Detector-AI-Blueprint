#!/usr/bin/env bash
# Launch bundled Synthetic Video Detector NIM from the runtime image.
set -euo pipefail

nim_type="${1:?synthetic-video-detector}"
project="${CDSW_PROJECT_DIR:-/home/cdsw}"
bundle_root="/opt/nvidia-nim/${nim_type}"
entrypoint_file="${bundle_root}/entrypoint"

require_access() {
  local path="$1" mode="$2"
  case "${mode}" in
    read)
      [[ -r "${path}" ]] || {
        echo "ERROR: not readable by $(id -un): ${path}" >&2
        exit 1
      }
      ;;
    write)
      [[ -w "${path}" ]] || {
        echo "ERROR: not writable by $(id -un): ${path}" >&2
        exit 1
      }
      ;;
    exec)
      [[ -x "${path}" ]] || {
        echo "ERROR: not executable by $(id -un): ${path}" >&2
        exit 1
      }
      ;;
  esac
}

# CAI runtime images expose GPUs via nvidia-smi but omit CUDA sample deviceQuery.
# NIM entrypoint.d/51-gpu-sm-version-check.sh requires it — provide a minimal stub.
ensure_device_query_stub() {
  local stub_dir="${project}/cai/runtime/bin"
  local stub="${stub_dir}/deviceQuery"
  mkdir -p "${stub_dir}"
  require_access "${stub_dir}" write
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
  chmod u=rwx,go=rx "${stub}"
  export PATH="${stub_dir}:${PATH}"
}
ensure_device_query_stub

if [[ ! -f "${entrypoint_file}" ]]; then
  echo "ERROR: NIM bundle not found at ${bundle_root}" >&2
  exit 1
fi
require_access "${bundle_root}" read
require_access "${entrypoint_file}" read

cache_root="${CDSW_PROJECT_DIR:-/home/cdsw}/volumes/models/${nim_type}"
baked_root="/opt/nvidia-nim/baked-model-cache/${nim_type}"
export NIM_CACHE_PATH="${NIM_CACHE_PATH:-${cache_root}}"
mkdir -p "${NIM_CACHE_PATH}"
require_access "${NIM_CACHE_PATH}" write

if [[ "${NVIDIA_VISIBLE_DEVICES:-}" == "void" || "${NVIDIA_VISIBLE_DEVICES:-}" == "none" || -z "${NVIDIA_VISIBLE_DEVICES:-}" ]]; then
  gpu_uuid="$(nvidia-smi -L 2>/dev/null | sed -n 's/.*UUID: \([^)]*\)).*/\1/p' | head -1 || true)"
  if [[ -n "${gpu_uuid}" ]]; then
    export NVIDIA_VISIBLE_DEVICES="${gpu_uuid}"
  else
    export NVIDIA_VISIBLE_DEVICES=0
  fi
fi

cache_has_models() {
  find "${NIM_CACHE_PATH}" -type f ! -name '.gitkeep' -print -quit 2>/dev/null | grep -q .
}

if [[ -d "${baked_root}" ]] && find "${baked_root}" -type f ! -name '.gitkeep' -print -quit 2>/dev/null | grep -q .; then
  if ! cache_has_models; then
    echo "Seeding model cache from baked weights..."
    cp -a "${baked_root}/." "${NIM_CACHE_PATH}/"
  fi
fi

export NVCF_MODELS_DIR="${NIM_CACHE_PATH}"
export PATH="${bundle_root}/usr/local/bin:${bundle_root}/usr/bin:${PATH:-}"

# nimlib hardcodes /opt/nim; map bundled layout when the canonical path is absent.
if [[ ! -e /opt/nim && -d "${bundle_root}/opt/nim" ]]; then
  if [[ -w /opt ]]; then
    ln -sf "${bundle_root}/opt/nim" /opt/nim
  else
    export NIM_ROOT="${bundle_root}/opt/nim"
    for candidate in \
      "${bundle_root}/opt/nim/etc/model_manifest.yaml" \
      "${bundle_root}/opt/nim/etc/default/model_manifest.yaml"; do
      if [[ -f "${candidate}" ]]; then
        export NIM_MANIFEST_PATH="${candidate}"
        break
      fi
    done
    if [[ -z "${NIM_MANIFEST_PATH:-}" ]]; then
      manifest="$(find "${bundle_root}/opt/nim" -name 'model_manifest.yaml' -type f 2>/dev/null | head -1 || true)"
      [[ -n "${manifest}" ]] && export NIM_MANIFEST_PATH="${manifest}"
    fi
  fi
fi

nimlib_dir="$(find "${bundle_root}" -path '*/dist-packages/nimlib' -type d 2>/dev/null | head -1 || true)"
python_paths=("${bundle_root}/opt/nim")
if [[ -n "${nimlib_dir}" ]]; then
  python_paths+=("$(dirname "${nimlib_dir}")")
fi
export PYTHONPATH="$(IFS=:; echo "${python_paths[*]}")${PYTHONPATH:+:${PYTHONPATH}}"

if [[ -x "${bundle_root}/usr/local/bin/python3" ]]; then
  export PYTHON="${bundle_root}/usr/local/bin/python3"
fi

export LD_LIBRARY_PATH="${bundle_root}/usr/local/lib:${bundle_root}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

cd "${bundle_root}"
nvidia_entrypoint="$(tr -d '\n' <"${entrypoint_file}")"
if [[ ! -f "${nvidia_entrypoint}" ]]; then
  echo "ERROR: recorded NIM entrypoint missing: ${nvidia_entrypoint}" >&2
  exit 1
fi
require_access "${nvidia_entrypoint}" read

start_server_file="${bundle_root}/start_server"
if [[ -f "${start_server_file}" ]]; then
  start_server_script="$(tr -d '\n' <"${start_server_file}")"
  echo "Launching NIM: ${nvidia_entrypoint} ${start_server_script}"
  exec bash "${nvidia_entrypoint}" "${start_server_script}"
fi

if [[ -f "${bundle_root}/opt/nim/start_server.sh" ]]; then
  echo "Launching NIM: ${nvidia_entrypoint} ${bundle_root}/opt/nim/start_server.sh"
  exec bash "${nvidia_entrypoint}" "${bundle_root}/opt/nim/start_server.sh"
fi

echo "ERROR: start_server script not found under ${bundle_root}" >&2
exit 1
