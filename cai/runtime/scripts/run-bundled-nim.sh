#!/usr/bin/env bash
# Launch bundled Synthetic Video Detector NIM (CAI all-in-one runtime).
#
# Stock NGC startup path:
#   1. nimlib start_server → inference.main()
#   2. NIM_DISABLE_GRPC_STARTUP=1 → HTTP only via GrpcNIMApiInterface (no service_class)
#   3. inference.main() execs /opt/synthetic-detector/src/grpc/start_service.sh → gRPC :8001
set -euo pipefail

nim_type="${1:-synthetic-video-detector}"
bundle_root="/opt/nvidia-nim/${nim_type}"
entrypoint_file="${bundle_root}/entrypoint"

if [[ ! -f "${entrypoint_file}" ]]; then
  echo "ERROR: NIM bundle not found at ${bundle_root}" >&2
  exit 1
fi

# CAI runtime images expose GPUs via nvidia-smi but omit CUDA sample deviceQuery.
ensure_device_query_stub() {
  local stub_dir
  for stub_dir in \
    "${CDSW_PROJECT_DIR:-/home/cdsw}/cai/runtime/bin" \
    "/opt/synthetic-video-detector/cai/runtime/bin"; do
    if [[ -x "${stub_dir}/deviceQuery" ]]; then
      export PATH="${stub_dir}:${PATH}"
      return 0
    fi
  done
  echo "WARNING: deviceQuery stub missing — NIM GPU check may fail" >&2
}
ensure_device_query_stub

cache_root="${CDSW_PROJECT_DIR:-/home/cdsw}/volumes/models/${nim_type}"
baked_root="/opt/nvidia-nim/baked-model-cache/${nim_type}"
export NIM_CACHE_PATH="${NIM_CACHE_PATH:-${cache_root}}"
mkdir -p "${NIM_CACHE_PATH}"

if [[ "${NVIDIA_VISIBLE_DEVICES:-}" == "void" || "${NVIDIA_VISIBLE_DEVICES:-}" == "none" || -z "${NVIDIA_VISIBLE_DEVICES:-}" ]]; then
  gpu_uuid="$(nvidia-smi -L 2>/dev/null | sed -n 's/.*UUID: \([^)]*\)).*/\1/p' | head -1 || true)"
  if [[ -n "${gpu_uuid}" ]]; then
    export NVIDIA_VISIBLE_DEVICES="${gpu_uuid}"
    echo "Adjusted NVIDIA_VISIBLE_DEVICES=${gpu_uuid}"
  else
    export NVIDIA_VISIBLE_DEVICES=0
  fi
fi

shm_mb="$(df -m /dev/shm 2>/dev/null | awk 'NR==2 {print $2}' || echo 0)"
if [[ "${shm_mb}" =~ ^[0-9]+$ ]] && (( shm_mb < 4096 )); then
  echo "ERROR: /dev/shm is only ${shm_mb}M — SVD NIM needs ~4–8 GB." >&2
  echo "  Project Settings → Engine → Advanced → Shared Memory Limit → 8192 MB" >&2
  exit 1
fi

dir_bytes() {
  [[ -d "$1" ]] && du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0
}

if [[ "${FORCE_CLEAR_NIM_CACHE:-}" == "1" ]]; then
  rm -rf "${NIM_CACHE_PATH:?}/"* "${NIM_CACHE_PATH:?}/".* 2>/dev/null || true
  rm -f /opt/nim/workspace/*.trt 2>/dev/null || true
fi

if [[ -d "${baked_root}" ]] && find "${baked_root}" -type f ! -name '.gitkeep' -print -quit 2>/dev/null | grep -q .; then
  if ! find "${NIM_CACHE_PATH}" -type f ! -name '.gitkeep' -print -quit 2>/dev/null | grep -q .; then
    echo "Seeding model cache from baked weights at ${baked_root} ..."
    cp -a "${baked_root}/." "${NIM_CACHE_PATH}/"
  fi
fi

link_bundle_opt_nim_layout() {
  local bundle_nim="${bundle_root}/opt/nim"
  local item name target manifest

  [[ -d "${bundle_nim}" ]] || { echo "ERROR: bundle opt/nim missing" >&2; exit 1; }
  [[ -w /opt/nim ]] || { echo "ERROR: /opt/nim not writable" >&2; exit 1; }

  shopt -s nullglob dotglob
  for item in "${bundle_nim}"/* "${bundle_nim}"/.[!.]* "${bundle_nim}"/..?*; do
    [[ -e "${item}" ]] || continue
    name="$(basename "${item}")"
    [[ "${name}" == ".cache" || "${name}" == "workspace" || "${name}" == .bundled_nim_launch_* ]] && continue
    target="/opt/nim/${name}"
    [[ -e "${target}" && ! -L "${target}" ]] && rm -rf "${target}"
    ln -sfn "${item}" "${target}"
  done
  shopt -u nullglob dotglob

  manifest="$(find "${bundle_nim}" -path '*/etc/model_manifest.yaml' -type f 2>/dev/null | head -1 || true)"
  [[ -z "${manifest}" ]] && manifest="/opt/nim/etc/default/model_manifest.yaml"
  export NIM_MANIFEST_PATH="${NIM_MANIFEST_PATH:-${manifest}}"
  mkdir -p /opt/nim/workspace
  echo "Linked bundled opt/nim → /opt/nim (manifest: ${NIM_MANIFEST_PATH})"
}

