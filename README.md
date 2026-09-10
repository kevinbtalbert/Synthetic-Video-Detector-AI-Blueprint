# Synthetic Video Detector AI Blueprint

NVIDIA Synthetic Video Detector blueprint for **Cloudera AI Workbench**, modeled after the [Content Localization blueprint](https://github.com/kevinbtalbert/Content-Localization-for-Media-Blueprint). It supports two deployment modes:

| Mode | Description |
|------|-------------|
| **Bundled** | Synthetic Video Detector NIM runs as a GPU application in your CAI project (weights baked into the custom runtime image at build time). |
| **Serverless** | Inference uses the [NVIDIA Cloud Functions gRPC API](https://build.nvidia.com/nvidia/synthetic-video-detector) — no local GPU NIM required. |

## Architecture

```
Launchpad UI (Next.js)
    → POST /api/detect
    → Python gRPC client (src/svd/client.py)
    → Bundled NIM :8001  OR  grpc.nvcf.nvidia.com:443 (serverless)
```

## Prerequisites

- **NGC API key** with Synthetic Video Detector entitlement ([generate key](https://org.ngc.nvidia.com/setup/api-key))
- **Bundled mode:** GPU with NVENC/NVDEC (T4, L4, A10, L40, RTX — not A100/H100). See [support matrix](https://docs.nvidia.com/nim/maxine/synthetic-video-detector/latest/support-matrix.html).
- **Serverless mode:** Outbound HTTPS to `grpc.nvcf.nvidia.com` (evaluation use only)
- **Cloudera AI:** Custom runtime **SyntheticVideoDetector** v1.1, 8 GB shared memory for bundled NIM

## Quick start (local docker-compose)

```bash
cp .env.example .env
# Edit .env — set NGC_API_KEY

# Serverless (no local GPU NIM):
export NIM_DEPLOY_MODE=SERVERLESS
docker compose --env-file .env up --build

# Bundled (requires GPU + docker.sock for NIM sidecar):
export NIM_DEPLOY_MODE=BUNDLED
docker compose --env-file .env up --build
```

Open `http://localhost:3000` → **Configure** → save NGC key → **Build pipeline** → **Detect**.

## Build runtime image (EC2 / GPU builder)

On a GPU host with Docker and NGC login:

```bash
export NGC_API_KEY='your-key'
echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin

./scripts/docker/build-svd-image.sh
# → synthetic-video-detector:1.1.0-<gpu-arch>

unset NGC_API_KEY
docker push <your-registry>/synthetic-video-detector:1.1.0-turing
```

Register in **Admin → Runtime Catalog** using `cai/runtime/METADATA.yaml` (edition: `SyntheticVideoDetector`).

## Cloudera AI AMP

1. Add `catalog-entry.yaml` to your AMP catalog
2. Install AMP; set **Edition** = `SyntheticVideoDetector`
3. Provide `NGC_API_KEY` on Configure Project
4. Enable **Unauthenticated App Access** for `synthetic-video-detector-ui`
5. Open Launchpad → choose **Bundled** or **Serverless** → Build pipeline

See [cai/README.md](cai/README.md) for CAI-specific details.

## CLI detection

```bash
pip install -e .
export NGC_API_KEY=...
export NIM_DEPLOY_MODE=SERVERLESS

python -m src.svd.cli --video-input assets/fake_sample_video.mp4
```

Bundled (local NIM on :8001):

```bash
export NIM_DEPLOY_MODE=BUNDLED
export SVD_SERVER=127.0.0.1:8001
python -m src.svd.cli --video-input assets/sample.mp4
```

## NVCF defaults

| Setting | Value |
|---------|-------|
| Function ID | `847b6e53-0133-452d-ab85-d7acf3ace723` |
| gRPC host | `grpc.nvcf.nvidia.com:443` |
| NIM image | `nvcr.io/nim/nvidia/synthetic-video-detector:latest` |
| Classification threshold | 30% |

## Input requirements

- MP4 with **H.264** video codec
- Max **500 MB** (serverless); up to 1024 MB configurable for bundled NIM
- Constant frame rate (VFR not supported)

## License

GOVERNING TERMS: Apache License 2.0. NVIDIA Synthetic Video Detector NIM is governed by [NVIDIA Software and Model Evaluation License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-software-and-model-evaluation-license/) and related model licenses.

## References

- [NVIDIA build.nvidia.com — Synthetic Video Detector](https://build.nvidia.com/nvidia/synthetic-video-detector)
- [NIM documentation](https://docs.nvidia.com/nim/maxine/synthetic-video-detector/latest/index.html)
- [Python client (nim-clients)](https://github.com/NVIDIA-Maxine/nim-clients/tree/main/synthetic-video-detector)
