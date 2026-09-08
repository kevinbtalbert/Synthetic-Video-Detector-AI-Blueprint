#!/usr/bin/env bash
# CAI application launcher: configure env, start sidecar, exec bundled SVD NIM.
set -euo pipefail

project="${CDSW_PROJECT_DIR:-/home/cdsw}"
cd "${project}"

nim_log="${project}/cai/config/svd_nim.log"
mkdir -p "${project}/cai/config"
exec > >(tee -a "${nim_log}") 2>&1
echo "=== SVD NIM launcher $(date -Iseconds) ==="

if ! nvidia-smi -L >/dev/null 2>&1; then
  echo "ERROR: GPU not visible (nvidia-smi failed)." >&2
  exit 1
fi
nvidia-smi -L || true

python3 - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_runtime import configure_svd_env
config = configure_svd_env()
print(f"SVD NIM: {config['source_image']}", flush=True)
print(f"gRPC :{config['grpc_port']} HTTP :{config['http_port']}", flush=True)
print(f"Cache: {config['cache_dir']}", flush=True)
PY

source "${project}/cai/config/svd_nim.env"

if [[ -z "${NGC_API_KEY:-}" ]]; then
  echo "ERROR: NGC_API_KEY is empty" >&2
  exit 1
fi

app_port="${CDSW_APP_PORT:-8100}"
sidecar_log="${project}/cai/config/svd_sidecar.log"
nohup python3 "${project}/cai/amp/4_services/run_nim_sidecar.py" \
  --grpc-port "${NIM_GRPC_API_PORT}" \
  --http-port "${NIM_HTTP_API_PORT}" \
  --app-port "${app_port}" \
  >>"${sidecar_log}" 2>&1 &
echo "Started NIM sidecar (port ${app_port})"

launcher="/usr/local/bin/run-bundled-nim"
if [[ ! -x "${launcher}" ]]; then
  launcher="${project}/cai/runtime/scripts/run-bundled-nim.sh"
fi
exec "${launcher}" synthetic-video-detector
