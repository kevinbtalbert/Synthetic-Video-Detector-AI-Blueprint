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

# Bundled NIM must not inherit Cloudera/Jupyter PYTHONPATH — it breaks gRPC servicer registration.
nim_bin_path="${bundle_root}/usr/local/bin:${bundle_root}/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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

collect_bundled_pythonpath() {
  local -a paths=("${bundle_root}/opt/nim")
  local site_dir
  while IFS= read -r site_dir; do
    paths+=("${site_dir}")
  done < <(
    find "${bundle_root}" -type d \( -name dist-packages -o -name site-packages \) 2>/dev/null | sort -u
  )
  local seen="" item
  for item in "${paths[@]}"; do
    [[ -n "${item}" && -d "${item}" ]] || continue
    case ":${seen}:" in
      *:"${item}":*) continue ;;
    esac
    seen="${seen}:${item}"
    printf '%s\n' "${item}"
  done
}
map_bundle_path() {
  local abs="$1"
  case "${abs}" in
    "${bundle_root}"/*)
      echo "${abs}"
      ;;
    /usr/local/bin/*|/usr/bin/*|/usr/local/lib/*|/opt/nim/*)
      local candidate="${bundle_root}${abs}"
      if [[ -e "${candidate}" ]]; then
        echo "${candidate}"
      else
        echo "${abs}"
      fi
      ;;
    *)
      echo "${abs}"
      ;;
  esac
}
read_script_shebang() {
  local script="$1"
  [[ -f "${script}" ]] || return 1
  head -1 "${script}" | sed 's/^#! *//'
}
nim_pythonpath="$(collect_bundled_pythonpath | paste -sd: -)"

ensure_nim_python_deps() {
  local vendor="${NIM_CACHE_PATH}/.nim_py_vendor"
  mkdir -p "${vendor}"
  if PYTHONPATH="${nim_pythonpath}" "${bundled_python}" -c "import wrapt" 2>/dev/null; then
    return 0
  fi
  echo "Installing bundled NIM python dependency: wrapt -> ${vendor}"
  if ! PYTHONPATH="${nim_pythonpath}" "${bundled_python}" -m pip install \
    --quiet --no-cache-dir --disable-pip-version-check --target "${vendor}" wrapt; then
    pip3 install --quiet --no-cache-dir --disable-pip-version-check --target "${vendor}" wrapt
  fi
  if [[ -d "${vendor}/wrapt" ]]; then
    nim_pythonpath="${nim_pythonpath}:${vendor}"
  fi
}

nim_ld_library_path="${bundle_root}/usr/local/lib:${bundle_root}/usr/lib/x86_64-linux-gnu"
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
  nim_ld_library_path="${nim_ld_library_path}:${LD_LIBRARY_PATH}"
fi

resolve_bundled_python() {
  local candidate shebang mapped
  for script in \
    "${bundle_root}/opt/nim/start_server.sh" \
    "${bundle_root}/usr/local/bin/start_server" \
    "${bundle_root}/start_server"; do
    shebang="$(read_script_shebang "${script}" 2>/dev/null || true)"
    if [[ -n "${shebang}" ]]; then
      mapped="$(map_bundle_path "${shebang}")"
      if [[ -x "${mapped}" ]]; then
        echo "${mapped}"
        return 0
      fi
    fi
  done
  for candidate in \
    "${bundle_root}/usr/local/bin/python3.12" \
    "${bundle_root}/usr/local/bin/python3" \
    "${bundle_root}/usr/bin/python3.12" \
    "${bundle_root}/usr/bin/python3"; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  if command -v python3.12 >/dev/null 2>&1; then
    command -v python3.12
    return 0
  fi
  command -v python3
}
bundled_python="$(resolve_bundled_python || true)"
if [[ -z "${bundled_python}" || ! -x "${bundled_python}" ]]; then
  echo "ERROR: no usable python for bundled NIM" >&2
  exit 1
fi
ensure_nim_python_deps

select_nim_profile() {
  local cap profile
  cap="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || true)"
  case "${cap}" in
    7.5)
      profile="ae4879839cd92b9ca86791d2455b3ce72261f485f00a89e2056e11c3e69d4bc3"
      ;;
    8.6|8.6*)
      profile="15d466e43b11fa523e0662603f09bce6e5c7fc92fba33ea5c6122b98ec546bd8"
      ;;
    8.9|8.9*)
      profile="6abf19cf36a0d5498b77c466780ac80c8224e641457f4f33a7df694810e2d746"
      ;;
    12.0|12.*)
      profile="3ce493f31eb1718ca928ae45a6995fc585f7571065106db509e7fce4b6f6d3aa"
      ;;
    8.*)
      profile="15d466e43b11fa523e0662603f09bce6e5c7fc92fba33ea5c6122b98ec546bd8"
      ;;
    *)
      profile="ae4879839cd92b9ca86791d2455b3ce72261f485f00a89e2056e11c3e69d4bc3"
      ;;
  esac
  echo "${profile}"
}
# Always pin hashed profile ID from GPU (svd_sm_* NGC tags are not valid NIM_MODEL_PROFILE values).
_nim_profile="$(select_nim_profile)"
export NIM_MODEL_PROFILE="${_nim_profile}"
unset NIM_MANIFEST_PROFILE 2>/dev/null || true
echo "Selected NIM_MODEL_PROFILE=${NIM_MODEL_PROFILE} (compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo unknown))"

workspace_dir="${bundle_root}/opt/nim/workspace"
mkdir -p "${workspace_dir}" 2>/dev/null || true
if [[ -w "${bundle_root}/opt/nim" ]]; then
  mkdir -p "${workspace_dir}"
fi

cd "${bundle_root}"
nvidia_entrypoint="$(tr -d '\n' <"${entrypoint_file}")"
if [[ ! -f "${nvidia_entrypoint}" ]]; then
  echo "ERROR: recorded NIM entrypoint missing: ${nvidia_entrypoint}" >&2
  exit 1
fi
require_access "${nvidia_entrypoint}" read

launch_nim() {
  local start_script="$1"
  echo "Launching NIM (sanitized PYTHONPATH): ${nvidia_entrypoint} ${start_script}"
  echo "  PYTHONPATH=${nim_pythonpath}"
  echo "  python=${bundled_python}"
  echo "  NIM_MODEL_PROFILE=${NIM_MODEL_PROFILE}"
  export PATH="${nim_bin_path}"
  export PYTHONPATH="${nim_pythonpath}"
  export NIM_MODEL_PROFILE
  unset NIM_MANIFEST_PROFILE 2>/dev/null || true
  export PYTHONNOUSERSITE=1
  export PYTHON="${bundled_python}"
  export LD_LIBRARY_PATH="${nim_ld_library_path}"
  unset PYTHONHOME PYTHONUSERBASE CONDA_PREFIX CONDA_DEFAULT_ENV 2>/dev/null || true
  exec bash "${nvidia_entrypoint}" "${start_script}"
}

start_server_file="${bundle_root}/start_server"
if [[ -f "${start_server_file}" ]]; then
  start_server_script="$(tr -d '\n' <"${start_server_file}")"
  launch_nim "${start_server_script}"
fi

if [[ -f "${bundle_root}/opt/nim/start_server.sh" ]]; then
  launch_nim "${bundle_root}/opt/nim/start_server.sh"
fi

echo "ERROR: start_server script not found under ${bundle_root}" >&2
exit 1
