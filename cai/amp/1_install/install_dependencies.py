#!/usr/bin/env python3
"""AMP session: install Python dependencies and generate protobuf code."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from shutil import which

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402
from cai.lib.paths import PROJECT_ROOT  # noqa: E402


def main() -> int:
    os.chdir(PROJECT_ROOT)
    print(f"Installing into runtime Python: {sys.executable}")
    if which("uv"):
        subprocess.run(
            ["uv", "pip", "install", "--python", sys.executable, "-e", ".[test]"],
            check=True,
        )
    else:
        subprocess.run([sys.executable, "-m", "pip", "install", "-e", ".[test]"], check=True)
    grpc_stub = (
        PROJECT_ROOT
        / "src/svd/generated/nvidia/maxine/syntheticvideodetector/v1/syntheticvideodetector_pb2_grpc.py"
    )
    subprocess.run(["bash", "protos/generate_protos.sh"], check=True)
    from src.svd.patch_grpc_stub import ensure_grpc_stub  # noqa: WPS433

    ensure_grpc_stub()
    print("Dependencies and protobuf code ready")
    return 0


run_amp_entry(main, __name__)
