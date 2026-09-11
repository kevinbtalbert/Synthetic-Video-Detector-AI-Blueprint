#!/usr/bin/env python3
"""All-in-one Bundled SVD application: NIM + sidecar + detection UI in one pod."""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402


def main() -> int:
    from cai.lib.launch_app import run_bash_script  # noqa: WPS433

    return run_bash_script("cai/amp/5_apps/launch_bundled_app.sh")


run_amp_entry(main, __name__)
