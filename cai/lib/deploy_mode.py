"""Inference deployment mode: bundled NVIDIA NIM vs serverless NVCF."""

from __future__ import annotations

import json
import os
from enum import Enum
from pathlib import Path

from cai.lib.paths import NIM_ENDPOINTS_JSON, PROJECT_ROOT

DEFAULT_SVD_NVCF_FUNCTION_ID = "847b6e53-0133-452d-ab85-d7acf3ace723"


class NIMDeployMode(str, Enum):
    BUNDLED = "BUNDLED"
    SERVERLESS = "SERVERLESS"


def normalize_nim_deploy_mode(raw: str | None = None) -> NIMDeployMode:
    if raw is None:
        raw = os.environ.get("NIM_DEPLOY_MODE", "").strip()
    if not raw:
        return NIMDeployMode.BUNDLED

    token = raw.strip().upper().replace("-", "_").replace(" ", "_")
    aliases = {
        "BUNDLED": NIMDeployMode.BUNDLED,
        "BUNDLE": NIMDeployMode.BUNDLED,
        "GPU": NIMDeployMode.BUNDLED,
        "NIM": NIMDeployMode.BUNDLED,
        "SERVERLESS": NIMDeployMode.SERVERLESS,
        "NVCF": NIMDeployMode.SERVERLESS,
        "CLOUD": NIMDeployMode.SERVERLESS,
    }
    if token in aliases:
        return aliases[token]
    raise ValueError(
        f"Invalid NIM_DEPLOY_MODE={raw!r}. Use BUNDLED (local NIM GPU app) "
        "or SERVERLESS (NVIDIA Cloud Functions API)."
    )


def get_nim_deploy_mode() -> NIMDeployMode:
    return normalize_nim_deploy_mode()


def is_bundled_nim_mode() -> bool:
    return get_nim_deploy_mode() == NIMDeployMode.BUNDLED


def is_serverless_nim_mode() -> bool:
    return get_nim_deploy_mode() == NIMDeployMode.SERVERLESS


def deploy_mode_label() -> str:
    if is_serverless_nim_mode():
        return "serverless NVIDIA Cloud Functions gRPC API"
    return "bundled Synthetic Video Detector NVIDIA NIM GPU application"


def skip_message(step_name: str) -> str:
    return f"Skipping '{step_name}' — NIM_DEPLOY_MODE={get_nim_deploy_mode().value}."


def write_serverless_endpoints_json(path: Path | None = None) -> Path:
    target = path or NIM_ENDPOINTS_JSON
    host = os.environ.get("NVIDIA_SERVERLESS_GRPC_HOST", "grpc.nvcf.nvidia.com")
    port = int(os.environ.get("NVIDIA_SERVERLESS_GRPC_PORT", "443"))
    payload = {
        "deploy_mode": NIMDeployMode.SERVERLESS.value,
        "svd": {
            "source": "nvcf",
            "host": host,
            "grpc_port": port,
            "grpc_address": f"{host}:{port}",
            "function_id": os.environ.get("SVD_NVIDIA_FUNCTION_ID", DEFAULT_SVD_NVCF_FUNCTION_ID),
        },
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, indent=2) + "\n")
    return target
