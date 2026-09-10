"""Build and manage the Synthetic Video Detector pipeline from the Launchpad."""

from __future__ import annotations

import json
import time
from collections.abc import Callable
from typing import Any

from cai.lib.app_config import AppConfig, load_app_config, save_app_config, validate_merged_config
from cai.lib.build_progress import (
    BUILD_PROGRESS_JSON,
    finish_build_progress,
    is_build_in_progress,
    read_build_progress,
    reconcile_stale_build,
    set_step,
    start_build_progress,
)
from cai.lib.cai_common import write_dotenv_file
from cai.lib.cml_client import ApplicationInfo, CMLClient
from cai.lib.deploy_mode import (
    NIMDeployMode,
    is_bundled_nim_mode,
    is_serverless_nim_mode,
    normalize_nim_deploy_mode,
    write_serverless_endpoints_json,
)
from cai.lib.paths import CONFIG_DIR, ENDPOINTS_ENV, NIM_ENDPOINTS_JSON, PROJECT_ROOT, ensure_cai_dirs

SERVICE_SPECS: dict[str, dict[str, Any]] = {
    "svd": {
        "name": "Synthetic Video Detector NIM",
        "subdomain": "svd-nim",
        "script": "cai/amp/4_services/launch_svd_nim.py",
        "cpu": 4,
        "memory": 32,
        "gpu": 1,
        "deploy_modes": {NIMDeployMode.BUNDLED.value},
    },
}


def build_plan(config: AppConfig) -> list[dict[str, str]]:
    steps = [
        {"id": "validate", "label": "Validate configuration"},
        {"id": "save", "label": "Save configuration"},
        {"id": "cleanup", "label": "Remove applications from the previous deploy mode"},
    ]
    if config.nim_deploy_mode == NIMDeployMode.BUNDLED.value:
        steps.append({"id": "svd", "label": "Start Synthetic Video Detector NIM (GPU)"})
    steps.extend(
        [
            {"id": "wire", "label": "Connect detection endpoint (write runtime endpoints)"},
            {"id": "ready", "label": "Wait until the pipeline is ready to use"},
        ]
    )
    return steps


def mode_summary(config: AppConfig | None) -> dict[str, str]:
    if config is None:
        return {
            "headline": "Configure your pipeline, then build it from this page.",
            "detail": "Nothing is deployed until you click Build pipeline.",
        }
    if config.nim_deploy_mode == NIMDeployMode.SERVERLESS.value:
        return {
            "headline": "Serverless: inference uses the NVIDIA Cloud Functions gRPC API.",
            "detail": "No local GPU NIM is started. Your NGC API key is used for NVCF authentication.",
        }
    return {
        "headline": "Bundled: Synthetic Video Detector runs as a NVIDIA NIM GPU application.",
        "detail": "Build creates one GPU application. First startup can take 15–30+ minutes.",
    }


RUNNING_APP_STATUSES = frozenset({"RUNNING", "APPLICATION_RUNNING"})
FAILED_APP_STATUSES = frozenset(
    {"APPLICATION_FAILED", "FAILED", "STOPPED", "APPLICATION_STOPPED", "ERROR", "APPLICATION_ERROR"}
)


def _normalize_app_status(status: str | None) -> str:
    return (status or "").upper()


def _is_app_running(status: str | None) -> bool:
    return _normalize_app_status(status) in RUNNING_APP_STATUSES


def _is_app_failed(status: str | None) -> bool:
    normalized = _normalize_app_status(status)
    return normalized in FAILED_APP_STATUSES or "FAIL" in normalized


def _required_service_keys(config: AppConfig | None) -> list[str]:
    if config is None or config.nim_deploy_mode == NIMDeployMode.SERVERLESS.value:
        return []
    return ["svd"]


def _find_app(apps: list[ApplicationInfo], name: str) -> ApplicationInfo | None:
    for app in apps:
        if app.name == name:
            return app
    return None


def _wait_for_app_removed(client: CMLClient, name: str, *, timeout_s: int = 180) -> None:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if _find_app(client.list_applications(), name) is None:
            return
        time.sleep(3)
    raise TimeoutError(f"Timed out waiting for application {name!r} to be deleted")


def _clear_runtime_endpoint_artifacts() -> None:
    for path in (ENDPOINTS_ENV, NIM_ENDPOINTS_JSON):
        path.unlink(missing_ok=True)


def _ensure_application(
    client: CMLClient,
    spec_key: str,
    config: AppConfig,
    apps: list[ApplicationInfo],
    *,
    recreate: bool = True,
) -> dict[str, Any]:
    spec = SERVICE_SPECS[spec_key]
    existing = _find_app(apps, spec["name"])
    env = config.app_environment()
    if int(spec.get("gpu", 0)) > 0:
        env.setdefault("NVIDIA_DRIVER_CAPABILITIES", "all")

    if existing and recreate:
        client.delete_application(existing.id)
        _wait_for_app_removed(client, spec["name"])
        apps = client.list_applications()
        existing = None

    if existing and _is_app_running(existing.status):
        return {"key": spec_key, "name": spec["name"], "application": existing.metadata, "created": False}

    created = client.create_application(
        name=spec["name"],
        script=spec["script"],
        subdomain=spec["subdomain"],
        cpu=int(spec["cpu"]),
        memory=int(spec["memory"]),
        gpu=int(spec.get("gpu", 0)),
        environment=env,
    )
    return {"key": spec_key, "name": spec["name"], "application": created.metadata, "created": True}


