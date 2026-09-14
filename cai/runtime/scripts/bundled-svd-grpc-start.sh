#!/usr/bin/env bash
# Bundled CAI gRPC startup — bind localhost only (matches CDSW_APP_PORT / detect client).
set -e

if [[ -f /usr/local/bin/nim-gstreamer-env.sh ]]; then
  # shellcheck disable=SC1091
  source /usr/local/bin/nim-gstreamer-env.sh
elif [[ -f "${CDSW_PROJECT_DIR:-}/cai/runtime/scripts/nim-gstreamer-env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${CDSW_PROJECT_DIR}/cai/runtime/scripts/nim-gstreamer-env.sh"
fi

# syntheticvideodetector_service.py may start auxiliary HTTP; nimlib already owns :8000.
export NIM_HTTP_API_HOST="${NIM_HTTP_API_HOST:-127.0.0.1}"
export NIM_HTTP_API_PORT="${SVD_GRPC_AUX_HTTP_PORT:-18080}"

echo "=== Synthetic Video Detector gRPC Service Startup (bundled) ==="

# Stock start_service.sh re-runs full inference (HTTP 0.0.0.0:8000) after nimlib already
# bound :8000 — address in use. This shim starts gRPC on loopback only.
GRPC_SERVICE_URI="${GRPC_SERVICE_URI:-127.0.0.1:${NIM_GRPC_API_PORT:-8001}}"
GRPC_MAX_CONCURRENCY="${GRPC_MAX_CONCURRENCY:-1}"
GRPC_MESSAGE_SIZE="${GRPC_MESSAGE_SIZE:-67108864}"

echo "=== TRT ENGINE VERIFICATION ==="
echo "Checking for TensorRT engines..."

export GRPC_SERVICE_URI GRPC_MAX_CONCURRENCY GRPC_MESSAGE_SIZE

echo "=== SERVICE STARTUP ==="
echo "Inference Type: TensorRT GPU"
echo "Service URI: ${GRPC_SERVICE_URI}"
echo "Aux HTTP (if any): ${NIM_HTTP_API_HOST}:${NIM_HTTP_API_PORT}"
echo "Message Size: ${GRPC_MESSAGE_SIZE}"
echo "Max Concurrency: ${GRPC_MAX_CONCURRENCY}"
echo "================================="

cd /opt/synthetic-detector/src/grpc

exec python3 syntheticvideodetector_service.py \
  --service-uri "${GRPC_SERVICE_URI}" \
  --max-concurrency "${GRPC_MAX_CONCURRENCY}" \
  --message-size "${GRPC_MESSAGE_SIZE}" \
  ${GRPC_SERVICE_EXTRA_CMD_ARGS:-}
