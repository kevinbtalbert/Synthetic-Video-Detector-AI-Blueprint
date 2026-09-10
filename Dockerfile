# syntax=docker/dockerfile:1
# Synthetic Video Detector unified runtime for Cloudera AI Workbench.
#
# Build (requires NGC login):
#   echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin
#   ./scripts/docker/build-svd-image.sh

FROM --platform=linux/amd64 nvcr.io/nim/nvidia/synthetic-video-detector:latest AS nim-svd

FROM --platform=linux/amd64 docker.repository.cloudera.com/cloudera/cdsw/ml-runtime-pbj-jupyterlab-python3.13-cuda:2026.08.1-b5

USER root
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_ROOT=/opt/synthetic-video-detector \
    NIM_BUNDLE_ROOT=/opt/nvidia-nim

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl wget jq git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ln -sf /root/.local/bin/uv /usr/local/bin/uv

COPY scripts/docker/record-nim-bundle-entrypoint.sh /tmp/record-nim-bundle-entrypoint.sh
COPY scripts/docker/copy-nim-bundle.sh /tmp/copy-nim-bundle.sh
RUN chmod +x /tmp/record-nim-bundle-entrypoint.sh /tmp/copy-nim-bundle.sh
RUN --mount=from=nim-svd,source=/,target=/nim-src,readonly \
    bash /tmp/copy-nim-bundle.sh /nim-src "${NIM_BUNDLE_ROOT}/synthetic-video-detector" synthetic-video-detector /tmp/record-nim-bundle-entrypoint.sh

COPY build/nim-model-cache/synthetic-video-detector /opt/nvidia-nim/baked-model-cache/synthetic-video-detector
RUN mkdir -p /opt/nvidia-nim/baked-model-cache/synthetic-video-detector && \
    chown -R cdsw:cdsw "${NIM_BUNDLE_ROOT}/synthetic-video-detector" /opt/nvidia-nim/baked-model-cache

WORKDIR ${APP_ROOT}
COPY pyproject.toml README.md ./
COPY protos ./protos
COPY src ./src
COPY cai ./cai
COPY client ./client
COPY assets ./assets
COPY scripts/docker ./scripts/docker

RUN chmod +x scripts/docker/*.sh cai/runtime/scripts/*.sh && \
    uv sync --extra test && \
    bash protos/generate_protos.sh 2>/dev/null || true && \
    mkdir -p /var/lib/synthetic-video-detector/models && \
    chown -R cdsw:cdsw ${APP_ROOT} /var/lib/synthetic-video-detector

COPY cai/runtime/scripts/run-bundled-nim.sh /usr/local/bin/run-bundled-nim
RUN chmod +x /usr/local/bin/run-bundled-nim

USER cdsw
WORKDIR ${APP_ROOT}/client/demos
RUN if [ -f package-lock.json ]; then npm ci && npm run build; elif [ -f package.json ]; then npm install && npm run build; fi

WORKDIR ${APP_ROOT}

LABEL com.cloudera.ml.runtime.edition="SyntheticVideoDetector" \
      com.cloudera.ml.runtime.full.version="1.1.0" \
      com.cloudera.ml.runtime.short.version="1.1" \
      ML_RUNTIME_EDITOR="JupyterLab" \
      ML_RUNTIME_KERNEL="Python 3.13" \
      ML_RUNTIME_EDITION="SyntheticVideoDetector" \
      ML_RUNTIME_FULL_VERSION="1.1.0" \
      ML_RUNTIME_SHORT_VERSION="1.1"

ENV PYTHONPATH="${APP_ROOT}:${APP_ROOT}/src"