def _wait_for_nim_endpoints(timeout_s: int = 1200) -> dict[str, Any]:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if NIM_ENDPOINTS_JSON.exists():
            data = json.loads(NIM_ENDPOINTS_JSON.read_text())
            svd = data.get("svd") or data.get("svd-nim")
            if svd and svd.get("grpc_address"):
                return data
        time.sleep(10)
    raise TimeoutError(f"Timed out waiting for SVD endpoint in {NIM_ENDPOINTS_JSON}")


def _wire_endpoints(config: AppConfig) -> dict[str, str]:
    if is_serverless_nim_mode():
        write_serverless_endpoints_json()
        host = config.nvidia_serverless_grpc_host
        port = config.nvidia_serverless_grpc_port
        endpoints = {
            "SVD_SERVER": f"{host}:{port}",
            "NIM_DEPLOY_MODE": NIMDeployMode.SERVERLESS.value,
            "SVD_SSL_MODE": "TLS",
        }
    else:
        nim_data = _wait_for_nim_endpoints()
        svd = nim_data.get("svd") or nim_data.get("svd-nim", {})
        endpoints = {
            "SVD_SERVER": svd.get("grpc_address", f"{svd.get('host')}:{svd.get('grpc_port')}"),
            "NIM_DEPLOY_MODE": NIMDeployMode.BUNDLED.value,
            "SVD_SSL_MODE": "DISABLED",
        }
    write_dotenv_file(ENDPOINTS_ENV, endpoints)
    return endpoints


def _wait_for_service_running(service_key: str, *, timeout_s: int = 900) -> None:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        status = list_deployment_status()
        svc = status.get("services", {}).get(service_key, {})
        app = svc.get("application") or {}
        app_status = app.get("status", "not started")
        if _is_app_failed(app_status):
            raise RuntimeError(f"{svc.get('name', service_key)} failed ({app_status})")
        if _is_app_running(app_status):
            return
        time.sleep(10)
    raise TimeoutError(f"Timed out waiting for {service_key} to reach RUNNING")


def build_pipeline(config: AppConfig) -> dict[str, Any]:
    ensure_cai_dirs()
    client = CMLClient()
    client.configure_project_resources(shared_memory_limit_mb=8192)
    steps = build_plan(config)
    start_build_progress(config.nim_deploy_mode, steps)
    try:
        set_step("validate", "running", message="Validating configuration")
        validation = config.validate_for_build()
        if not validation["valid"]:
            raise RuntimeError("; ".join(validation["errors"]))
        set_step("validate", "done")

        set_step("save", "running", message="Saving configuration")
        save_app_config(config)
        set_step("save", "done")

        set_step("cleanup", "running", message="Cleaning up previous deployment")
        _clear_runtime_endpoint_artifacts()
        if is_bundled_nim_mode():
            for key, spec in SERVICE_SPECS.items():
                existing = _find_app(client.list_applications(), spec["name"])
                if existing:
                    client.delete_application(existing.id)
                    _wait_for_app_removed(client, spec["name"])
        set_step("cleanup", "done")

        if is_bundled_nim_mode():
            set_step("svd", "running", message="Starting SVD NIM GPU application")
            apps = client.list_applications()
            _ensure_application(client, "svd", config, apps)
            _wait_for_service_running("svd")
            set_step("svd", "done")

        set_step("wire", "running", message="Writing runtime endpoints")
        endpoints = _wire_endpoints(config)
        set_step("wire", "done")

        set_step("ready", "running", message="Pipeline ready")
        set_step("ready", "done")
        finish_build_progress(True, "Pipeline is ready.")
        return {"success": True, "endpoints": endpoints}
    except Exception as exc:
        finish_build_progress(False, str(exc))
        raise


def list_deployment_status() -> dict[str, Any]:
    ensure_cai_dirs()
    config = load_app_config()
    services: dict[str, Any] = {}
    try:
        client = CMLClient()
        apps = client.list_applications()
        for key, spec in SERVICE_SPECS.items():
            app = _find_app(apps, spec["name"])
            services[key] = {
                "key": key,
                "name": spec["name"],
                "application": app.metadata if app else None,
                "deploy_modes": list(spec["deploy_modes"]),
            }
    except Exception as exc:
        services["error"] = str(exc)

    config_mode = (
        normalize_nim_deploy_mode(config.nim_deploy_mode)
        if config
        else normalize_nim_deploy_mode(None)
    )
    serverless = config_mode == NIMDeployMode.SERVERLESS

    endpoints_ready = ENDPOINTS_ENV.exists() and ENDPOINTS_ENV.read_text().strip() != ""
    required = _required_service_keys(config)
    running = pending = failed = 0
    failed_services: list[dict[str, str]] = []
    for key in required:
        app = (services.get(key) or {}).get("application") or {}
        status = app.get("status", "")
        if _is_app_running(status):
            running += 1
        elif _is_app_failed(status):
            failed += 1
            failed_services.append({"name": (services.get(key) or {}).get("name", key), "status": status})
        elif app:
            pending += 1

    pipeline_ready = endpoints_ready and (
        serverless or (running == len(required) and failed == 0 and pending == 0)
    )
    build = reconcile_stale_build(
        pipeline_failed=failed > 0,
        failed_services=failed_services,
        any_deployed_apps=bool(required),
    ) or read_build_progress()
    build_in_progress = is_build_in_progress()
    deploy_active = build_in_progress or (bool(required) and pending > 0 and failed == 0)

    return {
        "config": config.public_dict() if config else None,
        "config_error": None,
        "secrets_set": config.secrets_set() if config else {},
        "nim_deploy_mode": config.nim_deploy_mode if config else None,
        "mode_summary": mode_summary(config),
        "services": services,
        "pipeline_ready": pipeline_ready,
        "pipeline_failed": failed > 0,
        "endpoints_ready": endpoints_ready,
        "build_in_progress": build_in_progress,
        "build": build,
        "deploy_active": deploy_active,
    }
