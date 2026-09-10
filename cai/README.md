# Synthetic Video Detector on Cloudera AI Workbench

CAI deployment overlay for the NVIDIA Synthetic Video Detector NIM. Upstream detection logic uses the official gRPC API; CAI automation lives under `cai/`.

## Modes

| Mode | GPU app | Endpoint |
|------|---------|----------|
| **BUNDLED** | 1× Synthetic Video Detector NIM | Pod IP `:8001` from `cai/nim_endpoints.json` |
| **SERVERLESS** | None (optional placeholder) | `grpc.nvcf.nvidia.com:443` + NVCF auth metadata |

## Build runtime image

```bash
export NGC_API_KEY='...'
echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin
./scripts/docker/build-svd-image.sh
```

Register **SyntheticVideoDetector** v1.1 in Runtime Catalog (`cai/runtime/METADATA.yaml`).

## AMP tasks

1. Install Python deps + protos
2. Build Next.js UI
3. Start Launchpad (`synthetic-video-detector-ui`)

From Launchpad **Configure**: save NGC key, pick mode, **Build pipeline**.

## Bundled NIM ports

- HTTP health: `8000`
- gRPC inference: `8001`

## Troubleshooting

| Issue | Action |
|-------|--------|
| NGC pull fails | Verify API key and [AI for Media](https://developer.nvidia.com/ai-for-media/private-access-program) access if required |
| NIM slow first start | Model download 15–30 min; check `volumes/models/synthetic-video-detector` |
| `/dev/shm` too small | Set project shared memory to 8192 MB |
| A100/H100 | Not supported — use T4/L4/A10 class GPU |
| Serverless auth error | Confirm `SVD_NVIDIA_FUNCTION_ID` and `NGC_API_KEY` |
