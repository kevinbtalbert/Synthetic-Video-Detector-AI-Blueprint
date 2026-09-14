#!/usr/bin/env bash
# Verify bundled NIM can decode H.264 (DeepStream nvv4l2 path used by media_utils).
set -euo pipefail

bundle_root="${1:-/opt/nvidia-nim/synthetic-video-detector}"
require_gpu="${SVD_VERIFY_DECODE_GPU:-auto}"

nim_py=""
for candidate in \
  "${bundle_root}/usr/local/bin/python3.12" \
  "${bundle_root}/usr/bin/python3.12"; do
  if [[ -x "${candidate}" ]]; then
    nim_py="${candidate}"
    break
  fi
done
[[ -n "${nim_py}" ]] || { echo "ERROR: NIM python not found under ${bundle_root}" >&2; exit 1; }

# shellcheck disable=SC1091
source /usr/local/bin/nim-gstreamer-env.sh
export NIM_BUNDLE_ROOT="$(dirname "${bundle_root}")"

ds_lib="${bundle_root}/opt/nvidia/deepstream/deepstream/lib"
nv_plugin="${bundle_root}/usr/lib/x86_64-linux-gnu/gstreamer-1.0/deepstream/libgstnvvideo4linux2.so"

echo "Checking DeepStream decode prerequisites ..."
[[ -f "${ds_lib}/libnvbufsurface.so" ]] || { echo "ERROR: missing ${ds_lib}/libnvbufsurface.so" >&2; exit 1; }
[[ -f "${nv_plugin}" ]] || { echo "ERROR: missing ${nv_plugin}" >&2; exit 1; }
if ! ldd "${nv_plugin}" 2>/dev/null | grep -q 'libnvbufsurface.so'; then
  echo "ERROR: nvv4l2 GStreamer plugin does not link libnvbufsurface" >&2
  exit 1
fi

clip="${SVD_DECODE_TEST_CLIP:-/opt/synthetic-video-detector/.svd-gst-decode-test.mp4}"
mkdir -p "$(dirname "${clip}")"
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i testsrc=duration=0.5:size=320x240:rate=10 \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart "${clip}"

want_gpu=0
case "${require_gpu}" in
  1|true|yes) want_gpu=1 ;;
  auto)
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
      want_gpu=1
    fi
    ;;
esac

if (( want_gpu == 0 )); then
  echo "SKIP GPU VideoReader frame test (no GPU in this environment)"
  echo "DeepStream decode prerequisites OK (${nim_py})"
  exit 0
fi

if ! gst-inspect-1.0 nvv4l2decoder >/dev/null 2>&1; then
  echo "ERROR: nvv4l2decoder GStreamer element not available (need GPU + libcuda)" >&2
  exit 1
fi

site="${bundle_root}/usr/local/lib/python3.12/dist-packages"
export PYTHONPATH="${bundle_root}/opt/tritonserver/backends/dali/wheel/dali:${bundle_root}/opt/nim:${site}:${bundle_root}/opt/maxine:${bundle_root}/.nim_py_vendor"

echo "Checking media_utils VideoReader (nvv4l2) frame read ..."
if ! timeout 120 "${nim_py}" <<PY
from media_utils.video_reader import VideoReader, VideoReaderConfig, Backend

clip = "${clip}"
reader = VideoReader(Backend.GST)
cfg = VideoReaderConfig()
reader.open(cfg, file_uri=clip)
frame = reader.next_video_frame()
if frame is None:
    raise SystemExit("no frame")
reader.close()
print("VideoReader decode OK")
PY
then
  echo "ERROR: VideoReader nvv4l2 decode failed" >&2
  exit 1
fi

echo "NIM video decode verification passed (${nim_py})"
