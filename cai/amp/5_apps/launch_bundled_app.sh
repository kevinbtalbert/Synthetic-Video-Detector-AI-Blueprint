#!/usr/bin/env bash
# All-in-one bundled app: NIM + endpoint sidecar + Next.js UI in one GPU pod.
set -euo pipefail

project="${CDSW_PROJECT_DIR:-/home/cdsw}"
cd "${project}"

log="${project}/cai/config/svd_bundled_app.log"
mkdir -p "${project}/cai/config"
exec > >(tee -a "${log}") 2>&1
echo "=== SVD Bundled App $(date -Iseconds) ==="
echo "[startup] Pod hostname: $(hostname)"
echo "[startup] CDSW_APP_PORT=${CDSW_APP_PORT:-unset}"
echo "[startup] SVD_APP_ROLE=${SVD_APP_ROLE:-unset}"

python3 - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_startup import reset_nim_startup, update_nim_startup

reset_nim_startup(message="Bundled app startup sequence initiated")
update_nim_startup("starting", "Initializing bundled runtime application")
PY

if ! nvidia-smi -L >/dev/null 2>&1; then
  python3 - <<'PY'
import sys
from pathlib import Path
import os
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_startup import mark_nim_startup_error
mark_nim_startup_error("GPU not visible (nvidia-smi failed)")
PY
  echo "ERROR: GPU not visible (nvidia-smi failed)." >&2
  exit 1
fi
echo "[startup] GPU check passed:"
nvidia-smi -L || true

python3 - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_startup import update_nim_startup
update_nim_startup("gpu_check", "GPU visible", checks={"gpu_visible": True})
PY

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
from cai.lib.nim_startup import update_nim_startup

config = AppConfig.from_environ(mode=NIMDeployMode.BUNDLED)
config.apply_to_environ()
if not config.ngc_api_key.strip():
    from cai.lib.nim_startup import mark_nim_startup_error
    mark_nim_startup_error("NGC_API_KEY missing — redeploy from Launchpad with bundled configuration")
    raise SystemExit("ERROR: NGC_API_KEY missing — redeploy from Launchpad with bundled configuration")
cfg = configure_svd_env()
print(f"[startup] Bundled NIM gRPC :{cfg['grpc_port']} HTTP :{cfg['http_port']}", flush=True)
print(f"[startup] Model cache: {cfg['cache_dir']}", flush=True)
print(f"[startup] NIM_MODEL_PROFILE={os.environ.get('NIM_MODEL_PROFILE', 'unset')}", flush=True)
update_nim_startup(
    "config_ready",
    f"Configuration applied (HTTP :{cfg['http_port']}, gRPC :{cfg['grpc_port']})",
    checks={"config_applied": True},
)
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
from cai.lib.nim_startup import update_nim_startup

grpc_port = int(os.environ.get("NIM_GRPC_API_PORT", "8001"))
wire_bundled_runtime_endpoints(grpc_port=grpc_port)
print(f"[startup] Wired runtime endpoints to 127.0.0.1:{grpc_port}", flush=True)
update_nim_startup(
    "endpoints_wired",
    f"Runtime endpoints wired to 127.0.0.1:{grpc_port}",
    checks={"endpoints_wired": True},
)
PY

sidecar_log="${project}/cai/config/svd_sidecar.log"
echo "[startup] Launching NIM endpoint sidecar (logs: ${sidecar_log})"
nohup python3 "${project}/cai/amp/4_services/run_nim_sidecar.py" \
  --grpc-port "${NIM_GRPC_API_PORT}" \
  --http-port "${NIM_HTTP_API_PORT}" \
  --no-app-port \
  >>"${sidecar_log}" 2>&1 &
echo "[startup] Sidecar pid $!"

python3 - <<'PY'
import sys
from pathlib import Path
import os
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_startup import update_nim_startup
update_nim_startup("sidecar_started", "NIM endpoint sidecar started", checks={"sidecar_started": True})
PY

launcher="${project}/cai/runtime/scripts/run-bundled-nim.sh"
if [[ -f "${launcher}" ]]; then
  chmod u=rwx,go=rx "${launcher}" 2>/dev/null || true
fi
if [[ ! -x "${launcher}" ]]; then
  launcher="/usr/local/bin/run-bundled-nim"
fi
if [[ ! -x "${launcher}" ]]; then
  python3 - <<'PY'
import sys
from pathlib import Path
import os
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_startup import mark_nim_startup_error
mark_nim_startup_error("run-bundled-nim launcher not found")
PY
  echo "ERROR: run-bundled-nim launcher not found" >&2
  exit 1
fi

nim_log="${project}/cai/config/svd_nim.log"
echo "[startup] Launching bundled NIM via ${launcher} (logs: ${nim_log})"
(
  unset PYTHONPATH
  exec "${launcher}" synthetic-video-detector
) >>"${nim_log}" 2>&1 &
echo "[startup] NIM process pid $!"

python3 - <<'PY'
import sys
from pathlib import Path
import os
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_startup import update_nim_startup
update_nim_startup(
    "nim_process_started",
    "Bundled NIM process started — waiting for health checks",
    checks={"nim_process_started": True},
)
PY

nohup python3 - <<'PY' >>"${project}/cai/config/svd_bundled_wire.log" 2>&1 &
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))
from cai.lib.nim_runtime import wait_for_nim_ready, publish_nim_endpoint
from cai.lib.runtime_app import wire_bundled_runtime_endpoints
from cai.lib.nim_startup import update_nim_startup

http_port = int(os.environ.get("NIM_HTTP_API_PORT", "8000"))
grpc_port = int(os.environ.get("NIM_GRPC_API_PORT", "8001"))
print(f"[watcher] Waiting for NIM (HTTP :{http_port}, gRPC :{grpc_port})", flush=True)
try:
    wait_for_nim_ready(http_port, grpc_port, timeout_s=3600)
    publish_nim_endpoint(grpc_port=grpc_port, http_port=http_port)
    wire_bundled_runtime_endpoints(grpc_port=grpc_port)
    update_nim_startup(
        "endpoints_published",
        "NIM endpoints published and runtime wired",
        ready=True,
        checks={"endpoints_published": True},
    )
    print("[watcher] Bundled runtime endpoints wired — NIM ready for detection", flush=True)
except Exception as exc:
    from cai.lib.nim_startup import mark_nim_startup_error
    mark_nim_startup_error(str(exc))
    raise
PY
echo "[startup] Started background NIM readiness watcher (logs: ${project}/cai/config/svd_bundled_wire.log)"

echo "[startup] Starting detection UI on CDSW_APP_PORT=${CDSW_APP_PORT:-8080} (NIM continues loading in background)..."
exec python3 "${project}/cai/amp/5_apps/start_runtime_ui.py"
