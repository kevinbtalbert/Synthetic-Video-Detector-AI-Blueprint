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
    "NIM_HTTP_API_PORT",
    "NIM_GRPC_API_PORT",
    "NIM_MANIFEST_PROFILE",
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


def wait_for_nim_ready(http_port: int, grpc_port: int, *, timeout_s: int = 900) -> None:
    deadline = time.time() + timeout_s
    http_url = f"http://127.0.0.1:{http_port}/v1/health/ready"
    last_error = ""
    while time.time() < deadline:
        http_ok = False
        try:
            with urllib.request.urlopen(http_url, timeout=10) as response:
                http_ok = response.status == 200
        except Exception as exc:  # noqa: BLE001
            last_error = f"http: {exc}"
        grpc_ok = tcp_port_open("127.0.0.1", grpc_port)
        if http_ok and grpc_ok:
            return
        if http_ok:
            last_error = f"http ready but gRPC :{grpc_port} not listening"
        time.sleep(5)
    raise TimeoutError(f"NIM readiness failed ({http_url}, gRPC :{grpc_port}): {last_error}")


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


def configure_svd_env() -> dict[str, Any]:
    os.environ.setdefault("NIM_HTTP_API_PORT", str(SVD_DEFAULTS["http_port"]))
    os.environ.setdefault("NIM_GRPC_API_PORT", str(SVD_DEFAULTS["grpc_port"]))
    os.environ.setdefault("NVIDIA_DRIVER_CAPABILITIES", "all")
    os.environ.setdefault("MAXINE_MAX_INPUT_FILE_SIZE_MB", "500")
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
