#!/usr/bin/env bash
# Build-time stubs required when NIM rootfs runs inside the Cloudera ML runtime (not as PID 1).
set -euo pipefail

stub_dir="/opt/synthetic-video-detector/cai/runtime/bin"
mkdir -p "${stub_dir}"

cat >"${stub_dir}/deviceQuery" <<'EOF'
#!/usr/bin/env bash
# Stub for NIM entrypoint.d GPU check — CAI runtime has nvidia-smi but not CUDA samples.
cap="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || true)"
major="${cap%%.*}"
minor="${cap##*.}"
name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo GPU)"
echo "Detected 1 CUDA Capable device(s)"
echo "Device 0: \"${name}\""
echo "  CUDA Capability Major/Minor version number:    ${major:-7}.${minor:-5}"
exit 0
EOF
chmod u=rwx,go=rx "${stub_dir}/deviceQuery"

echo "Installed NIM runtime stubs under ${stub_dir}"
