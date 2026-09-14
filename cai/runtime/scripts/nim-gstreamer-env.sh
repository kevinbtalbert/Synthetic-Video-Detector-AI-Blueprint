#!/usr/bin/env bash
# Source from run-bundled-nim / bundled-svd-grpc-start (NIM python video decode).
bundle_root="${NIM_BUNDLE_ROOT:-/opt/nvidia-nim}/synthetic-video-detector"
deepstream_lib="${bundle_root}/opt/nvidia/deepstream/deepstream/lib"

prepend_path() {
  local var_name="$1"
  local segment="$2"
  [[ -z "${segment}" || ! -e "${segment}" ]] && return 0
  local current="${!var_name:-}"
  if [[ -z "${current}" ]]; then
    export "${var_name}=${segment}"
  elif [[ ":${current}:" != *":${segment}:"* ]]; then
    export "${var_name}=${segment}:${current}"
  fi
}

# System GLib/GStreamer first; NIM + DeepStream after (nvv4l2decoder / nvvideoconvert).
ld_segments=(/usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu)
[[ -d "${deepstream_lib}" ]] && ld_segments+=("${deepstream_lib}")
for lib in \
  "${bundle_root}/usr/lib/x86_64-linux-gnu" \
  "${bundle_root}/usr/lib" \
  "${bundle_root}/lib/x86_64-linux-gnu" \
  "${bundle_root}/lib"; do
  [[ -d "${lib}" ]] && ld_segments+=("${lib}")
done
IFS=:
export LD_LIBRARY_PATH="${ld_segments[*]}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
unset IFS

for gi in \
  "${bundle_root}/usr/lib/x86_64-linux-gnu/girepository-1.0" \
  "${bundle_root}/usr/lib/girepository-1.0" \
  "/usr/lib/x86_64-linux-gnu/girepository-1.0"; do
  prepend_path GI_TYPELIB_PATH "${gi}"
done

gst_segments=(/usr/lib/x86_64-linux-gnu/gstreamer-1.0)
for gst in \
  "${bundle_root}/usr/lib/x86_64-linux-gnu/gstreamer-1.0/deepstream" \
  "${bundle_root}/usr/lib/x86_64-linux-gnu/gstreamer-1.0" \
  "${bundle_root}/usr/lib/gstreamer-1.0"; do
  [[ -d "${gst}" ]] && gst_segments+=("${gst}")
done
IFS=:
export GST_PLUGIN_PATH="${gst_segments[*]}"
unset IFS

if [[ -z "${GST_PLUGIN_SCANNER:-}" ]]; then
  for scanner in \
    /usr/libexec/gstreamer-1.0/gst-plugin-scanner \
    "${bundle_root}/usr/libexec/gstreamer-1.0/gst-plugin-scanner"; do
    if [[ -x "${scanner}" ]]; then
      export GST_PLUGIN_SCANNER="${scanner}"
      break
    fi
  done
fi

export GST_PLUGIN_FEATURE_RANK="${GST_PLUGIN_FEATURE_RANK:-nvv4l2decoder:PRIMARY,nvvideoconvert:PRIMARY,h264parse:PRIMARY}"
