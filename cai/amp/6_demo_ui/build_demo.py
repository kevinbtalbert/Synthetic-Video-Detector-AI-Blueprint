#!/usr/bin/env python3
"""Build Next.js demo UI (skipped when dist/ exists in project or runtime image)."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from shutil import which

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402
from cai.lib.paths import PROJECT_ROOT  # noqa: E402

DEMO_DIR = PROJECT_ROOT / "client" / "demos"
SERVER_JS = DEMO_DIR / "dist" / "server.js"
RUNTIME_DEMO_DIR = Path(os.environ.get("APP_ROOT", "/opt/synthetic-video-detector")) / "client" / "demos"
RUNTIME_SERVER_JS = RUNTIME_DEMO_DIR / "dist" / "server.js"


def _copy_runtime_build() -> bool:
    """Use pre-built UI from the custom runtime image when the git checkout has no dist/."""
    if not RUNTIME_SERVER_JS.is_file():
        return False
    print(f"Copying pre-built Web UI from runtime image ({RUNTIME_SERVER_JS})")
    for name in ("dist", ".next"):
        src = RUNTIME_DEMO_DIR / name
        dst = DEMO_DIR / name
        if not src.is_dir():
            continue
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    return SERVER_JS.is_file()


def main() -> int:
    os.chdir(DEMO_DIR)
    next_dir = DEMO_DIR / ".next"

    if (
        SERVER_JS.is_file()
        and next_dir.is_dir()
        and not os.environ.get("FORCE_DEMO_BUILD", "").strip()
    ):
        print(f"Web UI already built ({SERVER_JS}) — skipping npm build")
        print("Set FORCE_DEMO_BUILD=1 to rebuild after code changes.")
        return 0

    if _copy_runtime_build() and not os.environ.get("FORCE_DEMO_BUILD", "").strip():
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
