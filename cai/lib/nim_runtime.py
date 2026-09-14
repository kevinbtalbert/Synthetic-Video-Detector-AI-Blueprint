"""Run NVIDIA Synthetic Video Detector NIM bundled in the runtime image."""

from __future__ import annotations

import json
import os
import shlex
import socket
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path
from typing import Any

from cai.lib.cai_common import merge_nim_endpoints

PROJECT_ROOT = Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))
NIM_BUNDLE_ROOT = Path(os.environ.get("NIM_BUNDLE_ROOT", "/opt/nvidia-nim"))
RUN_BUNDLED_NIM_IMAGE = Path("/usr/local/bin/run-bundled-nim")

SVD_NIM_ENV_KEYS = (
    "NGC_API_KEY",
    "NIM_HTTP_API_HOST",
    "NIM_HTTP_API_PORT",
    "NIM_GRPC_API_PORT",
    "GRPC_SERVICE_URI",
    "NIM_MANIFEST_PROFILE",
    "NIM_MODEL_PROFILE",
    "NIM_MAX_CONCURRENCY_PER_GPU",
    "NIM_CACHE_PATH",
    "NIM_CACHE_DIR",
    "FORCE_CLEAR_NIM_CACHE",
    "NVIDIA_DRIVER_CAPABILITIES",
    "NVIDIA_VISIBLE_DEVICES",
    "MAXINE_MAX_INPUT_FILE_SIZE_MB",
)

SVD_DEFAULTS = {
    "source_image": "nvcr.io/nim/nvidia/synthetic-video-detector:latest",
    "http_port": 8000,
    "grpc_port": 8001,
}


def nim_cache_dir() -> str:
    project = Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))
    override = os.environ.get("SVD_MODEL_MOUNT_PATH", "").strip()
    if override.startswith("/home/cdsw"):
        path = Path(override)
    else:
        path = project / "volumes" / "models" / "synthetic-video-detector"
    path.mkdir(parents=True, exist_ok=True)
    return str(path)


def resolve_run_bundled_nim() -> Path:
    project_script = PROJECT_ROOT / "cai" / "runtime" / "scripts" / "run-bundled-nim.sh"
    if project_script.is_file():
        return project_script
    return RUN_BUNDLED_NIM_IMAGE


def write_nim_shell_env() -> Path:
    path = PROJECT_ROOT / "cai" / "config" / "svd_nim.env"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    for key in SVD_NIM_ENV_KEYS:
        value = os.environ.get(key)
        if value is None:
            continue
        if key == "NVIDIA_VISIBLE_DEVICES" and str(value).strip().lower() in {"void", "none", ""}:
            continue
        lines.append(f"export {key}={shlex.quote(value)}")
    path.write_text("\n".join(lines) + "\n")
    return path


def pod_ip() -> str:
    return os.environ.get("CDSW_IP_ADDRESS") or socket.gethostbyname(socket.gethostname())


def nim_bundle_ready() -> bool:
    return (NIM_BUNDLE_ROOT / "synthetic-video-detector" / "entrypoint").is_file()


def tcp_port_open(host: str, port: int, *, timeout_s: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout_s):
            return True
    except OSError:
        return False


def _http_ready(url: str) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            return response.status == 200
    except Exception:  # noqa: BLE001
        return False


def _models_loaded(http_port: int) -> bool:
    url = f"http://127.0.0.1:{http_port}/v1/models"
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            if response.status != 200:
                return False
            payload = json.loads(response.read().decode("utf-8", errors="replace"))
            models = payload.get("data") or payload.get("models") or []
            return len(models) > 0
    except Exception:  # noqa: BLE001
        return False


