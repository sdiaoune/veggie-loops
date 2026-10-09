#!/usr/bin/env python3
"""Replay the bounded own Soft/Stereo lifetimes and engine integration."""
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

OWN = Path(__file__).resolve().parent
ROOT = OWN.parents[3]


def identity(path):
    return {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size}


def validate(records):
    paths, targets = set(), set()
    for row in records:
        relative = Path(row["path"])
        if relative.is_absolute() or ".." in relative.parts or str(relative) in paths:
            raise RuntimeError("Invalid published input path")
        paths.add(str(relative))
        if identity(ROOT / relative) != {key: row[key] for key in ("sha256", "bytes")}:
            raise RuntimeError("Published input changed: " + str(relative))
        for name in row.get("execution_paths", []):
            target = Path(name)
            if target.is_absolute() or ".." in target.parts or str(target) in targets:
                raise RuntimeError("Invalid or duplicate execution input path")
            if not target.parts or target.parts[0] not in ("source-plan", "native-plan"):
                raise RuntimeError("Execution input escapes the declared plans")
            targets.add(str(target))


def original_pins(records):
    for row in records:
        path = Path(row["path"])
        if not path.is_absolute() or identity(path) != {key: row[key] for key in ("sha256", "bytes")}:
            raise RuntimeError("Pinned installed original changed or missing")


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
    if args.check_only:
        print(json.dumps({"status": "published_source_bindings_verified", "files": len(records)}))
        return
    phases = ("source", "native") if args.phase == "all" else (args.phase,)
    if "native" in phases:
        original_pins(manifest["original_images"])
    parent = ROOT / ".tools/plugin-work/review"
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="soft-stereo-public-", dir=parent))
    source, native = work / "source-plan", work / "native-plan"
    source_rows, native_rows, copied = [], [], []
    reports = []
    primary_failure = postflight_failure = None
    try:
        source.mkdir()
        native.mkdir()
        for row in records:
            for name in row.get("execution_paths", []):
                destination = work / name
                item = {"sha256": row["sha256"], "bytes": row["bytes"]}
                copied.append({"path": str(destination), **item})
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / row["path"], destination)
                if destination.is_relative_to(source):
                    source_rows.append({"relative_path": str(destination.relative_to(source)), **item})
                else:
                    native_rows.append({"path": str(destination.relative_to(native)), **item})
        source_seed = source / "source-bindings.json"
        source_seed_text = json.dumps({"files": source_rows}, indent=2) + "\n"
        copied.append({"path": str(source_seed), "sha256": hashlib.sha256(source_seed_text.encode()).hexdigest(),
                       "bytes": len(source_seed_text.encode())})
        source_seed.write_text(source_seed_text)
        native_seed = native / "source-bindings.json"
        native_seed_text = json.dumps({"staged_inputs": native_rows, "frozen_origin_root": str(ROOT),
                                       "origin_bindings": [{key: row[key] for key in ("path", "sha256", "bytes")} for row in records],
                                       "original_images": manifest["original_images"]}, indent=2) + "\n"
        copied.append({"path": str(native_seed), "sha256": hashlib.sha256(native_seed_text.encode()).hexdigest(),
                       "bytes": len(native_seed_text.encode())})
        native_seed.write_text(native_seed_text)
        environment = dict(os.environ, VL_SOFT_STEREO_PUBLIC_EXECUTION_COPY="1",
                           VL_EFFECTS_NATIVE_SLOT_GRANTED="1")
        for phase in phases:
            directory = source if phase == "source" else native
            recipe = directory / ("verify_lifetime.py" if phase == "source" else "verify_native.py")
            argv = [sys.executable, str(recipe)]
            if phase == "source":
                argv += ["--phase", "source"]
            output = work / (phase + "-run")
            argv += ["--work", str(output)]
            result = subprocess.run(argv, capture_output=True, text=True, env=environment)
            (work / (phase + ".stdout")).write_text(result.stdout)
            (work / (phase + ".stderr")).write_text(result.stderr)
            if result.returncode or result.stderr:
                raise RuntimeError("Replay failed; preserved outputs: " + str(work))
            report = json.loads((output / "result.json").read_text())
            expected = "passed_scoped_source_lifetime_recipe" if phase == "source" else "passed_bounded_staged_engine_regressions"
            if report.get("status") != expected or report.get("full_plugin_equivalence") is not False:
                raise RuntimeError("Replay result or declared scope differs")
            reports.append({"phase": phase, "report": str(output / "result.json")})
    except Exception as error:
        primary_failure = str(error)
    finally:
        audit_rows = []

        def audit(category, path, expected):
            error = None
            actual = None
            try:
                actual = identity(path)
                if actual != expected:
                    raise RuntimeError("Identity changed")
            except Exception as failure:
                error = str(failure)
            audit_rows.append({"category": category, "path": str(path),
                               "expected": expected, "actual": actual, "error": error})

        for row in records:
            audit("published", ROOT / row["path"], {key: row[key] for key in ("sha256", "bytes")})
        audit("manifest", manifest_path, manifest_identity)
        for row in copied:
            audit("copied", Path(row["path"]), {key: row[key] for key in ("sha256", "bytes")})
        if "native" in phases:
            for row in manifest["original_images"]:
                audit("original", Path(row["path"]), {key: row[key] for key in ("sha256", "bytes")})
        failed = [row for row in audit_rows if row["error"] is not None]
        if failed:
            postflight_failure = "; ".join(row["path"] + ": " + row["error"] for row in failed)
        (work / "postflight.json").write_text(json.dumps({"primary_failure": primary_failure,
                                                        "postflight_failure": postflight_failure,
                                                        "audit_rows": audit_rows,
                                                        "copied_inputs": copied, "reports": reports,
                                                        "full_plugin_equivalence": False}, indent=2) + "\n")
    if primary_failure is not None or postflight_failure is not None:
        raise RuntimeError("Replay or final identity checks failed; outputs preserved: " + str(work))
    print(json.dumps({"status": "passed_published_bounded_Soft_Stereo_lifetime_and_engine_checks",
                      "work": str(work), "reports": reports, "full_plugin_equivalence": False}))


if __name__ == "__main__":
    main()
