#!/usr/bin/env python3
"""Validate CAI prerequisites before AMP install."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.deploy_mode import deploy_mode_label, get_nim_deploy_mode, is_bundled_nim_mode  # noqa: E402
from cai.lib.nim_runtime import nim_bundle_ready  # noqa: E402


def main() -> int:
    ok = True
    ngc = os.environ.get("NGC_API_KEY", "").strip()
    print(f"Deploy mode: {get_nim_deploy_mode().value} ({deploy_mode_label()})")
    if not ngc:
        print("WARN: NGC_API_KEY not set")
        ok = False
    else:
        print("NGC_API_KEY: set")

    if is_bundled_nim_mode():
        if shutil.which("nvidia-smi"):
            subprocess.run(["nvidia-smi", "-L"], check=False)
        else:
            print("WARN: nvidia-smi not found (required for bundled mode)")
            ok = False
        if nim_bundle_ready():
            print("Bundled NIM tree: OK (/opt/nvidia-nim/synthetic-video-detector)")
        else:
            print("WARN: bundled NIM not in runtime image — rebuild Dockerfile with NGC login")

    if shutil.which("node"):
        print(f"Node.js: {shutil.which('node')}")
    else:
        print("WARN: node not found (demo UI build may fail)")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
