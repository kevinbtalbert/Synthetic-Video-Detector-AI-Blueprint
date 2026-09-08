#!/usr/bin/env python3
"""Build Next.js demo UI (skipped when dist/ exists in runtime image)."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402
from cai.lib.paths import PROJECT_ROOT  # noqa: E402


def main() -> int:
    demo = PROJECT_ROOT / "client" / "demos"
    if (demo / "dist").is_dir():
        print("Demo dist/ already present — skipping build")
        return 0
    subprocess.run(["npm", "ci"], cwd=demo, check=True)
    subprocess.run(["npm", "run", "build"], cwd=demo, check=True)
    return 0


run_amp_entry(main, __name__)
