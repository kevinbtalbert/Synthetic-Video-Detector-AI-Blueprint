#!/usr/bin/env python3
"""Start the Next.js runtime UI (shared by all-in-one apps)."""

from __future__ import annotations

import sys
from pathlib import Path

import os

sys.path.insert(0, str(Path(os.environ.get("CDSW_PROJECT_DIR", "/home/cdsw"))))

from cai.lib.amp_runtime import run_amp_entry  # noqa: E402
from cai.lib.runtime_app import start_runtime_ui  # noqa: E402


def main() -> int:
    return start_runtime_ui()


run_amp_entry(main, __name__)
