#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/effects"
work_dir="$project_root/.tools/plugin-work/effects/center-boundary-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -fsanitize=address,undefined \
 "$source_dir/test_center_boundary.cpp" -o "$work_dir/test_boundary"
"$work_dir/test_boundary"
