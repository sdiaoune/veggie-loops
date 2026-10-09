#!/usr/bin/env python3
"""Bounded source-only Vial1.0.6 research matrix. No installed plugin required."""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[3]
PIN = "636ca0ef517a4db087a6a08a6a8a5e704e21f836"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, timeout=60):
    return subprocess.run(list(map(str, command)), text=True, capture_output=True,
                          timeout=timeout, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-build-directory", type=pathlib.Path,
                        help="Existing output of external/vial/build.sh; input is read-only")
    parser.add_argument("--work-directory", type=pathlib.Path,
                        help="New absolute output directory, default review-owned private path")
    parser.add_argument("--smoke", action="store_true", help="Only 48k/512; matrix counts remain explicit")
    args = parser.parse_args()
    work = args.work_directory or ROOT / ".tools/plugin-work/review" / ("vial-matrix-" + uuid.uuid4().hex)
    if not work.is_absolute() or work.exists():
        parser.error("Use a new absolute work directory")
    work.mkdir(parents=True)
    source_build = args.source_build_directory
    if source_build is None:
        source_build = work / "upstream"
        # This path is new, unrelated to any installed or other agent's bundle.
        run([ROOT / "reconstruction/plugins/external/vial/build.sh", source_build], timeout=3600)
    source_build = source_build.resolve()
    revision = run(["git", "-C", source_build / "source", "rev-parse", "HEAD"]).stdout.strip()
    if revision != PIN:
        raise ValueError("Wrong upstream source revision")
    original = source_build / "build/Debug/Vial Research.vst"
    info = plistlib.loads((original / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleVersion") != "1.0.6" or info.get("CFBundleIdentifier") != "org.veggieloops.research.vial-legacy":
        raise ValueError("Wrong source-build artifact identity")
    bundle = work / "Vial Research.vst"
    shutil.copytree(original, bundle)
    artifact = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
    fixture = ROOT / "reconstruction/plugins/review/vial_matrix_probe.mm"
    probe = work / "vial-matrix-probe"
    run(["clang++", "-std=c++17", "-O1", "-g", "-fsanitize=address,undefined",
         "-fno-sanitize-recover=all", fixture, "-framework", "AppKit",
         "-framework", "CoreFoundation", "-o", probe])
    run(["codesign", "--force", "--sign", "-", probe])
    validator_path = ROOT / "reconstruction/plugins/common/validate_vital_state.py"
    spec = importlib.util.spec_from_file_location("state_validator", validator_path)
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    nominal_rates = (8000, 44100, 48000, 96000, 192000)
    blocks = (1, 2, 3, 31, 64, 511, 512, 1024, 8191, 8192)
    cases = [(rate, block) for rate in nominal_rates for block in blocks]
    cases += [(rate, block) for rate in (8001, 191999) for block in (1, 511, 8192)]
    if args.smoke:
        cases = [(48000, 512)]
    report = {
        "scope": "Finite disclosed source-build matrix; no installed Vital1.0.7, arbitrary preset/state, GUI or realtime certificate",
        "source_version": "Vial1.0.6", "installed_reference_version": "Vital1.0.7",
        "installed_reference_loaded": False, "whole_plugin_equivalence": False,
        "upstream_revision": revision, "sample_state_offset_patch_disclosed": True,
        "artifact_sha256": digest(artifact),
        "source_built_library_sha256": digest(source_build / "build/Debug/libVial.a"),
        "public_recipe_sha256": digest(ROOT / "reconstruction/plugins/external/vial/build.sh"),
        "glue_source_sha256": digest(ROOT / "reconstruction/plugins/external/vial/legacy_wrapper.cpp"),
        "fixture_sha256": digest(fixture), "runner_sha256": digest(pathlib.Path(__file__)),
        "host_declaration_sha256": digest(ROOT / "reconstruction/plugins/common/vst2_probe.mm"),
        "state_validator_sha256": digest(validator_path),
        "fresh_upstream_build_in_this_run": args.source_build_directory is None,
        "plugin_dependency_sanitized": False, "host_fixture_sanitized": True,
        "planned_case_count": len(cases), "completed_case_count": 0,
        "all_cases_completed": False, "status": "running", "cases": [], "errors": [],
    }
    state_cases = {(rate, block) for rate in (8000, 48000, 192000) for block in (1, 511, 8192)}
    for rate, block in cases:
        rounds = 20 if (rate, block) in state_cases or args.smoke else 1
        prefix = work / f"rate-{rate}-block-{block}"
        try:
            result = run([probe, bundle, prefix, rate, block, rounds, "1.0.6"], timeout=60)
            (work / f"{prefix.name}.log").write_text(result.stdout + result.stderr)
            line = next(line for line in reversed(result.stdout.splitlines()) if line.startswith('{"status":'))
            row = json.loads(line)
            row["state_semantics"] = []
            initial = pathlib.Path(str(prefix) + "-g0.bin")
            for generation in range(1, rounds + 1):
                before = pathlib.Path(str(prefix) + f"-g{generation-1}.bin")
                after = pathlib.Path(str(prefix) + f"-g{generation}.bin")
                adjacent = validator.validate(before, after, tolerance=1)
                cumulative = validator.validate(initial, after, tolerance=1)
                row["state_semantics"].append({"generation": generation, "adjacent": adjacent,
                                               "cumulative_from_initial": cumulative,
                                               "bytes_equal": before.read_bytes() == after.read_bytes()})
            row["pcm_tolerant_stability"] = True
            row["exact_byte_idempotence_all_rounds"] = row["exact_adjacent_state_pairs"] == rounds
            row["exact_final_pair"] = row["state_semantics"][-1]["bytes_equal"]
            report["cases"].append(row)
            print(f"passed rate={rate} block={block} rounds={rounds}", flush=True)
        except (subprocess.SubprocessError, ValueError, KeyError, OSError) as error:
            if isinstance(error, subprocess.CalledProcessError):
                (work / f"{prefix.name}.log").write_text((error.stdout or "") + (error.stderr or ""))
            report["errors"].append({"rate": rate, "block": block, "error": str(error)})
            print(f"failed rate={rate} block={block}: {error}", flush=True)
        report["completed_case_count"] = len(report["cases"]) + len(report["errors"])
        report["status"] = "running" if not report["errors"] else "failed"
        (work / "matrix.json").write_text(json.dumps(report, indent=2) + "\n")
    report["all_cases_completed"] = report["completed_case_count"] == len(cases)
    report["status"] = "passed" if not report["errors"] and report["all_cases_completed"] else "failed"
    (work / "matrix.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "passed_cases": len(report["cases"]),
                      "failed_cases": len(report["errors"]), "report": str(work / "matrix.json")}))
    return 0 if not report["errors"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (subprocess.SubprocessError, ValueError, OSError) as error:
        print(f"matrix_failed: {error}", file=sys.stderr)
        raise SystemExit(1)
