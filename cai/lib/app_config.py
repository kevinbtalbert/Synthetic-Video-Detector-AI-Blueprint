"""Application configuration entered via the Launchpad and persisted on disk."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from cai.lib.cai_common import write_dotenv_file
from cai.lib.deploy_mode import DEFAULT_SVD_NVCF_FUNCTION_ID, NIMDeployMode, normalize_nim_deploy_mode
from cai.lib.paths import CONFIG_DIR

DEPLOYMENT_CONFIG_JSON = CONFIG_DIR / "deployment_config.json"
APP_ENVIRONMENT_ENV = CONFIG_DIR / "app_environment.env"

SECRET_KEYS: frozenset[str] = frozenset({"ngc_api_key"})

_ENV_MAP: dict[str, str] = {
    "nim_deploy_mode": "NIM_DEPLOY_MODE",
    "ngc_api_key": "NGC_API_KEY",
    "svd_nvidia_function_id": "SVD_NVIDIA_FUNCTION_ID",
    "nvidia_serverless_grpc_host": "NVIDIA_SERVERLESS_GRPC_HOST",
    "nvidia_serverless_grpc_port": "NVIDIA_SERVERLESS_GRPC_PORT",
    "svd_nim_manifest_profile": "NIM_MANIFEST_PROFILE",
    "detection_threshold": "SVD_DETECTION_THRESHOLD",
}


@dataclass
class AppConfig:
    nim_deploy_mode: str = "BUNDLED"
    ngc_api_key: str = ""
    svd_nvidia_function_id: str = DEFAULT_SVD_NVCF_FUNCTION_ID
    nvidia_serverless_grpc_host: str = "grpc.nvcf.nvidia.com"
    nvidia_serverless_grpc_port: str = "443"
    svd_nim_manifest_profile: str = ""
    detection_threshold: str = "0.30"

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AppConfig:
        mode = normalize_nim_deploy_mode(str(data.get("nim_deploy_mode", "BUNDLED"))).value
        return cls(
            nim_deploy_mode=mode,
            ngc_api_key=str(data.get("ngc_api_key", "")),
            svd_nvidia_function_id=str(
                data.get("svd_nvidia_function_id") or DEFAULT_SVD_NVCF_FUNCTION_ID
            ),
            nvidia_serverless_grpc_host=str(
                data.get("nvidia_serverless_grpc_host", "grpc.nvcf.nvidia.com")
            ),
            nvidia_serverless_grpc_port=str(data.get("nvidia_serverless_grpc_port", "443")),
            svd_nim_manifest_profile=str(data.get("svd_nim_manifest_profile", "")),
            detection_threshold=str(data.get("detection_threshold", "0.30")),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "nim_deploy_mode": self.nim_deploy_mode,
            "ngc_api_key": self.ngc_api_key,
            "svd_nvidia_function_id": self.svd_nvidia_function_id,
            "nvidia_serverless_grpc_host": self.nvidia_serverless_grpc_host,
            "nvidia_serverless_grpc_port": self.nvidia_serverless_grpc_port,
            "svd_nim_manifest_profile": self.svd_nim_manifest_profile,
            "detection_threshold": self.detection_threshold,
        }

    @classmethod
    def merge_update(cls, existing: AppConfig | None, patch: dict[str, Any]) -> AppConfig:
        merged = existing.to_dict() if existing else {}
        for key, value in patch.items():
            if key in SECRET_KEYS and not str(value or "").strip():
                continue
            merged[key] = value
        return cls.from_dict(merged)

    def secrets_set(self) -> dict[str, bool]:
        return {"ngc_api_key": bool(self.ngc_api_key)}

    def public_dict(self) -> dict[str, Any]:
        data = self.to_dict()
        for key in SECRET_KEYS:
            data.pop(key, None)
        return data

    def as_process_env(self) -> dict[str, str]:
        env: dict[str, str] = {}
        for json_key, env_key in _ENV_MAP.items():
            value = self.to_dict().get(json_key)
            if value is None or value == "":
                continue
            env[env_key] = str(value)
        return env

    def apply_to_environ(self) -> dict[str, str]:
        env = self.as_process_env()
        os.environ.update(env)
        return env

    def app_environment(self) -> dict[str, str]:
        env = self.as_process_env()
        env["TASK_TYPE"] = "START_APPLICATION"
        return env

    def validate_for_build(self) -> dict[str, Any]:
        errors: list[str] = []
        warnings: list[str] = []
        mode = normalize_nim_deploy_mode(self.nim_deploy_mode).value

        if mode not in {NIMDeployMode.BUNDLED.value, NIMDeployMode.SERVERLESS.value}:
            errors.append(f"Invalid deployment mode: {self.nim_deploy_mode}")

        if not self.ngc_api_key.strip():
            errors.append("NGC API key is required (bundled NIM entitlement and serverless NVCF auth).")

        if mode == NIMDeployMode.SERVERLESS.value and not self.svd_nvidia_function_id.strip():
            errors.append("NVCF function ID is required for serverless mode.")

        if mode == NIMDeployMode.BUNDLED.value:
            warnings.append(
                "Bundled mode starts a GPU NIM application; first startup can take 15–30+ minutes."
            )
        else:
            warnings.append(
                "Serverless mode uses the NVIDIA Cloud Functions API — evaluation use only, not production."
            )

        return {"valid": len(errors) == 0, "errors": errors, "warnings": warnings}


def validate_merged_config(patch: dict[str, Any] | None = None) -> dict[str, Any]:
    existing = load_app_config()
    config = AppConfig.merge_update(existing, patch or {}) if patch else existing
    if config is None:
        return {"valid": False, "errors": ["Save your configuration before building."], "warnings": []}
    return config.validate_for_build()


def load_app_config() -> AppConfig | None:
    if not DEPLOYMENT_CONFIG_JSON.exists():
        return None
    raw = DEPLOYMENT_CONFIG_JSON.read_text().strip()
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    return AppConfig.from_dict(data)


def deployment_config_load_error() -> str | None:
    if not DEPLOYMENT_CONFIG_JSON.exists():
        return None
    raw = DEPLOYMENT_CONFIG_JSON.read_text().strip()
    if not raw:
        return f"{DEPLOYMENT_CONFIG_JSON.name} is empty — save configuration first."
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        return f"{DEPLOYMENT_CONFIG_JSON.name} is invalid JSON ({exc.msg})."
    if not isinstance(data, dict):
        return f"{DEPLOYMENT_CONFIG_JSON.name} must be a JSON object."
    return None


def save_app_config(config: AppConfig) -> Path:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp_path = DEPLOYMENT_CONFIG_JSON.with_suffix(".json.tmp")
    tmp_path.write_text(json.dumps(config.to_dict(), indent=2) + "\n")
    tmp_path.replace(DEPLOYMENT_CONFIG_JSON)
    config.apply_to_environ()
    write_dotenv_file(APP_ENVIRONMENT_ENV, config.as_process_env())
    return DEPLOYMENT_CONFIG_JSON


def apply_persisted_config() -> AppConfig | None:
    config = load_app_config()
    if config is None:
        return None
    config.apply_to_environ()
    return config
