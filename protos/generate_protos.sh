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

# Normalize grpc imports for src.svd.generated.* on PYTHONPATH.
grpc_file="${out}/nvidia/maxine/syntheticvideodetector/v1/syntheticvideodetector_pb2_grpc.py"
python3 - "${grpc_file}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
long_alias = "nvidia_dot_maxine_dot_syntheticvideodetector_dot_v1_dot_syntheticvideodetector__pb2"
short_alias = "syntheticvideodetector__pb2"

# Replace grpc_tools alias everywhere in the stub body.
text = text.replace(long_alias, short_alias)

# Normalize import line to a single relative import (idempotent).
text = re.sub(
    r"^from nvidia\.maxine\.syntheticvideodetector\.v1 import syntheticvideodetector_pb2.*\n",
    f"from . import syntheticvideodetector_pb2 as {short_alias}\n",
    text,
    count=1,
    flags=re.MULTILINE,
)
text = re.sub(
    r"^import syntheticvideodetector_pb2.*\n",
    f"from . import syntheticvideodetector_pb2 as {short_alias}\n",
    text,
    count=1,
    flags=re.MULTILINE,
)
# Repair double-replacement from older broken sed runs.
text = re.sub(
    r"^from nvidia\.maxine\.syntheticvideodetector\.v1 from .*?\n",
    f"from . import syntheticvideodetector_pb2 as {short_alias}\n",
    text,
    count=1,
    flags=re.MULTILINE,
)

path.write_text(text)
PY

touch "${out}/__init__.py"
find "${out}/nvidia" -type d -exec touch {}/__init__.py \;

echo "Generated protos under ${out}"