def _nim_log_has_fatal_error() -> str | None:
    log_path = PROJECT_ROOT / "cai" / "config" / "svd_nim.log"
    if not log_path.is_file():
        return None
    try:
        tail = log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-40:]
    except OSError:
        return None
    for line in reversed(tail):
        stripped = line.strip()
        if not stripped:
            continue
        if "ERROR: failed to install wrapt" in stripped:
            return stripped
        if "ERROR: wrapt install" in stripped:
            return stripped
        if stripped.startswith("ERROR:"):
            if "0.0.0.0" in stripped and "8000" in stripped and "already in use" in stripped:
                return (
                    "NIM tried to bind 0.0.0.0:8000 while HTTP is already up — stock gRPC "
                    "startup likely ran instead of bundled-svd-grpc-start.sh (127.0.0.1). "
                    "Sync repo + redeploy, or rebuild runtime 1.6+ with baked start_service shim."
                )
            return stripped
        if "Can not combine '--user' and '--target'" in stripped:
            return "NIM bootstrap failed installing python deps (pip --user vs --target conflict)"
        if "TypeError: 'NoneType' object is not callable" in stripped:
            return (
                "NIM gRPC bootstrap failed (set NIM_DISABLE_GRPC_STARTUP=1 and ensure "
                "/opt/synthetic-detector is present). See cai/config/svd_nim.log."
            )
        if "start_service.sh" in stripped or (
            "synthetic-detector" in stripped and "No such file" in stripped
        ):
            return "NIM gRPC service script missing — rebuild SyntheticVideoDetector 1.5.1+ runtime image."
        if "service_class(logger=" in stripped or "GrpcNIMApiInterface" in stripped:
            return "NIM gRPC server failed to start — see cai/config/svd_nim.log"
    return None


def wait_for_nim_ready(http_port: int, grpc_port: int, *, timeout_s: int = 3600) -> None:
    """Wait until Triton HTTP is ready, at least one model is loaded, and gRPC is listening."""
    from cai.lib.nim_startup import mark_nim_startup_error, update_nim_startup

    deadline = time.time() + timeout_s
    http_url = f"http://127.0.0.1:{http_port}/v1/health/ready"
    last_error = ""
    poll = 0
    grpc_stall_polls = 0
    while time.time() < deadline:
        poll += 1
        log_error = _nim_log_has_fatal_error()
        if log_error:
            mark_nim_startup_error(log_error)
            raise RuntimeError(log_error)

        http_ok = _http_ready(http_url)
        models_ok = _models_loaded(http_port) if http_ok else False
        grpc_ok = tcp_port_open("127.0.0.1", grpc_port)
        checks = {
            "http_ready": http_ok,
            "grpc_ready": grpc_ok,
            "models_loaded": models_ok,
        }
        if http_ok and grpc_ok and models_ok:
            update_nim_startup(
                "ready",
                f"NIM is ready (HTTP :{http_port}, gRPC :{grpc_port})",
                ready=True,
                checks=checks,
            )
            return
        if not http_ok:
            phase = "waiting_http"
            message = f"Waiting for NIM HTTP health on :{http_port} (poll #{poll})…"
            last_error = "http health not ready"
            grpc_stall_polls = 0
        elif not grpc_ok:
            grpc_stall_polls += 1
            phase = "waiting_grpc"
            message = (
                f"HTTP ready — waiting for gRPC on :{grpc_port} (poll #{poll})… "
                "Check cai/config/svd_nim.log if this persists."
            )
            last_error = f"http ready but gRPC :{grpc_port} not listening"
            if grpc_stall_polls >= 12:
                log_error = _nim_log_has_fatal_error()
                if log_error:
                    mark_nim_startup_error(log_error)
                    raise RuntimeError(log_error)
        else:
            phase = "loading_models"
            message = f"Waiting for models to load (poll #{poll}; first run can take 15–30+ min)…"
            last_error = "models not loaded yet"
            grpc_stall_polls = 0
        update_nim_startup(phase, message, checks=checks)
        time.sleep(10)
    err = f"NIM readiness failed ({http_url}, gRPC :{grpc_port}): {last_error}"
    mark_nim_startup_error(err)
    raise TimeoutError(err)


