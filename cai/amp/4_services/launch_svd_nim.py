#!/usr/bin/env python3
"""Launch bundled Synthetic Video Detector NIM on CAI (BUNDLED mode only)."""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402
from cai.lib.deploy_mode import is_bundled_nim_mode  # noqa: E402
from cai.lib.launch_app import run_bash_script, run_wrong_deploy_mode_message  # noqa: E402


def main() -> int:
    if not is_bundled_nim_mode():
        return run_wrong_deploy_mode_message("svd-nim", expected="BUNDLED")
    return run_bash_script("cai/amp/4_services/launch_svd_nim.sh")


run_amp_entry(main, __name__)
