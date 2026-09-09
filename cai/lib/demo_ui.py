"""Helpers for the Next.js Launchpad demo UI."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

from cai.lib.paths import PROJECT_ROOT

DEMO_DIR = PROJECT_ROOT / "client" / "demos"
SERVER_JS = DEMO_DIR / "dist" / "server.js"
NEXT_DIR = DEMO_DIR / ".next"
RUNTIME_DEMO_DIR = Path(os.environ.get("APP_ROOT", "/opt/synthetic-video-detector")) / "client" / "demos"
RUNTIME_SERVER_JS = RUNTIME_DEMO_DIR / "dist" / "server.js"


def demo_ui_ready() -> bool:
    return SERVER_JS.is_file() and NEXT_DIR.is_dir()


def copy_runtime_demo_ui() -> bool:
    """Copy pre-built dist/ and .next/ from the custom runtime image into the project."""
    if not RUNTIME_SERVER_JS.is_file():
        return False
    print(f"Copying pre-built Web UI from runtime image ({RUNTIME_SERVER_JS})", flush=True)
    for name in ("dist", ".next"):
        src = RUNTIME_DEMO_DIR / name
        dst = DEMO_DIR / name
        if not src.is_dir():
            continue
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    return demo_ui_ready()


def ensure_demo_ui() -> bool:
    if demo_ui_ready():
        return True
    return copy_runtime_demo_ui()


def missing_demo_ui_message() -> str:
    parts = [
        f"ERROR: Web UI not built — missing launch artifacts under {DEMO_DIR}",
        f"  dist/server.js: {'ok' if SERVER_JS.is_file() else 'MISSING'}",
        f"  .next/: {'ok' if NEXT_DIR.is_dir() else 'MISSING'}",
    ]
    if RUNTIME_SERVER_JS.is_file():
        parts.append(
            f"  Runtime image has a build at {RUNTIME_DEMO_DIR} but copy failed — "
            "check project directory permissions."
        )
    else:
        parts.append(
            "  Runtime image has no pre-built UI — run AMP step 'Build Web UI' first "
            "(requires SyntheticVideoDetector runtime with Node.js)."
        )
    parts.append("Set FORCE_DEMO_BUILD=1 on the Build Web UI session to force a rebuild.")
    return "\n".join(parts)
