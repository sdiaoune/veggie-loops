#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo 'Usage: build_hosts.sh /absolute/path/to/VST3_SDK [arm64|x86_64]' >&2
  exit 2
fi
sdk="$1"
probe_arch="${2:-arm64}"
case "$probe_arch" in arm64|x86_64) ;; *) echo 'Unsupported host architecture' >&2; exit 2 ;; esac
for source in pluginterfaces/base/funknown.cpp pluginterfaces/base/coreiids.cpp public.sdk/source/vst/vstinitiids.cpp; do
  test -f "$sdk/$source" || { echo "Missing SDK source: $source" >&2; exit 1; }
done
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
probe_output="$repo_root/.tools/plugin-work/common/$probe_arch"
mkdir -p "$probe_output"
xcrun clang++ -arch "$probe_arch" -std=c++17 -O2 -Wno-pragma-pack -Wno-deprecated-declarations \
  -I "$sdk" "$repo_root/reconstruction/plugins/common/vst3_probe.cpp" \
  "$sdk/pluginterfaces/base/funknown.cpp" "$sdk/pluginterfaces/base/coreiids.cpp" \
  "$sdk/public.sdk/source/vst/vstinitiids.cpp" -framework CoreFoundation -o "$probe_output/vst3_probe"
xcrun clang++ -arch "$probe_arch" -std=c++17 -O2 "$repo_root/reconstruction/plugins/common/au_probe.cpp" \
  -framework AudioToolbox -framework CoreFoundation -o "$probe_output/au_probe"
echo "$probe_output"
