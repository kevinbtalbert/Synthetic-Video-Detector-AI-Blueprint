#!/usr/bin/env bash
# All-in-one bundled app: NIM + endpoint sidecar + Next.js UI in one GPU pod.
set -euo pipefail

project="${CDSW_PROJECT_DIR:-/home/cdsw}"
cd "${project}"

log="${project}/cai/config/svd_bundled_app.log"
mkdir -p "${project}/cai/config"
exec > >(tee -a "${log}") 2>&1
echo "=== SVD Bundled App $(date -Iseconds) ==="

if ! nvidia-smi -L >/dev/null 2>&1; then
  echo "ERROR: GPU not visible (nvidia-smi failed)." >&2
  exit 1
fi
nvidia-smi -L || true

export NIM_DEPLOY_MODE=BUNDLED
export SVD_APP_ROLE=runtime
export NEXT_PUBLIC_SVD_APP_ROLE=runtime

python3 - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.app_config import AppConfig
from cai.lib.deploy_mode import NIMDeployMode
from cai.lib.nim_runtime import configure_svd_env

config = AppConfig.from_environ(mode=NIMDeployMode.BUNDLED)
config.apply_to_environ()
if not config.ngc_api_key.strip():
    raise SystemExit("ERROR: NGC_API_KEY missing — redeploy from Launchpad with bundled configuration")
cfg = configure_svd_env()
print(f"Bundled NIM gRPC :{cfg['grpc_port']} HTTP :{cfg['http_port']}", flush=True)
print(f"Cache: {cfg['cache_dir']}", flush=True)
PY

source "${project}/cai/config/svd_nim.env"

if [[ -z "${NGC_API_KEY:-}" ]]; then
  echo "ERROR: NGC_API_KEY is empty" >&2
  exit 1
fi

python3 - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.runtime_app import wire_bundled_runtime_endpoints

grpc_port = int(os.environ.get("NIM_GRPC_API_PORT", "8001"))
wire_bundled_runtime_endpoints(grpc_port=grpc_port)
print(f"Wired bundled runtime endpoints to 127.0.0.1:{grpc_port}", flush=True)
PY

sidecar_log="${project}/cai/config/svd_sidecar.log"
nohup python3 "${project}/cai/amp/4_services/run_nim_sidecar.py" \
  --grpc-port "${NIM_GRPC_API_PORT}" \
  --http-port "${NIM_HTTP_API_PORT}" \
  --no-app-port \
  >>"${sidecar_log}" 2>&1 &
echo "Started NIM endpoint sidecar"

launcher="${project}/cai/runtime/scripts/run-bundled-nim.sh"
if [[ -f "${launcher}" ]]; then
  chmod u=rwx,go=rx "${launcher}" 2>/dev/null || true
fi
if [[ ! -x "${launcher}" ]]; then
  launcher="/usr/local/bin/run-bundled-nim"
fi
if [[ ! -x "${launcher}" ]]; then
  echo "ERROR: run-bundled-nim launcher not found" >&2
  exit 1
fi

nim_log="${project}/cai/config/svd_nim.log"
(
  unset PYTHONPATH
  exec "${launcher}" synthetic-video-detector
) >>"${nim_log}" 2>&1 &
echo "Started bundled NIM in background (pid $!)"

nohup python3 - <<'PY' >>"${project}/cai/config/svd_bundled_wire.log" 2>&1 &
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_runtime import wait_for_nim_ready, publish_nim_endpoint
from cai.lib.runtime_app import wire_bundled_runtime_endpoints

http_port = int(os.environ.get("NIM_HTTP_API_PORT", "8000"))
grpc_port = int(os.environ.get("NIM_GRPC_API_PORT", "8001"))
print(f"Background: waiting for NIM (HTTP :{http_port}, gRPC :{grpc_port})", flush=True)
wait_for_nim_ready(http_port, grpc_port, timeout_s=3600)
publish_nim_endpoint(grpc_port=grpc_port, http_port=http_port)
wire_bundled_runtime_endpoints(grpc_port=grpc_port)
print("Background: bundled runtime endpoints wired", flush=True)
PY
echo "Started background NIM readiness watcher"

echo "Starting detection UI on CDSW_APP_PORT (NIM continues loading in background)..."
exec python3 "${project}/cai/amp/5_apps/start_runtime_ui.py"
