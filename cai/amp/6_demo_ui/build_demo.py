#!/usr/bin/env python3
"""Build Next.js demo UI (skipped when dist/ exists in project or runtime image)."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from shutil import which

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402
from cai.lib.demo_ui import DEMO_DIR, SERVER_JS, copy_runtime_demo_ui, demo_ui_ready  # noqa: E402


def main() -> int:
    os.chdir(DEMO_DIR)

    if demo_ui_ready() and not os.environ.get("FORCE_DEMO_BUILD", "").strip():
        print(f"Web UI already built ({SERVER_JS}) — skipping npm build")
        print("Set FORCE_DEMO_BUILD=1 to rebuild after code changes.")
        return 0

    if copy_runtime_demo_ui() and not os.environ.get("FORCE_DEMO_BUILD", "").strip():
        print(f"Web UI ready from runtime image ({SERVER_JS})")
        return 0

    if not which("npm"):
        print("ERROR: npm not found — use the SyntheticVideoDetector runtime edition or install Node.js")
        return 1

    install_cmd = ["npm", "ci"] if (DEMO_DIR / "package-lock.json").is_file() else ["npm", "install"]
    for cmd in (install_cmd, ["npm", "run", "build"]):
        print("Running:", " ".join(cmd), flush=True)
        subprocess.run(cmd, check=True)

    if not SERVER_JS.is_file():
        print(f"ERROR: build finished but {SERVER_JS} is missing")
        return 1

    print(f"Web UI built ({SERVER_JS})")
    return 0


run_amp_entry(main, __name__)
