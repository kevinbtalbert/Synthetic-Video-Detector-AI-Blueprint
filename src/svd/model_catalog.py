"""Curated Hugging Face open-weights presets for Launchpad."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Literal

ModelKind = Literal["image", "videomae"]

_CATALOG_PATH = Path(__file__).resolve().parents[2] / "cai" / "config" / "open_model_catalog.json"


def _catalog_path() -> Path:
    override = os.environ.get("SVD_OPEN_MODEL_CATALOG")
    if override:
        return Path(override)
    return _CATALOG_PATH


def load_catalog() -> dict[str, Any]:
    path = _catalog_path()
    if not path.is_file():
        raise FileNotFoundError(f"Open model catalog not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def list_presets() -> list[dict[str, Any]]:
    data = load_catalog()
    presets = data.get("presets") or []
    return [p for p in presets if isinstance(p, dict) and p.get("id")]


def default_preset_id() -> str:
    data = load_catalog()
    return str(data.get("default_preset_id") or "videomae-ffc23")


def preset_by_id(preset_id: str) -> dict[str, Any] | None:
    for preset in list_presets():
        if preset.get("id") == preset_id:
            return preset
    return None


def preset_for_hf_model(hf_model_id: str) -> dict[str, Any] | None:
    needle = hf_model_id.strip()
    for preset in list_presets():
        if preset.get("hf_model_id") == needle:
            return preset
    return None


def resolve_open_model_config() -> tuple[str, ModelKind, str | None]:
    """Return (hf_model_id, kind, preset_id)."""
    preset_id = os.environ.get("SVD_OPEN_MODEL_PRESET", "").strip() or None
    hf_id = os.environ.get("SVD_HF_MODEL_ID", "").strip()
    kind_raw = os.environ.get("SVD_OPEN_MODEL_KIND", "").strip().lower()

    if preset_id:
        preset = preset_by_id(preset_id)
        if preset:
            hf_id = str(preset.get("hf_model_id") or hf_id)
            kind_raw = str(preset.get("kind") or kind_raw)

    if not hf_id:
        preset = preset_by_id(default_preset_id())
        if preset:
            preset_id = str(preset.get("id"))
            hf_id = str(preset.get("hf_model_id"))
            kind_raw = str(preset.get("kind") or "image")

    if not preset_id and hf_id:
        matched = preset_for_hf_model(hf_id)
        if matched:
            preset_id = str(matched.get("id"))

    if kind_raw not in {"image", "videomae"}:
        matched = preset_for_hf_model(hf_id)
        kind_raw = str(matched.get("kind") if matched else "image")

    return hf_id, kind_raw, preset_id  # type: ignore[return-value]
