#!/usr/bin/env bash
# Generate Python gRPC stubs for Synthetic Video Detector.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
proto_root="${root}/protos"
out="${root}/src/svd/generated"
mkdir -p "${out}"

python3 -m grpc_tools.protoc \
  -I"${proto_root}" \
  --python_out="${out}" \
  --grpc_python_out="${out}" \
  --pyi_out="${out}" \
  "${proto_root}/nvidia/maxine/syntheticvideodetector/v1/syntheticvideodetector.proto"

# Fix relative imports in generated grpc module.
grpc_file="${out}/nvidia/maxine/syntheticvideodetector/v1/syntheticvideodetector_pb2_grpc.py"
if [[ -f "${grpc_file}" ]]; then
  sed -i.bak 's/import syntheticvideodetector_pb2/from nvidia.maxine.syntheticvideodetector.v1 import syntheticvideodetector_pb2/' "${grpc_file}" 2>/dev/null || \
  sed -i '' 's/import syntheticvideodetector_pb2/from nvidia.maxine.syntheticvideodetector.v1 import syntheticvideodetector_pb2/' "${grpc_file}"
  rm -f "${grpc_file}.bak"
fi

touch "${out}/__init__.py"
find "${out}/nvidia" -type d -exec touch {}/__init__.py \;

echo "Generated protos under ${out}"
