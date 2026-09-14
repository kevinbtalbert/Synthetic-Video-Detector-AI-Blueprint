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
        ffmpeg \
        gstreamer1.0-tools \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-libav \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-x \
        libgstreamer1.0-0 \
        libgstreamer-plugins-base1.0-0 \
        libgstreamer-plugins-good1.0-0 \
        gir1.2-gstreamer-1.0 \
        gir1.2-gst-plugins-base-1.0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ln -sf /root/.local/bin/uv /usr/local/bin/uv

COPY scripts/docker/record-nim-bundle-entrypoint.sh /tmp/record-nim-bundle-entrypoint.sh
COPY scripts/docker/copy-nim-bundle.sh /tmp/copy-nim-bundle.sh
COPY scripts/docker/install-nim-runtime-stubs.sh /tmp/install-nim-runtime-stubs.sh
COPY scripts/docker/install-nim-gstreamer.sh /tmp/install-nim-gstreamer.sh
COPY scripts/docker/verify-nim-video-decode.sh /tmp/verify-nim-video-decode.sh
RUN chmod +x /tmp/record-nim-bundle-entrypoint.sh /tmp/copy-nim-bundle.sh /tmp/install-nim-runtime-stubs.sh /tmp/install-nim-gstreamer.sh /tmp/verify-nim-video-decode.sh
COPY cai/runtime/scripts/nim-gstreamer-env.sh /tmp/nim-gstreamer-env.sh
RUN --mount=from=nim-svd,source=/,target=/nim-src,readonly \
    bash /tmp/copy-nim-bundle.sh /nim-src "${NIM_BUNDLE_ROOT}/synthetic-video-detector" synthetic-video-detector /tmp/record-nim-bundle-entrypoint.sh && \
    cp /tmp/nim-gstreamer-env.sh /usr/local/bin/nim-gstreamer-env.sh && \
    chmod u=rx,go=rx /usr/local/bin/nim-gstreamer-env.sh && \
    bash /tmp/install-nim-gstreamer.sh "${NIM_BUNDLE_ROOT}/synthetic-video-detector"

COPY build/nim-model-cache/synthetic-video-detector /opt/nvidia-nim/baked-model-cache/synthetic-video-detector
RUN mkdir -p /opt/nvidia-nim/baked-model-cache/synthetic-video-detector && \
    chown -R cdsw:cdsw "${NIM_BUNDLE_ROOT}" /opt/nvidia-nim/baked-model-cache && \
    chmod -R u+rwX,go+rX "${NIM_BUNDLE_ROOT}" /opt/nvidia-nim/baked-model-cache && \
    find "${NIM_BUNDLE_ROOT}/synthetic-video-detector" -type f \( -name '*.sh' -o -path '*/bin/*' \) -exec chmod u+rx,go+rx {} +

WORKDIR ${APP_ROOT}
COPY pyproject.toml README.md ./
COPY protos ./protos
COPY src ./src
COPY cai ./cai
COPY client ./client
COPY assets ./assets
COPY scripts/docker ./scripts/docker

