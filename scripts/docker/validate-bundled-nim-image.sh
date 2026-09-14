#!/usr/bin/env bash
# Pre-deploy smoke checks for SyntheticVideoDetector runtime image.
# Run on any amd64 host with Docker (GPU / nvidia-container-toolkit not required).
# Matches what CAI bundled NIM needs before gRPC starts: Gst GI + media_utils import.
set -euo pipefail

IMAGE="${1:?docker image ref, e.g. kevintalbert/synthetic-video-detector:1.7-turing}"

echo "=== validate-bundled-nim-image: ${IMAGE} ==="

gpu_args=()
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  gpu_args=(--gpus all)
fi

docker run --rm "${gpu_args[@]}" --platform linux/amd64 -e SVD_VERIFY_DECODE_GPU=1 "${IMAGE}" bash -c '
set -euo pipefail
bundle="/opt/nvidia-nim/synthetic-video-detector"
py=""
for c in "${bundle}/usr/local/bin/python3.12" "${bundle}/usr/bin/python3.12"; do
  [[ -x "${c}" ]] && py="${c}" && break
done
[[ -n "${py}" ]] || { echo "FAIL: NIM python missing"; exit 1; }

source /usr/local/bin/nim-gstreamer-env.sh

echo "--- check 1: Gst namespace ---"
"${py}" -c "
import gi
gi.require_version(\"Gst\", \"1.0\")
from gi.repository import Gst
Gst.init(None)
print(\"Gst OK\")
"

echo "--- check 2: media_utils VideoReader import ---"
site="${bundle}/usr/local/lib/python3.12/dist-packages"
export PYTHONPATH="${bundle}/opt/tritonserver/backends/dali/wheel/dali:${bundle}/opt/nim:${site}:${bundle}/opt/maxine"
"${py}" -c "from media_utils.video_reader import VideoReader; print(\"VideoReader OK\")"

echo "--- check 3: H.264 decode (DeepStream / media_utils) ---"
bash /opt/synthetic-video-detector/scripts/docker/verify-nim-video-decode.sh "${bundle}"

echo "--- check 4: gRPC start shim ---"
grep -q "127.0.0.1" /opt/synthetic-detector/src/grpc/start_service.sh
grpc_shim="/usr/local/bin/bundled-svd-grpc-start"
[[ -x "${grpc_shim}" ]] || { echo "FAIL: missing ${grpc_shim}"; exit 1; }
grep -qE "SVD_GRPC_AUX_HTTP_PORT|18080" "${grpc_shim}"

echo "=== ALL CHECKS PASSED (in-container) ==="
'

echo "--- check 5: runtime image labels ---"
docker inspect --format '{{index .Config.Labels "com.cloudera.ml.runtime.full-version"}}' "${IMAGE}" | grep -q '^1\.7\.'

echo "validate-bundled-nim-image: success"
