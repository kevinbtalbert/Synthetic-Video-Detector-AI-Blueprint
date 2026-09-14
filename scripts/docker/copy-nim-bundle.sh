#!/usr/bin/env bash
# Copy Synthetic Video Detector NIM container rootfs into bundle prefix for CAI exec mode.
set -euo pipefail

src="${1:?source root (e.g. /nim-src)}"
dest="${2:?bundle dest (e.g. /opt/nvidia-nim/synthetic-video-detector)}"
nim_kind="${3:-synthetic-video-detector}"
record_script="${4:-/tmp/record-nim-bundle-entrypoint.sh}"

src="${src%/}"
dest="${dest%/}"

copy_tree() {
  local rel="$1"
  if [[ -e "${src}/${rel}" ]]; then
    mkdir -p "${dest}/$(dirname "${rel}")"
    cp -a "${src}/${rel}" "${dest}/${rel}"
  fi
}

mkdir -p "${dest}"

for rel in \
  opt/nim \
  opt/nvidia \
  opt/nvidia/deepstream \
  opt/tritonserver \
  opt/synthetic-detector \
  opt/maxine \
  usr/local/lib \
  usr/local/lib64 \
  usr/lib \
  usr/lib64 \
  lib \
  lib64; do
  copy_tree "${rel}"
done

# GStreamer typelibs + plugins (media_utils VideoReader requires Gst GI namespace).
for rel in \
  usr/lib/x86_64-linux-gnu/gstreamer-1.0 \
  usr/lib/x86_64-linux-gnu/girepository-1.0 \
  usr/lib/gstreamer-1.0 \
  usr/lib/girepository-1.0 \
  lib/x86_64-linux-gnu/gstreamer-1.0 \
  usr/libexec/gstreamer-1.0; do
  copy_tree "${rel}"
done

copy_python_site() {
  local rel
  for rel in \
    usr/local/lib/python3.12/dist-packages \
    usr/local/lib/python3.11/dist-packages \
    usr/lib/python3.12/dist-packages \
    usr/lib/python3/dist-packages; do
    if [[ -d "${src}/${rel}" ]]; then
      mkdir -p "${dest}/${rel}"
      cp -aL "${src}/${rel}/." "${dest}/${rel}/" 2>/dev/null || cp -a "${src}/${rel}/." "${dest}/${rel}/"
    fi
  done
}
copy_python_site

mkdir -p "${dest}/usr/local/bin" "${dest}/usr/bin"
if [[ -d "${src}/usr/local/bin" ]]; then
  cp -a "${src}/usr/local/bin/." "${dest}/usr/local/bin/" 2>/dev/null || true
  for bin in python3 python3.12 start_server; do
    [[ -e "${src}/usr/local/bin/${bin}" ]] && cp -aL "${src}/usr/local/bin/${bin}" "${dest}/usr/local/bin/${bin}" 2>/dev/null || true
  done
fi
for py in python3 python3.12; do
  [[ -e "${src}/usr/bin/${py}" ]] && cp -aL "${src}/usr/bin/${py}" "${dest}/usr/bin/${py}" 2>/dev/null || true
done

if ! find "${dest}" -path '*/dist-packages/nimlib' -type d 2>/dev/null | grep -q .; then
  echo "ERROR: nimlib not found under ${dest}" >&2
  exit 1
fi

py="$(find "${dest}" \( -path '*/usr/bin/python3*' -o -path '*/usr/local/bin/python3*' \) -type f 2>/dev/null | head -1)"
nimlib_dir="$(find "${dest}" -path '*/dist-packages/nimlib' -type d 2>/dev/null | head -1)"
site="$(dirname "${nimlib_dir}")"
dali_wheel="${dest}/opt/tritonserver/backends/dali/wheel/dali"
bundle_pythonpath="${dali_wheel}:${site}:${dest}/opt/nim"

export LD_LIBRARY_PATH="${dest}/usr/local/lib:${dest}/usr/lib/x86_64-linux-gnu:${dest}/usr/lib:${dest}/lib:${LD_LIBRARY_PATH:-}"

if [[ ! -d "${dest}/opt/synthetic-detector/src/grpc" ]]; then
  echo "ERROR: opt/synthetic-detector missing under ${dest} (required for gRPC start_service.sh)" >&2
  exit 1
fi
if [[ ! -x "${dest}/opt/synthetic-detector/src/grpc/start_service.sh" ]]; then
  echo "ERROR: start_service.sh missing under ${dest}/opt/synthetic-detector/src/grpc" >&2
  exit 1
fi

if [[ ! -d "${dali_wheel}/wrapt" ]]; then
  echo "ERROR: Triton DALI wheel (wrapt) missing at ${dali_wheel}" >&2
  exit 1
fi
if ! PYTHONPATH="${site}" "${py}" -c "import nimlib" >/dev/null 2>&1; then
  echo "ERROR: bundled python cannot import nimlib (python=${py} site=${site})" >&2
  exit 1
fi
if ! PYTHONPATH="${bundle_pythonpath}" "${py}" -c "import wrapt" >/dev/null 2>&1; then
  echo "ERROR: bundled python cannot import wrapt via DALI wheel path" >&2
  exit 1
fi
if ! PYTHONPATH="${bundle_pythonpath}" "${py}" -c "from opentelemetry.instrumentation.utils import http_status_to_status_code" >/dev/null 2>&1; then
  echo "ERROR: bundled python missing opentelemetry instrumentation deps" >&2
  exit 1
fi

if [[ ! -f "${dest}/usr/local/bin/start_server" ]]; then
  echo "ERROR: usr/local/bin/start_server missing under ${dest}" >&2
  exit 1
fi

manifest="$(find "${dest}/opt/nim" -path '*/etc/model_manifest.yaml' -type f 2>/dev/null | head -1 || true)"
if [[ -z "${manifest}" && ! -f "${dest}/opt/nim/etc/default/model_manifest.yaml" ]]; then
  echo "ERROR: model manifest missing under ${dest}/opt/nim/etc" >&2
  exit 1
fi

bash "${record_script}" "${dest}"
echo "SVD NIM bundle OK: ${dest} (includes opt/synthetic-detector for gRPC)"
