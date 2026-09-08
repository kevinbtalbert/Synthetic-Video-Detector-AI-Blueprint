# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""gRPC client for NVIDIA Synthetic Video Detector NIM (bundled or serverless)."""

from __future__ import annotations

import math
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import grpc

from src.svd.generated.nvidia.maxine.syntheticvideodetector.v1 import (
    syntheticvideodetector_pb2,
    syntheticvideodetector_pb2_grpc,
)
from src.svd.nvcf import (
    DEFAULT_NVCF_GRPC_HOST,
    DEFAULT_NVCF_GRPC_PORT,
    intercept_channel_with_metadata,
    is_nvcf_endpoint,
    nvcf_grpc_metadata,
    svd_nvcf_function_id,
)

DATA_CHUNK_SIZE = 2 * 1024 * 1024
CLASSIFICATION_THRESHOLD = 0.30


@dataclass
class ClipResult:
    index: int
    logit: float


@dataclass
class DetectionResult:
    probability: float
    logit: float
    total_clips: int
    csv_data: str
    clip_results: list[ClipResult]
    is_synthetic: bool
    synthetic_score_percent: float


def _expit(logit: float) -> float:
    if logit >= 0:
        return 1.0 / (1.0 + math.exp(-logit))
    exp_logit = math.exp(logit)
    return exp_logit / (1.0 + exp_logit)


def resolve_svd_target() -> tuple[str, bool, tuple[tuple[str, str], ...] | None]:
    """Return (host:port, use_tls, nvcf_metadata)."""
    endpoint = os.environ.get("SVD_SERVER", "").strip()
    if endpoint:
        host, _, port = endpoint.partition(":")
        port = port or "8001"
        target = f"{host}:{port}"
        if is_nvcf_endpoint(host):
            api_key = os.environ.get("NGC_API_KEY", "").strip()
            if not api_key:
                raise RuntimeError("NGC_API_KEY is required for serverless NVCF mode")
            return target, True, nvcf_grpc_metadata(api_key, svd_nvcf_function_id())
        return target, False, None

    mode = os.environ.get("NIM_DEPLOY_MODE", "BUNDLED").strip().upper()
    if mode == "SERVERLESS":
        host = os.environ.get("NVIDIA_SERVERLESS_GRPC_HOST", DEFAULT_NVCF_GRPC_HOST)
        port = os.environ.get("NVIDIA_SERVERLESS_GRPC_PORT", DEFAULT_NVCF_GRPC_PORT)
        api_key = os.environ.get("NGC_API_KEY", "").strip()
        if not api_key:
            raise RuntimeError("NGC_API_KEY is required for serverless mode")
        return f"{host}:{port}", True, nvcf_grpc_metadata(api_key, svd_nvcf_function_id())

    return "127.0.0.1:8001", False, None


def _video_chunks(video_path: Path) -> Iterator[syntheticvideodetector_pb2.DetectSyntheticVideoRequest]:
    with video_path.open("rb") as handle:
        while True:
            chunk = handle.read(DATA_CHUNK_SIZE)
            if not chunk:
                break
            yield syntheticvideodetector_pb2.DetectSyntheticVideoRequest(video_file_data=chunk)


def detect_video(video_path: str | Path, *, timeout_s: int = 600) -> DetectionResult:
    """Analyze an H.264 MP4 and return aggregated synthetic probability."""
    path = Path(video_path)
    if not path.is_file():
        raise FileNotFoundError(f"Video not found: {path}")
    if path.suffix.lower() != ".mp4":
        raise ValueError("Synthetic Video Detector supports MP4 (H.264) only")

    target, use_tls, metadata = resolve_svd_target()
    if use_tls:
        channel = grpc.secure_channel(target, grpc.ssl_channel_credentials())
    else:
        channel = grpc.insecure_channel(target)
    if metadata:
        channel = intercept_channel_with_metadata(channel, metadata)

    stub = syntheticvideodetector_pb2_grpc.SyntheticVideoDetectorServiceStub(channel)
    clip_results: list[ClipResult] = []
    final_probability = 0.0
    final_logit = 0.0
    total_clips = 0
    csv_data = ""

    responses = stub.DetectSyntheticVideo(_video_chunks(path), timeout=timeout_s)
    for response in responses:
        which = response.WhichOneof("stream_output")
        if which == "clip_result":
            clip = response.clip_result
            clip_results.append(ClipResult(index=clip.index, logit=clip.logit))
        elif which == "final_result":
            final = response.final_result
            final_logit = final.logit
            final_probability = final.probability or _expit(final.logit)
            total_clips = final.total_clips
            csv_data = final.csv_data or ""
        elif which == "keepalive":
            continue

    channel.close()

    score = final_probability if final_probability else _expit(final_logit)
    return DetectionResult(
        probability=score,
        logit=final_logit,
        total_clips=total_clips,
        csv_data=csv_data,
        clip_results=clip_results,
        is_synthetic=score >= CLASSIFICATION_THRESHOLD,
        synthetic_score_percent=round(score * 100, 1),
    )
