# Synthetic Video Detector

Cloudera AI Workbench blueprint with **two deploy modes** from Launchpad:

| Mode | What it is |
|------|------------|
| **Bundled (GPU)** | **New:** Hugging Face model server + Detect UI in one application (three curated presets). Replaces the old NIM-in-pod bundle. |
| **Serverless (CPU)** | **Same as 1.6:** NVIDIA Synthetic Video Detector via NVCF gRPC (`grpc.nvcf.nvidia.com`), NGC API key, function ID. |

Both use runtime edition **SyntheticVideoDetector** v1.9 (single Docker image: open + serverless Python extras).

## Build

```bash
./scripts/docker/build-svd-image.sh
```

Register `cai/runtime/METADATA.yaml` in the Runtime Catalog.

## Architecture

```
Launchpad
  ├─ Deploy Serverless → CPU app → src/svd/client.py → NVCF gRPC
  └─ Deploy Bundled    → GPU app → HF model in pod + UI → HTTP localhost
```

See [cai/README.md](cai/README.md) for AMP tasks and model presets.
