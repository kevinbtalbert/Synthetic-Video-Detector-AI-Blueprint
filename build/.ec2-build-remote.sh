#!/usr/bin/env bash
# Remote EC2 build helper — run from laptop after SSH access is configured.
# Usage: EC2_HOST=ubuntu@<ip> ./build/.ec2-build-remote.sh
set -euo pipefail

host="${EC2_HOST:?set EC2_HOST=ubuntu@your-ec2}"
repo="${SVD_REPO:-Synthetic-Video-Detector-AI-Blueprint}"

ssh "${host}" "mkdir -p ~/${repo}"
rsync -avz --exclude .git --exclude node_modules --exclude .venv \
  "$(cd "$(dirname "$0")/.." && pwd)/" "${host}:~/${repo}/"

ssh "${host}" bash -lc "
  set -euo pipefail
  cd ~/${repo}
  if [[ -z \"\${NGC_API_KEY:-}\" ]]; then
    echo 'Set NGC_API_KEY on EC2 before building'
    exit 1
  fi
  echo \"\$NGC_API_KEY\" | docker login nvcr.io -u '\$oauthtoken' --password-stdin
  ./scripts/docker/build-svd-image.sh
"
