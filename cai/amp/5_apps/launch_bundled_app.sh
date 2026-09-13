#!/usr/bin/env bash
# Deprecated wrapper — use launch_bundled_app.py (Python supervisor) directly.
exec python3 "$(dirname "$0")/launch_bundled_app.py"
