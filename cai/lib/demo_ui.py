"""Helpers for the Next.js Launchpad demo UI."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from shutil import which

from cai.lib.paths import PROJECT_ROOT

DEMO_DIR = PROJECT_ROOT / "client" / "demos"
SERVER_JS = DEMO_DIR / "dist" / "server.js"
NEXT_DIR = DEMO_DIR / ".next"
RUNTIME_DEMO_DIR = Path(os.environ.get("APP_ROOT", "/opt/synthetic-video-detector")) / "client" / "demos"
RUNTIME_SERVER_JS = RUNTIME_DEMO_DIR / "dist" / "server.js"


def demo_ui_ready() -> bool:
    return SERVER_JS.is_file() and NEXT_DIR.is_dir()


def demo_sources_newer_than_dist() -> bool:
    """True when Launchpad app sources changed after the last next build."""
    if not SERVER_JS.is_file():
        return True
    dist_mtime = SERVER_JS.stat().st_mtime
    app_dir = DEMO_DIR / "app"
    if not app_dir.is_dir():
        return False
    for path in app_dir.rglob("*"):
        if path.is_file() and path.stat().st_mtime > dist_mtime:
            return True
    return False


def _remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def _link_runtime_tree(name: str) -> bool:
    src = RUNTIME_DEMO_DIR / name
    dst = DEMO_DIR / name
    if not src.is_dir():
        return False
    _remove_path(dst)
    os.symlink(src, dst, target_is_directory=True)
    return True


def _copy_runtime_tree(name: str) -> bool:
    src = RUNTIME_DEMO_DIR / name
    dst = DEMO_DIR / name
    if not src.is_dir():
        return False
    _remove_path(dst)
    shutil.copytree(src, dst)
    return True


def copy_runtime_demo_ui() -> bool:
    """Use pre-built dist/ and .next/ from the custom runtime image."""
    if not RUNTIME_SERVER_JS.is_file():
        return False

    print(f"Using pre-built Web UI from runtime image ({RUNTIME_DEMO_DIR})", flush=True)
    ok = True
    for name in ("dist", ".next"):
        linked = _link_runtime_tree(name)
        copied = linked or _copy_runtime_tree(name)
        ok = ok and copied
    return demo_ui_ready() if ok else False


def build_demo_ui() -> bool:
    """Run npm install/ci + next build in the project demo directory."""
    if not which("npm"):
        print("ERROR: npm not found — use SyntheticVideoDetector runtime or run Build Web UI", flush=True)
        return False

    os.chdir(DEMO_DIR)
    lock = DEMO_DIR / "package-lock.json"
    install = ["npm", "ci"] if lock.is_file() else ["npm", "install"]
    for cmd in (install, ["npm", "run", "build"]):
        print("Running:", " ".join(cmd), flush=True)
        subprocess.run(cmd, check=True)
    return demo_ui_ready()


def ensure_demo_ui(*, allow_build: bool = True) -> bool:
    if demo_ui_ready():
        return True
    if copy_runtime_demo_ui():
        return True
    if allow_build and not os.environ.get("SKIP_DEMO_BUILD", "").strip():
        try:
            return build_demo_ui()
        except subprocess.CalledProcessError as exc:
            print(f"ERROR: Web UI build failed (exit {exc.returncode})", flush=True)
    return False


def missing_demo_ui_message() -> str:
    parts = [
        f"ERROR: Web UI not built — missing launch artifacts under {DEMO_DIR}",
        f"  dist/server.js: {'ok' if SERVER_JS.is_file() else 'MISSING'}",
        f"  .next/: {'ok' if NEXT_DIR.is_dir() else 'MISSING'}",
        f"  runtime UI at {RUNTIME_SERVER_JS}: {'ok' if RUNTIME_SERVER_JS.is_file() else 'MISSING'}",
        f"  APP_ROOT: {os.environ.get('APP_ROOT', '(not set, default /opt/synthetic-video-detector)')}",
        f"  npm: {which('npm') or 'MISSING'}",
    ]
    parts.append("Run AMP step 'Build Web UI', or restart Launchpad on SyntheticVideoDetector runtime.")
    return "\n".join(parts)
