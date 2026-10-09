#!/usr/bin/env python3
"""Replay the bounded Center own lifetimes and intact-engine regressions."""
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import uuid

OWN = Path(__file__).resolve().parent
ROOT = OWN.parents[3]
REPLAY = Path(".tools/plugin-work/review/center-lifetime-public-replay")
DIAGNOSTICS = ("Sanitizer", "runtime error:", "UndefinedBehavior")


def identity(path):
    h = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
            size += len(block)
    return {"sha256": h.hexdigest(), "bytes": size}


def expected_identity(row):
    return {key: row[key] for key in ("sha256", "bytes")}


def relative(name):
    path = Path(name)
    if not isinstance(name, str) or path.is_absolute() or not path.parts or ".." in path.parts or str(path) != name:
        raise RuntimeError("Invalid relative input path")
    return path


def exact(value, expected):
    if type(value) is not type(expected):
        return False
    if isinstance(expected, dict):
        return value.keys() == expected.keys() and all(exact(value[key], expected[key]) for key in expected)
    if isinstance(expected, list):
        return len(value) == len(expected) and all(exact(a, b) for a, b in zip(value, expected))
    return value == expected


def validate(records):
    paths, targets = set(), set()
    for row in records:
        path = relative(row["path"])
        if str(path) in paths or not (ROOT / path).resolve().is_relative_to(ROOT):
            raise RuntimeError("Duplicate or escaping public input")
        paths.add(str(path))
        if identity(ROOT / path) != expected_identity(row):
            raise RuntimeError("Published input differs: " + str(path))
        for name in row.get("execution_paths", []):
            target = relative(name)
            if str(target) in targets:
                raise RuntimeError("Duplicate copied input")
            targets.add(str(target))


def original_pins(records):
    for row in records:
        path = Path(row["path"])
        if not path.is_absolute() or identity(path) != expected_identity(row):
            raise RuntimeError("Installed original differs: " + str(path))


