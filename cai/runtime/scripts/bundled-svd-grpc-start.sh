#!/usr/bin/env bash
# Bundled CAI gRPC startup — bind localhost only (matches CDSW_APP_PORT / detect client).
set -e

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
echo "Message Size: ${GRPC_MESSAGE_SIZE}"
echo "Max Concurrency: ${GRPC_MAX_CONCURRENCY}"
echo "================================="

cd /opt/synthetic-detector/src/grpc

exec python3 syntheticvideodetector_service.py \
  --service-uri "${GRPC_SERVICE_URI}" \
  --max-concurrency "${GRPC_MAX_CONCURRENCY}" \
  --message-size "${GRPC_MESSAGE_SIZE}" \
  ${GRPC_SERVICE_EXTRA_CMD_ARGS:-}
