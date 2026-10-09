#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/phase-inverter-check"
mkdir -p "$work_dir/private"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -dynamiclib \
  "$project_root/reconstruction/plugins/effects/phase_inverter_plugin.cpp" -o "$work_dir/VLPhaseInverter.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/test_phase_inverter_factory.mm" -o "$work_dir/test_phase_inverter_factory"
"$work_dir/test_phase_inverter_factory" \
  '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Phase Inverter/Fruity Phase Inverter_x64.dylib' \
  "$work_dir/private/" "$work_dir/VLPhaseInverter.dylib"