RUN bash /tmp/install-nim-runtime-stubs.sh && \
    chmod +x scripts/docker/*.sh cai/runtime/scripts/*.sh cai/amp/5_apps/*.sh && \
    uv sync --extra test && \
    bash protos/generate_protos.sh 2>/dev/null || true && \
    mkdir -p /var/lib/synthetic-video-detector/models && \
    chown -R cdsw:cdsw ${APP_ROOT} /var/lib/synthetic-video-detector

COPY cai/runtime/scripts/run-bundled-nim.sh /usr/local/bin/run-bundled-nim
COPY cai/runtime/scripts/prepare-bundled-nim-models.sh /usr/local/bin/prepare-bundled-nim-models
COPY cai/runtime/scripts/bundled-svd-grpc-start.sh /usr/local/bin/bundled-svd-grpc-start
# NIM expects /opt/nim, /opt/tritonserver, /opt/synthetic-detector, and /config (→ .config-root).
RUN mkdir -p /opt/nim \
             /opt/nim/.config-root/models/synthetic-video-detector \
             /opt/nim/workspace \
             /var/lib/synthetic-video-detector/models && \
    ln -sfn /opt/nim/.config-root /config && \
    ln -sfn "${NIM_BUNDLE_ROOT}/synthetic-video-detector/opt/tritonserver" /opt/tritonserver && \
    ln -sfn "${NIM_BUNDLE_ROOT}/synthetic-video-detector/opt/synthetic-detector" /opt/synthetic-detector && \
    chown -R cdsw:cdsw /opt/nim /opt/tritonserver /opt/synthetic-detector \
      "${NIM_BUNDLE_ROOT}/synthetic-video-detector" && \
    chown cdsw:cdsw /usr/local/bin/run-bundled-nim /usr/local/bin/prepare-bundled-nim-models /usr/local/bin/bundled-svd-grpc-start && \
    chmod u=rwx,go=rx /usr/local/bin/run-bundled-nim /usr/local/bin/prepare-bundled-nim-models /usr/local/bin/bundled-svd-grpc-start && \
    test -x "${NIM_BUNDLE_ROOT}/synthetic-video-detector/opt/synthetic-detector/src/grpc/start_service.sh" && \
    cp /usr/local/bin/bundled-svd-grpc-start \
      "${NIM_BUNDLE_ROOT}/synthetic-video-detector/opt/synthetic-detector/src/grpc/start_service.sh" && \
    grep -q '127.0.0.1' "${NIM_BUNDLE_ROOT}/synthetic-video-detector/opt/synthetic-detector/src/grpc/start_service.sh" && \
    if [ -x "${NIM_BUNDLE_ROOT}/synthetic-video-detector/usr/local/bin/python3.12" ]; then \
      "${NIM_BUNDLE_ROOT}/synthetic-video-detector/usr/local/bin/python3.12" -m pip install \
        --no-cache-dir --disable-pip-version-check --no-user --isolated --break-system-packages \
        --target /opt/nvidia-nim/synthetic-video-detector/.nim_py_vendor wrapt; \
    fi

USER cdsw
WORKDIR ${APP_ROOT}

# Runtime catalog metadata (Cloudera custom-runtime convention).
# short.maintenance → full version (e.g. 1.7.0). AMP matches on short version (1.7).
# Bump ML_RUNTIME_MAINTENANCE_VERSION on each repush to register a new catalog entry.
ENV ML_RUNTIME_EDITION="SyntheticVideoDetector" \
    ML_RUNTIME_EDITOR="JupyterLab" \
    ML_RUNTIME_KERNEL="Python 3.13" \
    ML_RUNTIME_SHORT_VERSION="1.7" \
    ML_RUNTIME_MAINTENANCE_VERSION="2" \
    ML_RUNTIME_DESCRIPTION="JupyterLab Runtime with NVIDIA Synthetic Video Detector NIM"

ENV ML_RUNTIME_FULL_VERSION="${ML_RUNTIME_SHORT_VERSION}.${ML_RUNTIME_MAINTENANCE_VERSION}"

LABEL com.cloudera.ml.runtime.edition=$ML_RUNTIME_EDITION \
    com.cloudera.ml.runtime.full-version=$ML_RUNTIME_FULL_VERSION \
    com.cloudera.ml.runtime.short-version=$ML_RUNTIME_SHORT_VERSION \
    com.cloudera.ml.runtime.maintenance-version=$ML_RUNTIME_MAINTENANCE_VERSION \
    com.cloudera.ml.runtime.description=$ML_RUNTIME_DESCRIPTION \
    com.cloudera.ml.runtime.editor=$ML_RUNTIME_EDITOR

ENV PYTHONPATH="${APP_ROOT}:${APP_ROOT}/src"