link_path() {
  local src="$1" target="$2"
  [[ -d "${src}" ]] || { echo "ERROR: missing bundled path ${src}" >&2; exit 1; }
  [[ -e "${target}" && ! -L "${target}" ]] && rm -rf "${target}"
  ln -sfn "${src}" "${target}"
  echo "Linked ${target} → ${src}"
}

configure_nim_image_env() {
  # Baked into NGC image — must restore or inference crashes (GrpcNIMApiInterface service_class None).
  export NIM_DISABLE_GRPC_STARTUP="${NIM_DISABLE_GRPC_STARTUP:-1}"
  export NIM_DIR_PATH="${NIM_DIR_PATH:-/opt/nim}"
  export NIM_LIB_PATH="${NIM_LIB_PATH:-/opt/nim/nimlib}"
  export NIM_WORKSPACE="${NIM_WORKSPACE:-/opt/nim/workspace}"
  export NIM_USE_MULTIPROCESSING_FOR_INFERENCE="${NIM_USE_MULTIPROCESSING_FOR_INFERENCE:-true}"
  export NIM_INFERENCE_TYPE="${NIM_INFERENCE_TYPE:-grpc}"
  export NIM_USE_MODEL_MANIFEST_V0="${NIM_USE_MODEL_MANIFEST_V0:-False}"
  export TRITON_SERVER_GPU_ENABLED="${TRITON_SERVER_GPU_ENABLED:-1}"
  export NIM_MODEL_NAME="${NIM_MODEL_NAME:-SyntheticDetector}"
  export NIM_NAME="${NIM_NAME:-SyntheticDetector}"
  export NVCF_MODELS_DIR="${NVCF_MODELS_DIR:-/config/models/synthetic-detector}"
  export SYNTHETIC_DETECTOR_ROOT="${SYNTHETIC_DETECTOR_ROOT:-/opt/synthetic-detector}"
  export NIM_HTTP_API_PORT="${NIM_HTTP_API_PORT:-8000}"
  export NIM_GRPC_API_PORT="${NIM_GRPC_API_PORT:-8001}"
}

select_nim_profile() {
  local cap profile
  cap="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || true)"
  case "${cap}" in
    7.5) profile="ae4879839cd92b9ca86791d2455b3ce72261f485f00a89e2056e11c3e69d4bc3" ;;
    8.6|8.6*) profile="15d466e43b11fa523e0662603f09bce6e5c7fc92fba33ea5c6122b98ec546bd8" ;;
    8.9|8.9*) profile="6abf19cf36a0d5498b77c466780ac80c8224e641457f4f33a7df694810e2d746" ;;
    12.0|12.*) profile="3ce493f31eb1718ca928ae45a6995fc585f7571065106db509e7fce4b6f6d3aa" ;;
    8.*) profile="15d466e43b11fa523e0662603f09bce6e5c7fc92fba33ea5c6122b98ec546bd8" ;;
    *) profile="ae4879839cd92b9ca86791d2455b3ce72261f485f00a89e2056e11c3e69d4bc3" ;;
  esac
  echo "${profile}"
}

build_nim_pythonpath() {
  local -a parts=()
  local d dali_wheel="${bundle_root}/opt/tritonserver/backends/dali/wheel/dali"
  [[ -d "${dali_wheel}" ]] && parts+=("${dali_wheel}")
  for d in \
    "${bundle_root}/opt/nim" \
    "${bundle_root}/opt/nim/workspace" \
    "${bundle_root}/opt/maxine" \
    "${bundle_root}/.nim_py_vendor" \
    "${NIM_CACHE_PATH}/.nim_py_vendor" \
    "${bundle_root}/usr/local/lib/python3.12/dist-packages" \
    "${bundle_root}/usr/lib/python3/dist-packages"; do
    [[ -d "${d}" ]] && parts+=("${d}")
  done
  local IFS=:
  echo "${parts[*]}"
}

