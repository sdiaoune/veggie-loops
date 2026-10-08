#!/bin/bash
set -euo pipefail
if [ "$#" -gt 1 ]; then
  echo 'Usage: build_legacy_host.sh [arm64|x86_64]' >&2
  exit 2
fi
probe_arch="${1:-arm64}"
case "$probe_arch" in arm64|x86_64) ;; *) echo 'Unsupported host architecture' >&2; exit 2 ;; esac
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
probe_output="$repo_root/.tools/plugin-work/common/$probe_arch"
mkdir -p "$probe_output"
xcrun clang++ -arch "$probe_arch" -std=c++17 -O2 -Wall -Wextra \
  "$repo_root/reconstruction/plugins/common/vst2_probe.mm" \
  -framework AppKit -framework CoreFoundation -o "$probe_output/vst2_probe"
codesign --force --sign - "$probe_output/vst2_probe"
echo "$probe_output/vst2_probe"
