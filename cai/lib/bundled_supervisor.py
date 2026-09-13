"""Single-process supervisor for the bundled all-in-one runtime application.

Architecture (one CAI GPU app):
  1. Configure env from CML application variables (no Launchpad config files).
  2. Start stock NIM via run-bundled-nim.sh (nvidia_entrypoint + start_server).
  3. Background thread: wait for readiness → publish endpoints → wire localhost gRPC.
  4. Foreground: Next.js UI on CDSW_APP_PORT (started by launch_bundled_app.py).

No sidecar, no duplicate watchers — same pattern as launch_serverless_app.py.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
from pathlib import Path

from cai.lib.app_config import AppConfig
from cai.lib.deploy_mode import NIMDeployMode
from cai.lib.nim_runtime import (
    configure_svd_env,
    nim_bundle_ready,
    publish_nim_endpoint,
    resolve_run_bundled_nim,
    wait_for_nim_ready,
)
from cai.lib.nim_startup import mark_nim_startup_error, reset_nim_startup, update_nim_startup
from cai.lib.paths import CONFIG_DIR
from cai.lib.runtime_app import wire_bundled_runtime_endpoints

PROJECT_ROOT = Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))
NIM_LOG = CONFIG_DIR / "svd_nim.log"
WIRE_LOG = CONFIG_DIR / "svd_bundled_wire.log"


def _log(msg: str) -> None:
    print(msg, flush=True)


def _gpu_visible() -> bool:
    try:
        subprocess.run(["nvidia-smi", "-L"], capture_output=True, check=True, timeout=15)
        return True
    except (subprocess.CalledProcessError, OSError, subprocess.TimeoutExpired):
        return False


def _start_nim_background() -> subprocess.Popen:
    launcher = resolve_run_bundled_nim()
    if not launcher.is_file():
        raise RuntimeError(f"run-bundled-nim launcher not found: {launcher}")
    NIM_LOG.parent.mkdir(parents=True, exist_ok=True)
    NIM_LOG.write_text("")
    _log(f"Starting stock NIM via {launcher} (log: {NIM_LOG})")
    log_handle = NIM_LOG.open("a")
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    proc = subprocess.Popen(
        [str(launcher), "synthetic-video-detector"],
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        env=env,
        cwd=str(PROJECT_ROOT),
    )
    return proc


def _readiness_worker(*, http_port: int, grpc_port: int) -> None:
    WIRE_LOG.parent.mkdir(parents=True, exist_ok=True)
    with WIRE_LOG.open("a") as wire_log:
        def wlog(msg: str) -> None:
            wire_log.write(msg + "\n")
            wire_log.flush()
            _log(msg)

        wlog(f"[readiness] waiting for NIM HTTP :{http_port} gRPC :{grpc_port}")
        try:
            wait_for_nim_ready(http_port, grpc_port, timeout_s=3600)
            publish_nim_endpoint(grpc_port=grpc_port, http_port=http_port)
            wire_bundled_runtime_endpoints(grpc_port=grpc_port)
            update_nim_startup(
                "endpoints_published",
                "NIM ready — endpoints published",
                ready=True,
                checks={"endpoints_published": True},
            )
            wlog("[readiness] NIM ready for detection")
        except Exception as exc:
            mark_nim_startup_error(str(exc))
            wlog(f"[readiness] failed: {exc}")


def prepare_bundled_runtime() -> dict[str, int]:
    """Validate GPU, apply CML env, wire provisional localhost endpoints. Returns port map."""
    reset_nim_startup(message="Bundled runtime starting")
    update_nim_startup("starting", "Initializing bundled runtime application")

    if not _gpu_visible():
        mark_nim_startup_error("GPU not visible (nvidia-smi failed)")
        raise RuntimeError("GPU not visible (nvidia-smi failed)")
    update_nim_startup("gpu_check", "GPU visible", checks={"gpu_visible": True})

    if not nim_bundle_ready():
        mark_nim_startup_error("Bundled NIM not found in runtime image")
        raise RuntimeError("Bundled NIM not found under /opt/nvidia-nim/synthetic-video-detector")

    config = AppConfig.from_environ(mode=NIMDeployMode.BUNDLED)
    config.apply_to_environ()
    if not config.ngc_api_key.strip():
        mark_nim_startup_error("NGC_API_KEY missing on deployed application")
        raise RuntimeError("NGC_API_KEY missing — redeploy from Launchpad with bundled configuration")

    cfg = configure_svd_env()
    http_port = int(cfg["http_port"])
    grpc_port = int(cfg["grpc_port"])
    _log(f"NIM profile={os.environ.get('NIM_MODEL_PROFILE', 'unset')} cache={cfg['cache_dir']}")

    update_nim_startup(
        "config_ready",
        f"Configuration applied (HTTP :{http_port}, gRPC :{grpc_port})",
        checks={"config_applied": True},
    )

    wire_bundled_runtime_endpoints(grpc_port=grpc_port)
    update_nim_startup(
        "endpoints_wired",
        f"Detection will use 127.0.0.1:{grpc_port}",
        checks={"endpoints_wired": True},
    )
    return {"http_port": http_port, "grpc_port": grpc_port}


def start_bundled_nim_supervisor() -> None:
    """Start NIM + readiness thread. Does not block on NIM ready (UI starts immediately)."""
    ports = prepare_bundled_runtime()
    proc = _start_nim_background()
    update_nim_startup(
        "nim_process_started",
        f"Stock NIM started (pid {proc.pid})",
        checks={"nim_process_started": True},
    )

    thread = threading.Thread(
        target=_readiness_worker,
        kwargs={"http_port": ports["http_port"], "grpc_port": ports["grpc_port"]},
        daemon=True,
        name="svd-nim-readiness",
    )
    thread.start()
    _log(f"Readiness thread started (log: {WIRE_LOG})")
