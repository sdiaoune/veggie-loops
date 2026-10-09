#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -ne 0 ]; then exit 2; fi
work_dir=${VL_TYRELL_XY_REPAIR_WORK_DIR:-"$source_dir/replay"}
mkdir -p "$work_dir"
VL_TYRELL_XY_WORK_DIR="$work_dir/canonical" sh "$source_dir/verify.sh" > "$work_dir/canonical.log" 2>&1
sh "$source_dir/verify-effects-supplement-fenv.sh" "$work_dir/canonical" "$work_dir/endpoint" > "$work_dir/endpoint.log" 2>&1
sh "$source_dir/verify_validation_native_active.sh" "$work_dir/canonical" "$work_dir/native-active" > "$work_dir/native-active.log" 2>&1
sh "$source_dir/verify_validation_contract_qualified.sh" "$work_dir/validation-contract" > "$work_dir/validation-contract.log" 2>&1
sh "$source_dir/verify_validation_o0.sh" "$work_dir/o0" > "$work_dir/o0.log" 2>&1
python3 "$source_dir/verify_validation_negatives.py" "$work_dir/validation-negative" > "$work_dir/validation-negative.log" 2>&1
python3 "$source_dir/summarize_validation.py" "$source_dir" "$work_dir"
