"""Local Hugging Face open-weights detector HTTP service (OPEN deploy mode)."""

from __future__ import annotations

import os
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse

from src.svd.model_catalog import resolve_open_model_config
from src.svd.open_inference import LoadedModel, load_open_model, score_video

DEFAULT_PORT = 8080

_loaded: LoadedModel | None = None


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global _loaded
    _loaded = load_open_model()
    yield
    _loaded = None


app = FastAPI(title="SVD Open Weights Detector", lifespan=lifespan)


@app.get("/health")
def health() -> dict[str, object]:
    hf_id, kind, preset_id = resolve_open_model_config()
    return {
        "status": "ok",
        "model": hf_id,
        "kind": kind,
        "preset_id": preset_id,
    }


@app.post("/v1/detect")
async def detect(file: UploadFile = File(...)) -> JSONResponse:
    if _loaded is None:
        return JSONResponse({"error": "Model not loaded"}, status_code=503)
    suffix = Path(file.filename or "upload.mp4").suffix or ".mp4"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = Path(tmp.name)
    try:
        result = score_video(tmp_path, _loaded)
        return JSONResponse(result)
    finally:
        tmp_path.unlink(missing_ok=True)


def main() -> None:
    port = int(os.environ.get("SVD_OPEN_PORT", DEFAULT_PORT))
    uvicorn.run(
        "src.svd.open_server:app",
        host="127.0.0.1",
        port=port,
        log_level=os.environ.get("SVD_OPEN_LOG_LEVEL", "info"),
    )


if __name__ == "__main__":
    main()
