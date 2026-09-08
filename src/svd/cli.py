#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""CLI for Synthetic Video Detector inference."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow running from repo root without install
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from src.svd.client import detect_video  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect synthetic/AI-generated video content")
    parser.add_argument("--video-input", required=True, help="Path to H.264 MP4 input")
    parser.add_argument("--output-json", default="", help="Optional JSON output path")
    parser.add_argument("--save-csv", default="", help="Optional CSV output path")
    args = parser.parse_args()

    result = detect_video(args.video_input)
    payload = {
        "probability": result.probability,
        "logit": result.logit,
        "synthetic_score_percent": result.synthetic_score_percent,
        "is_synthetic": result.is_synthetic,
        "total_clips": result.total_clips,
        "threshold": 0.30,
    }
    print(json.dumps(payload, indent=2))

    if args.output_json:
        Path(args.output_json).write_text(json.dumps(payload, indent=2) + "\n")
    if args.save_csv and result.csv_data:
        Path(args.save_csv).write_text(result.csv_data)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
