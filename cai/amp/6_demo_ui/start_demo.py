#!/usr/bin/env python3
"""Start the Synthetic Video Detector Launchpad (Next.js demo UI)."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402
from cai.lib.app_config import apply_persisted_config  # noqa: E402
from cai.lib.cai_common import apply_dotenv_to_os  # noqa: E402
from cai.lib.paths import CONFIG_DIR, ENDPOINTS_ENV, PROJECT_ROOT  # noqa: E402
from cai.lib.runtime_env import capture_runtime_context  # noqa: E402
from cai.lib.service_env import load_config_defaults  # noqa: E402


def main() -> int:
    load_config_defaults()
    apply_persisted_config()
    if ENDPOINTS_ENV.exists():
        apply_dotenv_to_os(ENDPOINTS_ENV)
    capture_runtime_context()

    demo = PROJECT_ROOT / "client" / "demos"
    port = os.environ.get("CDSW_APP_PORT", "3000")
    env = {**os.environ, "PORT": port, "CDSW_APP_PORT": port}
    if (demo / "dist").is_dir():
        return subprocess.call(["npm", "run", "start"], cwd=demo, env=env)
    return subprocess.call(["npm", "run", "dev"], cwd=demo, env=env)


run_amp_entry(main, __name__)