resolve_nim_python() {
  local py site nimlib_dir
  while IFS= read -r nimlib_dir; do
    site="$(dirname "${nimlib_dir}")"
    for py in \
      "${bundle_root}/usr/local/bin/python3.12" \
      "${bundle_root}/usr/local/bin/python3" \
      "${bundle_root}/usr/bin/python3.12" \
      "${bundle_root}/usr/bin/python3"; do
      [[ -x "${py}" ]] || continue
      if PYTHONPATH="${site}" "${py}" -c "import nimlib" >/dev/null 2>&1; then
        echo "${py}"
        return 0
      fi
    done
  done < <(find "${bundle_root}" -path '*/dist-packages/nimlib' -type d 2>/dev/null)
  return 1
}

resolve_start_server() {
  if [[ -f "${bundle_root}/usr/local/bin/start_server" ]]; then
    printf '%s\n' "${bundle_root}/usr/local/bin/start_server"
    return 0
  fi
  find "${bundle_root}" -path '*/usr/local/bin/start_server' -type f 2>/dev/null | head -1
}

# --- Runtime layout ---
if [[ ! -d /opt/nim ]]; then
  mkdir -p /opt/nim 2>/dev/null || { echo "ERROR: cannot create /opt/nim" >&2; exit 1; }
fi
if [[ -e /opt/nim/.cache && ! -L /opt/nim/.cache ]]; then
  rm -rf /opt/nim/.cache
fi
ln -sfn "${NIM_CACHE_PATH}" /opt/nim/.cache
export NIM_CACHE_DIR="/opt/nim/.cache"

link_bundle_opt_nim_layout
link_path "${bundle_root}/opt/tritonserver" /opt/tritonserver
link_path "${bundle_root}/opt/synthetic-detector" /opt/synthetic-detector

configure_nim_image_env

export NIM_MODEL_PROFILE="$(select_nim_profile)"
unset NIM_MANIFEST_PROFILE 2>/dev/null || true
echo "Selected NIM_MODEL_PROFILE=${NIM_MODEL_PROFILE} (compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo unknown))"

prepare_models_script=""
for candidate in \
  "${CDSW_PROJECT_DIR:-}/cai/runtime/scripts/prepare-bundled-nim-models.sh" \
  /usr/local/bin/prepare-bundled-nim-models \
  /opt/synthetic-video-detector/cai/runtime/scripts/prepare-bundled-nim-models.sh; do
  if [[ -f "${candidate}" ]]; then
    prepare_models_script="${candidate}"
    break
  fi
done
if [[ -n "${prepare_models_script}" ]]; then
  chmod +x "${prepare_models_script}" 2>/dev/null || true
  bash "${prepare_models_script}" "${nim_type}" "${NIM_CACHE_PATH}"
fi

for lib in \
  /opt/tritonserver/lib \
  /opt/tritonserver/backends/nv_arsdk_backend \
  "${bundle_root}/usr/local/lib" \
  "${bundle_root}/usr/lib/x86_64-linux-gnu" \
  "${bundle_root}/usr/lib" \
  "${bundle_root}/lib"; do
  [[ -d "${lib}" ]] && export LD_LIBRARY_PATH="${lib}:${LD_LIBRARY_PATH:-}"
done

export PATH="${bundle_root}/usr/local/bin:${bundle_root}/usr/bin:/opt/tritonserver/bin:${PATH}"

nim_python="$(resolve_nim_python || true)"
start_server="$(resolve_start_server || true)"
if [[ -z "${nim_python}" || -z "${start_server}" ]]; then
  echo "ERROR: bundled NIM python or start_server missing under ${bundle_root}" >&2
  exit 1
fi
chmod +x "${start_server}" 2>/dev/null || true

nim_pythonpath="$(build_nim_pythonpath)"

# wrapt fallback (image also pre-installs to .nim_py_vendor at build time)
vendor="${NIM_CACHE_PATH}/.nim_py_vendor"
mkdir -p "${vendor}"
if ! PYTHONNOUSERSITE=1 PYTHONPATH="${nim_pythonpath}:${vendor}" "${nim_python}" -c "import wrapt" 2>/dev/null; then
  echo "Installing wrapt → ${vendor}"
  env PIP_USER=0 PIP_BREAK_SYSTEM_PACKAGES=1 PYTHONNOUSERSITE=1 \
    "${nim_python}" -m pip install --quiet --no-cache-dir --disable-pip-version-check \
    --no-user --isolated --break-system-packages --target "${vendor}" wrapt
  nim_pythonpath="${nim_pythonpath}:${vendor}"
