#!/usr/bin/env bash
# GStreamer + GObject introspection for bundled SVD NIM (video decode via media_utils).
set -euo pipefail

bundle_root="${1:-/opt/nvidia-nim/synthetic-video-detector}"

echo "Installing system GStreamer packages for bundled NIM..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ffmpeg \
  gstreamer1.0-tools \
  gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad \
  gstreamer1.0-libav \
  gstreamer1.0-plugins-ugly \
  gstreamer1.0-x \
  libgstreamer1.0-0 \
  libgstreamer-plugins-base1.0-0 \
  libgstreamer-plugins-good1.0-0 \
  gir1.2-gstreamer-1.0 \
  gir1.2-gst-plugins-base-1.0
rm -rf /var/lib/apt/lists/*

verify_decode="/tmp/verify-nim-video-decode.sh"
if [[ ! -f "${verify_decode}" ]]; then
  verify_decode="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-nim-video-decode.sh"
fi

nim_py=""
for candidate in \
  "${bundle_root}/usr/local/bin/python3.12" \
  "${bundle_root}/usr/bin/python3.12"; do
  if [[ -x "${candidate}" ]]; then
    nim_py="${candidate}"
    break
  fi
done

if [[ -z "${nim_py}" ]]; then
  echo "WARNING: NIM python not found — skipping Gst import check" >&2
  exit 0
fi

# shellcheck disable=SC1091
source /usr/local/bin/nim-gstreamer-env.sh
export NIM_BUNDLE_ROOT="$(dirname "${bundle_root}")"

if ! "${nim_py}" -c "import gi; gi.require_version('Gst','1.0'); from gi.repository import Gst; Gst.init(None); print('Gst OK')"; then
  echo "ERROR: bundled NIM python cannot import GStreamer (Gst namespace)" >&2
  echo "  GI_TYPELIB_PATH=${GI_TYPELIB_PATH:-}" >&2
  echo "  GST_PLUGIN_PATH=${GST_PLUGIN_PATH:-}" >&2
  exit 1
fi
echo "GStreamer OK for bundled NIM (${nim_py})"

if [[ -x "${verify_decode}" ]]; then
  bash "${verify_decode}" "${bundle_root}"
elif [[ -f "${verify_decode}" ]]; then
  bash "${verify_decode}" "${bundle_root}"
else
  echo "WARNING: verify-nim-video-decode.sh missing — skipping decode check" >&2
fi
