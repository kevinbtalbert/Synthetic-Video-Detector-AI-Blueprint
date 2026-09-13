#!/usr/bin/env bash
# Wire SVD TensorRT engines into /opt/nim/workspace for gRPC startup.
#
# Official NIM layout:
#   NVCF_MODELS_DIR=/config/models/synthetic-detector  (symlink -> /opt/nim/workspace at runtime)
#   /opt/synthetic-detector/weights/tensorrt -> /config/models/synthetic-detector
#   Engines: dinov2_fp32_<cc>.trt, dinov3_fp32_<cc>.trt in workspace
set -euo pipefail

nim_type="${1:?synthetic-video-detector}"
cache="${2:-${NIM_CACHE_PATH:-}}"

[[ "${nim_type}" == "synthetic-video-detector" ]] || {
  echo "ERROR: unknown nim_type '${nim_type}'" >&2
  exit 1
}

if [[ -z "${cache}" || ! -d "${cache}" ]]; then
  exit 0
fi

ws="/opt/nim/workspace"
mount_name="synthetic-detector"
hub="models--nim--nvidia--synthetic-video-detector"
config_mount="/opt/nim/.config-root/models/${mount_name}"

if [[ ! -w /opt/nim ]]; then
  echo "ERROR: /opt/nim is not writable — rebuild SyntheticVideoDetector runtime (Dockerfile chown cdsw)." >&2
  exit 1
fi

mkdir -p /opt/nim/workspace /opt/nim/.config-root/models "${ws}"

gpu_cc="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '[:space:].')"
cc_suffix=""
case "${gpu_cc}" in
  7.5|75) cc_suffix="75" ;;
  8.6|86) cc_suffix="86" ;;
  8.9|89) cc_suffix="89" ;;
  12.0|120|12) cc_suffix="120" ;;
  8.*) cc_suffix="86" ;;
esac

link_trt_from_dir() {
  local src="$1"
  local f bn
  [[ -d "${src}" ]] || return 0
  shopt -s nullglob
  for f in "${src}"/*.trt; do
    bn="$(basename "${f}")"
    if [[ -n "${cc_suffix}" && "${bn}" == *"_${cc_suffix}.trt" ]]; then
      rm -f "${ws}/${bn}"
      cp -f "${f}" "${ws}/${bn}" 2>/dev/null || ln -sf "${f}" "${ws}/${bn}"
    fi
  done
  shopt -u nullglob
}

best_snap=""
best_count=0
while IFS= read -r candidate; do
  count="$(find "${candidate}" -maxdepth 1 -name '*.trt' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ -n "${gpu_cc}" && "${candidate}" == *"sm${gpu_cc}"* ]] && (( count >= best_count )); then
    best_count="${count}"
    best_snap="${candidate}"
  elif [[ -z "${best_snap}" ]] && (( count > best_count )); then
    best_count="${count}"
    best_snap="${candidate}"
  fi
done < <(find "${cache}" -type d -path "*/${hub}/snapshots/*" 2>/dev/null)

if [[ -n "${best_snap}" ]]; then
  link_trt_from_dir "${best_snap}"
fi

# Also scan cache root for materialized .trt (runtime download layout).
while IFS= read -r trt; do
  bn="$(basename "${trt}")"
  if [[ -n "${cc_suffix}" && "${bn}" == *"_${cc_suffix}.trt" && ! -f "${ws}/${bn}" ]]; then
    cp -f "${trt}" "${ws}/${bn}" 2>/dev/null || ln -sf "${trt}" "${ws}/${bn}"
  fi
done < <(find "${cache}" -name '*.trt' 2>/dev/null | head -20)

ln -sfn "${ws}" "${config_mount}"
mkdir -p /config/models 2>/dev/null || true
if [[ -e /config/models/${mount_name} && ! -L /config/models/${mount_name} ]]; then
  rm -rf "/config/models/${mount_name}"
fi
ln -sfn "${ws}" "/config/models/${mount_name}" 2>/dev/null || true

engine_count="$(find "${ws}" -maxdepth 1 -name '*.trt' 2>/dev/null | wc -l | tr -d ' ')"
echo "prepare-bundled-nim-models: ${nim_type} workspace=${ws} trt_engines=${engine_count} gpu_cc=${gpu_cc:-unknown}"
if [[ "${engine_count}" == "0" ]]; then
  echo "  No .trt engines in workspace yet — NIM will download on startup (needs NGC_API_KEY)." >&2
fi
