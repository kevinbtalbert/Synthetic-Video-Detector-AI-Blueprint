#!/usr/bin/env python3
"""Start the Synthetic Video Detector Launchpad (Next.js demo UI)."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from shutil import which

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402
from cai.lib.app_config import apply_persisted_config  # noqa: E402
from cai.lib.cai_common import apply_dotenv_to_os  # noqa: E402
from cai.lib.demo_ui import DEMO_DIR, SERVER_JS, ensure_demo_ui, missing_demo_ui_message  # noqa: E402
from cai.lib.paths import ENDPOINTS_ENV, ensure_cai_dirs  # noqa: E402
from cai.lib.runtime_env import log_runtime_context  # noqa: E402
from cai.lib.service_env import load_config_defaults  # noqa: E402


def main() -> int:
    try:
        log_runtime_context()
        load_config_defaults()
        apply_persisted_config()
        if ENDPOINTS_ENV.exists():
            apply_dotenv_to_os(ENDPOINTS_ENV)
        ensure_cai_dirs()
    except Exception as exc:
        print(f"WARNING: startup configuration step failed: {exc}", flush=True)

    port = os.environ.get("CDSW_APP_PORT") or os.environ.get("PORT") or "8080"
    os.environ["PORT"] = str(port)
    os.environ.setdefault("NODE_ENV", "production")

    if not ensure_demo_ui():
        print(missing_demo_ui_message(), flush=True)
        return 1

    node = which("node") or "/usr/bin/node"
    if not Path(node).is_file():
        print(f"ERROR: node not found (tried {node})", flush=True)
        return 1

    os.chdir(DEMO_DIR)
    print(f"Starting Launchpad UI: {node} {SERVER_JS} on 127.0.0.1:{port}", flush=True)
    return subprocess.call([node, str(SERVER_JS)])


run_amp_entry(main, __name__)
