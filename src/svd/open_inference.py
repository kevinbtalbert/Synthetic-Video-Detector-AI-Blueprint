"""Load HF presets and score videos (image-classifier or VideoMAE)."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from src.svd.model_catalog import ModelKind, resolve_open_model_config


@dataclass
class LoadedModel:
    kind: ModelKind
    hf_model_id: str
    preset_id: str | None
    processor: Any
    model: Any
    device: str


def _hf_token() -> str | None:
    import os

    token = os.environ.get("HF_TOKEN", "").strip()
    return token or None


def _synthetic_label_ids(id2label: dict[Any, Any]) -> set[int]:
    ids: set[int] = set()
    for idx, label in id2label.items():
        text = str(label).lower()
        if any(token in text for token in ("fake", "deep", "synthetic", "artificial", "ai")):
            ids.add(int(idx))
    return ids


def load_open_model() -> LoadedModel:
    import torch

    hf_model_id, kind, preset_id = resolve_open_model_config()
    device = "cuda" if torch.cuda.is_available() else "cpu"
    token = _hf_token()

    if kind == "videomae":
        from transformers import VideoMAEForVideoClassification, VideoMAEImageProcessor

        processor = VideoMAEImageProcessor.from_pretrained(hf_model_id, token=token)
        model = VideoMAEForVideoClassification.from_pretrained(hf_model_id, token=token)
    else:
        from transformers import AutoImageProcessor, AutoModelForImageClassification

        processor = AutoImageProcessor.from_pretrained(hf_model_id, token=token)
        model = AutoModelForImageClassification.from_pretrained(hf_model_id, token=token)

    model.to(device)
    model.eval()
    return LoadedModel(
        kind=kind,
        hf_model_id=hf_model_id,
        preset_id=preset_id,
        processor=processor,
        model=model,
        device=device,
    )


def _logit_from_prob(prob: float) -> float:
    import torch

    p = max(1e-6, min(1.0 - 1e-6, prob))
    return float(torch.logit(torch.tensor(p)))


def _aggregate(clip_results: list[dict[str, float | int]]) -> dict[str, object]:
    if not clip_results:
        raise ValueError("No scores produced")
    probability = sum(float(c["score"]) for c in clip_results) / len(clip_results)
    mean_logit = sum(float(c["logit"]) for c in clip_results) / len(clip_results)
    if 0.0 < probability < 1.0:
        mean_logit = _logit_from_prob(probability)
    csv_lines = ["clip_index,score,logit"]
    for row in clip_results:
        csv_lines.append(f"{row['index']},{row['score']:.6f},{row['logit']:.6f}")
    return {
        "probability": probability,
        "logit": mean_logit,
        "total_clips": len(clip_results),
        "csv_data": "\n".join(csv_lines) + "\n",
        "clip_results": clip_results,
    }


def _read_frame_at(cap, index: int):
    import cv2

    cap.set(cv2.CAP_PROP_POS_FRAMES, index)
    ok, frame = cap.read()
    if not ok or frame is None:
        return None
    return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)


def _score_image_model(loaded: LoadedModel, path: Path) -> dict[str, object]:
    import cv2
    import torch

    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {path}")

    sample_every = 15
    max_samples = 48
    clip_results: list[dict[str, float | int]] = []
    frame_idx = 0
    sampled = 0

    id2label = getattr(loaded.model.config, "id2label", {}) or {}
    fake_ids = _synthetic_label_ids(id2label)
    if not fake_ids and id2label:
        fake_ids = {max(int(k) for k in id2label)}

    while sampled < max_samples:
        ok, frame = cap.read()
        if not ok:
            break
        if frame_idx % sample_every != 0:
            frame_idx += 1
            continue
        frame_idx += 1
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        inputs = loaded.processor(images=rgb, return_tensors="pt")
        inputs = {k: v.to(loaded.device) for k, v in inputs.items()}
        with torch.no_grad():
            out = loaded.model(**inputs)
            probs = torch.softmax(out.logits, dim=-1)[0]
        if fake_ids:
            fake_prob = float(max(probs[i] for i in fake_ids if i < len(probs)))
        else:
            fake_prob = float(probs[-1])
        logit = _logit_from_prob(fake_prob)
        clip_results.append({"index": sampled, "logit": logit, "score": fake_prob})
        sampled += 1

    cap.release()
    return _aggregate(clip_results)


def _score_videomae(loaded: LoadedModel, path: Path) -> dict[str, object]:
    import cv2
    import torch

    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {path}")

    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    if total < 2:
        cap.release()
        raise ValueError("Video too short for VideoMAE (need at least 2 frames)")

    num_frames = int(getattr(loaded.model.config, "num_frames", 16) or 16)
    max_windows = 16
    id2label = getattr(loaded.model.config, "id2label", {}) or {}
    fake_ids = _synthetic_label_ids(id2label) or {1}

    clip_results: list[dict[str, float | int]] = []
    window_count = min(max_windows, max(1, total // num_frames))

    for window in range(window_count):
        start = int(window * total / window_count)
        end = int((window + 1) * total / window_count)
        span = max(end - start, 1)
        indices = [start + int(i * span / num_frames) for i in range(num_frames)]
        frames = []
        for idx in indices:
            rgb = _read_frame_at(cap, min(idx, total - 1))
            if rgb is not None:
                frames.append(rgb)
        if len(frames) < num_frames:
            continue
        inputs = loaded.processor(list(frames), return_tensors="pt")
        inputs = {k: v.to(loaded.device) for k, v in inputs.items()}
        with torch.no_grad():
            out = loaded.model(**inputs)
            probs = torch.softmax(out.logits, dim=-1)[0]
        fake_prob = float(max(probs[i] for i in fake_ids if i < len(probs)))
        logit = _logit_from_prob(fake_prob)
        clip_results.append({"index": window, "logit": logit, "score": fake_prob})

    cap.release()
    if not clip_results:
        raise ValueError("VideoMAE could not sample enough frames")
    return _aggregate(clip_results)


def score_video(path: Path, loaded: LoadedModel) -> dict[str, object]:
    if loaded.kind == "videomae":
        return _score_videomae(loaded, path)
    return _score_image_model(loaded, path)
