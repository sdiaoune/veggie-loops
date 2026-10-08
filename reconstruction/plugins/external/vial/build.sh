#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Source-only research build. Does not install plugins.
set -euo pipefail
vial_module="$(cd "$(dirname "$0")" && pwd)"
vial_revision=636ca0ef517a4db087a6a08a6a8a5e704e21f836
if [[ $# != 1 ]]; then
  echo "usage: $0 /absolute/path/to/new-build-directory" >&2
  exit 2
fi
vial_work="$1"
if [[ "$vial_work" != /* || -e "$vial_work" ]]; then
  echo "Use an absolute build directory that does not already exist." >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "This recipe is verified only on an arm64 Mac with Xcode." >&2
  exit 2
fi
mkdir -p "$vial_work"
git clone https://github.com/mtytel/vital.git "$vial_work/source"
git -C "$vial_work/source" checkout --detach "$vial_revision"
git -C "$vial_work/source" apply --check "$vial_module/sample-state-offset.patch"
git -C "$vial_work/source" apply "$vial_module/sample-state-offset.patch"
vial_build="$vial_work/build/Debug"
mkdir -p "$vial_build"
xcodebuild -project "$vial_work/source/plugin/builds/osx/Vial.xcodeproj" \
  -scheme 'Vial - VST3' -configuration Debug -jobs 4 \
  -derivedDataPath "$vial_work/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=14.0 \
  CODE_SIGNING_ALLOWED=NO DEPLOYMENT_LOCATION=NO \
  CONFIGURATION_BUILD_DIR="$vial_build" SYMROOT="$vial_work/build" \
  'OTHER_CPLUSPLUSFLAGS=$(inherited) -DJUCE_VST3_CAN_REPLACE_VST2=0' build
xcodebuild -project "$vial_work/source/plugin/builds/osx/Vial.xcodeproj" \
  -scheme 'Vial - AU' -configuration Debug -jobs 4 \
  -derivedDataPath "$vial_work/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=14.0 \
  CODE_SIGNING_ALLOWED=NO DEPLOYMENT_LOCATION=NO \
  CONFIGURATION_BUILD_DIR="$vial_build" SYMROOT="$vial_work/build" \
  'OTHER_CPLUSPLUSFLAGS=$(inherited) -DJUCE_VST3_CAN_REPLACE_VST2=0' build
vial_bundle="$vial_build/Vial Research.vst"
mkdir -p "$vial_bundle/Contents/MacOS"
xcrun clang++ -arch arm64 -std=c++17 -g -O0 -DDEBUG=1 -D_DEBUG=1 \
  -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG \
  -DJUCE_VST3_CAN_REPLACE_VST2=0 \
  -I "$vial_work/source/plugin/JuceLibraryCode" \
  -I "$vial_work/source/third_party/JUCE/modules" \
  -bundle "$vial_module/legacy_wrapper.cpp" "$vial_build/libVial.a" \
  -framework Cocoa -framework AudioToolbox -framework CoreAudio -framework CoreAudioKit \
  -framework CoreMIDI -framework Accelerate -framework IOKit -framework WebKit \
  -framework Security -framework OpenGL -framework CoreGraphics -framework QuartzCore \
  -o "$vial_bundle/Contents/MacOS/Vial Research"
python3 - "$vial_bundle" <<'PY'
import plistlib,sys
from pathlib import Path
bundle=Path(sys.argv[1])
info={'CFBundleExecutable':'Vial Research',
      'CFBundleIdentifier':'org.veggieloops.research.vial-legacy',
      'CFBundleName':'Vial Research','CFBundlePackageType':'BNDL',
      'CFBundleVersion':'1.0.6','CFBundleShortVersionString':'1.0.6',
      'NSHighResolutionCapable':True}
(bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
for vial_artifact in "$vial_build/Vial.vst3" "$vial_build/Vial.component" "$vial_bundle"; do
  codesign --force --deep --sign - "$vial_artifact"
done
echo "Research artifacts: $vial_build"
