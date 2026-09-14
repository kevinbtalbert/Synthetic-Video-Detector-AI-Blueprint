#!/usr/bin/env python3
"""Alias entrypoint — use launch_bundled_app.py for Bundled deployments."""

from __future__ import annotations

import runpy
from pathlib import Path

runpy.run_path(str(Path(__file__).with_name("launch_bundled_app.py")), run_name="__main__")