def verified_phase(output, phase, expected):
    report_path = output / "verification.json"
    report = json.loads(report_path.read_text())
    if report.get("status") != "passed_scoped_Center_" + phase + "_lifetime_recipe" or report.get("phase") != phase:
        raise RuntimeError("Canonical phase status differs")
    for field in ("original_extra_destructor_equivalence", "application_created", "full_plugin_equivalence"):
        if report.get(field) is not False:
            raise RuntimeError("Canonical phase scope differs: " + field)
    rows = report["results"]["positive_profiles"]
    required = expected[phase]["positive_profiles"]
    if len(rows) != len(required):
        raise RuntimeError("Missing or extra positive result")
    for row, golden in zip(rows, required):
        for field in ("mode", "variant") + (("fixture",) if phase == "native" else ()):
            if not exact(row[field], golden[field]):
                raise RuntimeError("Positive profile identity differs")
        if not exact(row["result"], golden["result"]):
            raise RuntimeError("Positive JSON value/type differs")
        if row["run"]["exit_code"] != 0 or row["run"]["stderr"]["bytes"] != 0:
            raise RuntimeError("Positive process was not clean")
    if phase == "source":
        negatives = report["results"]["fatal_semantic_negatives"]
        if len(negatives) != len(expected[phase]["fatal_semantic_negatives"]):
            raise RuntimeError("Missing or extra semantic negative")
        for row, golden in zip(negatives, expected[phase]["fatal_semantic_negatives"]):
            if not exact(row["name"], golden["name"]) or not exact(row["expected_semantic_diagnostic"], golden["diagnostic"]):
                raise RuntimeError("Semantic negative identity differs")
            if row["rejection"]["exit_code"] != 1 or row["rejection"]["stdout"]["bytes"] != 0:
                raise RuntimeError("Semantic negative did not reject cleanly")
            diagnostic_path = output / "mutants" / row["name"] / "rejection.stderr"
            if diagnostic_path.read_bytes() != (golden["diagnostic"] + "\n").encode():
                raise RuntimeError("Semantic negative diagnostic differs")
    products, strict, architectures = set(), set(), set()
    for row in report["artifacts"]:
        path = Path(row["path"])
        if not path.resolve().is_relative_to(output.resolve()) or identity(path) != expected_identity(row):
            raise RuntimeError("Canonical artifact missing, escaped or changed")
        if not path.name.endswith(".command.json"):
            continue
        command = json.loads(path.read_text())
        argv = command["argv"]
        if argv[:4] == ["codesign", "--force", "--sign", "-"]:
            if command["exit_code"] != 0:
                raise RuntimeError("Signing failed")
            products.add(argv[-1])
        elif argv[:3] == ["codesign", "--verify", "--strict"]:
            if command["exit_code"] != 0 or command["stdout"]["bytes"] or command["stderr"]["bytes"]:
                raise RuntimeError("Strict signature failed")
            strict.add(argv[-1])
        elif argv[:2] == ["lipo", "-archs"]:
            stem = path.name[:-len(".command.json")]
            if command["exit_code"] != 0 or (path.parent / (stem + ".stdout")).read_bytes().strip() != b"arm64" or command["stderr"]["bytes"]:
                raise RuntimeError("Architecture verification failed")
            architectures.add(argv[-1])
    if len(products) != expected[phase]["signed_products"] or products != strict or products != architectures:
        raise RuntimeError("Missing signed/strict arm64 products")
    return {"phase": phase, "report": str(report_path), "positive_profiles": len(required),
            "fatal_semantic_negatives": 4 if phase == "source" else 0,
            "signed_strict_arm64_products": len(products), "report_identity": identity(report_path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("source", "native", "all"), default="all")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    manifest_path = OWN / "verification.json"
    manifest_identity = identity(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    records = manifest["files"]
    validate(records)
    expected_path = OWN / "expected-results.json"
    expected = json.loads(expected_path.read_text())
    if args.check_only:
        # No original file, ignored directory, compiler or child process is read/created/called here.
        print(json.dumps({"status": "published_Center_source_bindings_verified", "files": len(records)}))
        return
    if os.environ.get("VL_CENTER_PUBLIC_SLOT_GRANTED") != "1":
        raise RuntimeError("An explicit compiler/native slot grant is required")
    if platform.system() != "Darwin" or platform.machine() not in ("arm64", "aarch64"):
        raise RuntimeError("Center replay requires macOS arm64")
    phases = ("source", "native") if args.phase == "all" else (args.phase,)
    originals = manifest["original_images"] if "native" in phases else []
    original_pins(originals)
    parent = ROOT / ".tools/plugin-work/effects/center-lifetime-public"
    work = parent / ("replay-" + uuid.uuid4().hex)
    project = work / "project"
    copies, staged = [], []
    for row in records:
        for name in row.get("execution_paths", []):
            destination = project / name
            item = expected_identity(row)
            copies.append({"kind": "public_copy", "path": str(destination), "source": str(ROOT / row["path"]), **item})
            staged.append({"path": name, **item})
    seed_path = project / REPLAY / "candidate-source.json"
    seed_bytes = (json.dumps({"status": "generated_exact_public_Center_replay_bindings", "records": staged}, indent=2) + "\n").encode()
    copies.append({"kind": "generated_candidate_map", "path": str(seed_path),
                   "sha256": hashlib.sha256(seed_bytes).hexdigest(), "bytes": len(seed_bytes)})
    registry_path = work / "registered-inputs.json"
    registry_bytes = (json.dumps({"copied_and_generated_inputs_registered_before_attempted_writes": copies}, indent=2) + "\n").encode()
    copies.append({"kind": "generated_input_registry", "path": str(registry_path),
                   "sha256": hashlib.sha256(registry_bytes).hexdigest(), "bytes": len(registry_bytes)})
    # Every expected destination/seed identity is registered before any mkdir/copy/write attempt.
    reports, audit_rows = [], []
    primary_failure, postflight_failures = None, []
    result_publication_failure, report = None, None
    try:
        parent.mkdir(parents=True, exist_ok=True)
        work.mkdir(exist_ok=False)
        registry_path.write_bytes(registry_bytes)
        for item in copies:
            if item["kind"] != "public_copy":
                continue
            destination = Path(item["path"])
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(item["source"], destination)
            if identity(destination) != expected_identity(item):
                raise RuntimeError("Copied input differs")
        seed_path.parent.mkdir(parents=True, exist_ok=True)
        seed_path.write_bytes(seed_bytes)
        if identity(seed_path) != expected_identity(copies[-2]):
            raise RuntimeError("Generated map differs")
        recipe = project / REPLAY / "verify_lifetime.py"
        for phase in phases:
            output = work / (phase + "-run")
            argv = [sys.executable, str(recipe), phase, "--work", str(output)]
            command_path = work / (phase + ".command.json")
            invocation = {"argv": argv, "stage": "before_child", "exit_code": None}
            command_path.write_text(json.dumps(invocation, indent=2) + "\n")
            environment = dict(os.environ, VL_CENTER_PUBLIC_EXECUTION_COPY="1", VL_CENTER_LIFETIME_SLOT_GRANTED=phase)
            result = subprocess.run(argv, capture_output=True, text=True, env=environment)
            (work / (phase + ".stdout")).write_text(result.stdout)
            (work / (phase + ".stderr")).write_text(result.stderr)
            invocation.update(stage="child_returned", exit_code=result.returncode)
            command_path.write_text(json.dumps(invocation, indent=2) + "\n")
            if result.returncode or result.stderr or any(token in result.stdout for token in DIAGNOSTICS):
                raise RuntimeError("Canonical replay failed; logs preserved: " + str(work))
            summary = {"status": "passed_scoped_Center_" + phase + "_lifetime_recipe", "report": str(output / "verification.json")}
            if not exact(json.loads(result.stdout), summary):
                raise RuntimeError("Canonical summary differs")
            reports.append(verified_phase(output, phase, expected))
    except BaseException as failure:
        primary_failure = {"type": type(failure).__name__, "message": str(failure)}
    finally:
        def audit(category, path, wanted):
            row = {"category": category, "path": str(path), "expected": wanted, "actual": None, "error": None}
            try:
                row["actual"] = identity(path)
                if row["actual"] != wanted:
                    raise RuntimeError("Identity differs")
            except BaseException as failure:
                row["error"] = {"type": type(failure).__name__, "message": str(failure)}
                postflight_failures.append(row)
            audit_rows.append(row)
        for row in records:
            audit("public", ROOT / row["path"], expected_identity(row))
        audit("manifest", manifest_path, manifest_identity)
        for row in copies:
            audit(row["kind"], Path(row["path"]), expected_identity(row))
        for row in originals:
            audit("original", Path(row["path"]), expected_identity(row))
        if primary_failure is None and not postflight_failures:
            report = {"status": "passed_published_bounded_Center_lifetime_and_engine_checks", "phase": args.phase,
                      "work": str(work), "reports": reports, "own_NSApplication_created": True,
                      "actual_FL_application_created": False, "native_editor128cycles_bypass_only": True,
                      "original_extra_destructor_equivalence": False, "full_plugin_equivalence": False}
            try:
                (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
            except BaseException as failure:
                result_publication_failure = {"type": type(failure).__name__, "message": str(failure)}
                postflight_failures.append({"category": "result_publication", **result_publication_failure})
        final = {"primary_failure": primary_failure, "postflight_failures": postflight_failures,
                 "audit_rows": audit_rows, "registered_inputs": copies, "reports": reports,
                 "result_publication_failure": result_publication_failure,
                 "full_plugin_equivalence": False}
        try:
            (work / "postflight.json").write_text(json.dumps(final, indent=2) + "\n")
        except BaseException as failure:
            postflight_failures.append({"category": "postflight_recording", "type": type(failure).__name__, "message": str(failure)})
    if primary_failure or postflight_failures:
        raise RuntimeError("Center replay or final audit failed; preserve outputs: " + str(work) +
                           "; primary=" + json.dumps(primary_failure) + "; postflight=" + json.dumps(postflight_failures))
    print(json.dumps(report))


if __name__ == "__main__":
    main()
