# Synthetic Video Detector on Cloudera AI Workbench

CAI deployment overlay for the NVIDIA Synthetic Video Detector NIM.

## Architecture

Three CAI applications — not three copies of the same UI:

| App | Role |
|-----|------|
| **Launchpad** | Configure env vars and **generate** standalone runtime apps |
| **Serverless runtime** | NVCF gRPC + Detect/Demo UI (CPU) |
| **Bundled runtime** | Stock NIM + Detect/Demo UI (GPU, one pod) |

### Bundled runtime (single container model)

The runtime image **embeds the NGC NIM rootfs** at build time (`scripts/docker/copy-nim-bundle.sh`). At runtime the bundled app:

1. Reads config from **CML application environment variables** (set by Launchpad at deploy time)
2. Starts **stock NIM** the same way the NGC container does: `nvidia_entrypoint.sh` → `start_server.sh` via `run-bundled-nim.sh`
3. Runs a **single readiness thread** (wait → wire `127.0.0.1:8001` for detection)
4. Serves the **Next.js UI** on `CDSW_APP_PORT`

No sidecar, no duplicate watchers, no reading Launchpad config files from disk.

Integration glue that remains (build-time, not runtime one-offs):

| Piece | Why |
|-------|-----|
| `copy-nim-bundle.sh` | NIM filesystem lives under `/opt/nvidia-nim/...` inside Cloudera base image |
| `run-bundled-nim.sh` | Isolates NIM Python from Cloudera `PYTHONPATH`; execs stock entrypoint |
| `deviceQuery` stub | Baked in image — CAI has `nvidia-smi` but not CUDA samples |
| `wrapt` in image | Bundled Python dep, installed at Docker build |

### Serverless runtime

Same UI artifact; `launch_serverless_app.py` wires NVCF endpoints and starts the UI. No local NIM.

## Modes

| Mode | GPU | Inference |
|------|-----|-----------|
| **BUNDLED** | 1× GPU | Local gRPC `:8001` in pod |
| **SERVERLESS** | 0 | `grpc.nvcf.nvidia.com:443` |

## Build runtime image

```bash
export NGC_API_KEY='...'
echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin
./scripts/docker/build-svd-image.sh
```

Register **SyntheticVideoDetector** in Runtime Catalog (`cai/runtime/METADATA.yaml`).

## AMP tasks

1. Install Python deps + protos
2. Build Next.js UI
3. Start Launchpad

From Launchpad: configure → deploy Serverless and/or Bundled runtime apps.

## Bundled NIM ports (in pod)

- HTTP health: `8000`
- gRPC inference: `8001`

## Troubleshooting

| Issue | Action |
|-------|--------|
| NGC pull fails | Verify API key and [AI for Media](https://developer.nvidia.com/ai-for-media/private-access-program) access |
| NIM slow first start | Model download 15–30 min; check `volumes/models/synthetic-video-detector` |
| `/dev/shm` too small | Set project shared memory to 8192 MB |
| gRPC servicer error | See `cai/config/svd_nim.log`; ensure runtime image includes latest `run-bundled-nim.sh` |
| Serverless auth error | Confirm `SVD_NVIDIA_FUNCTION_ID` and `NGC_API_KEY` on deployed app |