def publish_nim_endpoint(*, grpc_port: int, http_port: int) -> dict[str, Any]:
    host = pod_ip()
    entry = {
        "host": host,
        "grpc_port": grpc_port,
        "http_port": http_port,
        "grpc_address": f"{host}:{grpc_port}",
        "http_url": f"http://{host}:{http_port}",
        "nim_type": "synthetic-video-detector",
    }
    return merge_nim_endpoints({"svd": entry, "svd-nim": entry})


# Profile IDs from /opt/nim/etc/default/model_manifest.yaml (SVD NIM 1.0.0).
_PROFILE_ID_BY_GPU_CC: dict[str, str] = {
    "7.5": "ae4879839cd92b9ca86791d2455b3ce72261f485f00a89e2056e11c3e69d4bc3",
    "8.6": "15d466e43b11fa523e0662603f09bce6e5c7fc92fba33ea5c6122b98ec546bd8",
    "8.9": "6abf19cf36a0d5498b77c466780ac80c8224e641457f4f33a7df694810e2d746",
    "12.0": "3ce493f31eb1718ca928ae45a6995fc585f7571065106db509e7fce4b6f6d3aa",
}


def _gpu_compute_cap() -> str:
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=compute_cap", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        if out.stdout:
            return out.stdout.strip().splitlines()[0].strip()
    except Exception:  # noqa: BLE001
        pass
    return ""


def _default_nim_model_profile() -> str:
    cap = _gpu_compute_cap()
    if cap in _PROFILE_ID_BY_GPU_CC:
        return _PROFILE_ID_BY_GPU_CC[cap]
    if cap.startswith("8.9"):
        return _PROFILE_ID_BY_GPU_CC["8.9"]
    if cap.startswith("8.6") or cap.startswith("8."):
        return _PROFILE_ID_BY_GPU_CC["8.6"]
    return _PROFILE_ID_BY_GPU_CC["7.5"]


def _resolve_nim_profile() -> str:
    for key in ("NIM_MODEL_PROFILE", "NIM_MANIFEST_PROFILE"):
        value = (os.environ.get(key) or "").strip()
        if value and len(value) >= 32:
            return value
    return _default_nim_model_profile()


def configure_svd_env() -> dict[str, Any]:
    os.environ.setdefault("NIM_HTTP_API_HOST", "127.0.0.1")
    os.environ.setdefault("NIM_HTTP_API_PORT", str(SVD_DEFAULTS["http_port"]))
    os.environ.setdefault("NIM_GRPC_API_PORT", str(SVD_DEFAULTS["grpc_port"]))
    os.environ.setdefault(
        "GRPC_SERVICE_URI",
        f"127.0.0.1:{os.environ['NIM_GRPC_API_PORT']}",
    )
    os.environ.setdefault("NIM_DISABLE_GRPC_STARTUP", "1")
    os.environ.setdefault("NVIDIA_DRIVER_CAPABILITIES", "all")
    os.environ.setdefault("MAXINE_MAX_INPUT_FILE_SIZE_MB", "500")
    profile = _resolve_nim_profile()
    os.environ["NIM_MODEL_PROFILE"] = profile
    # Legacy alias — keep unset when using hashed profile IDs (svd_sm_* breaks nimlib 0.17+).
    os.environ.pop("NIM_MANIFEST_PROFILE", None)
    cache = nim_cache_dir()
    os.environ["NIM_CACHE_PATH"] = cache
    os.environ["NIM_CACHE_DIR"] = cache
    write_nim_shell_env()
    return {
        "source_image": SVD_DEFAULTS["source_image"],
        "http_port": int(os.environ["NIM_HTTP_API_PORT"]),
        "grpc_port": int(os.environ["NIM_GRPC_API_PORT"]),
        "cache_dir": cache,
    }


def run_nim_server() -> int:
    if not nim_bundle_ready():
        print(
            f"ERROR: bundled SVD NIM not found under {NIM_BUNDLE_ROOT}/synthetic-video-detector",
            file=sys.stderr,
        )
        return 1
    config = configure_svd_env()
    launcher = resolve_run_bundled_nim()
    print(f"Starting bundled SVD NIM via {launcher}", flush=True)
    return subprocess.call([str(launcher), "synthetic-video-detector"])