fi

if ! PYTHONNOUSERSITE=1 PYTHONPATH="${nim_pythonpath}" "${nim_python}" -c "
import wrapt
import nimlib
import inference
from opentelemetry.instrumentation.utils import http_status_to_status_code
print('bootstrap OK')
"; then
  echo "ERROR: bundled NIM bootstrap import failed" >&2
  exit 1
fi

if [[ ! -x /opt/synthetic-detector/src/grpc/start_service.sh ]]; then
  echo "ERROR: /opt/synthetic-detector/src/grpc/start_service.sh missing — rebuild runtime 1.5.1+" >&2
  exit 1
fi

entrypoint="$(tr -d '\n' <"${entrypoint_file}")"
[[ -x "${entrypoint}" ]] || chmod +x "${entrypoint}" 2>/dev/null || true

launch_wrapper="/opt/nim/.bundled_nim_launch_${nim_type}.sh"
cat >"${launch_wrapper}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1
export PYTHONPATH="${nim_pythonpath}"
export PATH="${PATH}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export NIM_CACHE_DIR="/opt/nim/.cache"
export NIM_CACHE_PATH="${NIM_CACHE_PATH}"
export NIM_HTTP_API_PORT="${NIM_HTTP_API_PORT}"
export NIM_GRPC_API_PORT="${NIM_GRPC_API_PORT}"
export NIM_DISABLE_GRPC_STARTUP="${NIM_DISABLE_GRPC_STARTUP}"
export NIM_DIR_PATH="${NIM_DIR_PATH}"
export NIM_LIB_PATH="${NIM_LIB_PATH}"
export NIM_WORKSPACE="${NIM_WORKSPACE}"
export NIM_USE_MULTIPROCESSING_FOR_INFERENCE="${NIM_USE_MULTIPROCESSING_FOR_INFERENCE}"
export NIM_INFERENCE_TYPE="${NIM_INFERENCE_TYPE}"
export NIM_USE_MODEL_MANIFEST_V0="${NIM_USE_MODEL_MANIFEST_V0}"
export NIM_MODEL_NAME="${NIM_MODEL_NAME}"
export NIM_NAME="${NIM_NAME}"
export NVCF_MODELS_DIR="${NVCF_MODELS_DIR}"
export SYNTHETIC_DETECTOR_ROOT="${SYNTHETIC_DETECTOR_ROOT}"
export TRITON_SERVER_GPU_ENABLED="${TRITON_SERVER_GPU_ENABLED}"
export NIM_MODEL_PROFILE="${NIM_MODEL_PROFILE}"
export NIM_MANIFEST_PATH="${NIM_MANIFEST_PATH:-}"
export NGC_API_KEY="${NGC_API_KEY:-}"
export NVIDIA_VISIBLE_DEVICES="${NVIDIA_VISIBLE_DEVICES:-}"
export NVIDIA_DRIVER_CAPABILITIES="${NVIDIA_DRIVER_CAPABILITIES:-all}"
export MAXINE_MAX_INPUT_FILE_SIZE_MB="${MAXINE_MAX_INPUT_FILE_SIZE_MB:-500}"
cd /opt/nim
exec "${nim_python}" "${start_server}"
EOF
chmod +x "${launch_wrapper}"

echo "Starting bundled ${nim_type} NIM"
echo "  NIM_DISABLE_GRPC_STARTUP=${NIM_DISABLE_GRPC_STARTUP} (HTTP via nimlib; gRPC via start_service.sh)"
echo "  NVCF_MODELS_DIR=${NVCF_MODELS_DIR}"
echo "  SYNTHETIC_DETECTOR_ROOT=${SYNTHETIC_DETECTOR_ROOT}"
echo "  NIM_PYTHON=${nim_python}"
echo "  START_SERVER=${start_server}"
echo "  LAUNCH_WRAPPER=${launch_wrapper}"
echo "  NIM_CACHE_PATH=${NIM_CACHE_PATH}"
echo "  NGC_API_KEY set: $([ -n "${NGC_API_KEY:-}" ] && echo yes || echo NO)"

exec "${entrypoint}" "${launch_wrapper}"
