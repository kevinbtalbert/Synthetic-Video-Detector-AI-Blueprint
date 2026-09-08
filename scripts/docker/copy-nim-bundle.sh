#!/usr/bin/env bash
# Copy Synthetic Video Detector NIM container rootfs into bundle prefix.
set -euo pipefail

src="${1:?source root}"
dest="${2:?bundle dest}"
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
for rel in opt/nim opt/nvidia opt/tritonserver usr/local/lib usr/local/lib64 usr/lib usr/lib64 lib lib64; do
  copy_tree "${rel}"
done

for rel in opt/maxine; do
  copy_tree "${rel}"
done

mkdir -p "${dest}/usr/local/bin" "${dest}/usr/bin"
if [[ -d "${src}/usr/local/bin" ]]; then
  cp -a "${src}/usr/local/bin/." "${dest}/usr/local/bin/" 2>/dev/null || true
  for bin in python3 python3.12 start_server; do
    [[ -e "${src}/usr/local/bin/${bin}" ]] && cp -aL "${src}/usr/local/bin/${bin}" "${dest}/usr/local/bin/${bin}" 2>/dev/null || true
  done
fi

if ! find "${dest}" -path '*/dist-packages/nimlib' -type d 2>/dev/null | grep -q .; then
  echo "ERROR: nimlib not found under ${dest}" >&2
  exit 1
fi

bash "${record_script}" "${dest}"
echo "SVD NIM bundle OK: ${dest}"
