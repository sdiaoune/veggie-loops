#!/usr/bin/env python3
"""Verify the published inputs and replay bounded preparation tests in a fresh copy."""
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import shutil
import argparse

OWN = Path(__file__).resolve().parent
ROOT = OWN.parents[3]


def identity(path):
    return {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size}


def validate(records, root):
    paths, copies = set(), set()
    for record in records:
        relative = Path(record["path"])
        if relative.is_absolute() or ".." in relative.parts or str(relative) in paths:
            raise RuntimeError("Invalid source path")
        paths.add(str(relative))
        if "execution_path" in record:
            target = Path(record["execution_path"])
            if target.is_absolute() or ".." in target.parts or str(target) in copies:
                raise RuntimeError("Invalid copied input path")
            copies.add(str(target))
        if identity(root / relative) != {key: record[key] for key in ("sha256", "bytes")}:
            raise RuntimeError("Published input changed: " + str(relative))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((OWN / "verification.json").read_text())
    records = manifest["files"]
    validate(records, ROOT)
    if args.check_only:
        print(json.dumps({"status": "published_source_bindings_verified", "files": len(records)}))
        return
    for record in manifest["original_images"]:
        if identity(Path(record["path"]))["sha256"] != record["sha256"]:
            raise RuntimeError("Installed original identity changed")
    parent = ROOT / ".tools" / "plugin-work" / "generators"
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="prevoice-public-", dir=parent))
    project = work / "project"
    candidate = project / ".tools/plugin-work/generators/prevoice-preparation-repair"
    candidate.mkdir(parents=True)
    bound = []
    for record in records:
        if "execution_path" not in record:
            continue
        target = project / record["execution_path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / record["path"], target)
        bound.append({"path": record["execution_path"], "sha256": record["sha256"]})
    seed = {"status": "published_own_source_expected_binding", "bound_source_inputs": bound,
            "original_images": manifest["original_images"], "full_plugin_equivalence": False}
    seed_path = candidate / "prevoice-repair-verification.json"
    seed_path.write_text(json.dumps(seed, indent=2) + "\n")
    output = work / "result.json"
    env = dict(os.environ, VL_PREVOICE_REPAIR_EXECUTION_COPY="1",
               VL_PREVOICE_REPAIR_PROJECT_ROOT=str(project),
               VL_PREVOICE_REPAIR_EXPECTED_MANIFEST=str(seed_path),
               VL_PREVOICE_REPAIR_OUTPUT=str(output))
    commands = [("native", ["sh", str(candidate / "verify_prevoice_repair.sh")]),
                ("sanitized", ["sh", str(candidate / "verify_prevoice_repair.sh"), "--sanitize"]),
                ("O0", ["sh", str(candidate / "verify_prevoice_repair.sh"), "--O0"]),
                ("negatives", ["sh", str(candidate / "verify_prevoice_negatives.sh")]),
                ("summary-negatives", [sys.executable, str(candidate / "summarize_prevoice_repair.py"), "--probe-rejections"]),
                ("summary", [sys.executable, str(candidate / "summarize_prevoice_repair.py")])]
    for name, command in commands:
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        (work / (name + ".stdout")).write_text(result.stdout)
        (work / (name + ".stderr")).write_text(result.stderr)
        if result.returncode or result.stderr:
            raise RuntimeError("Replay failed; outputs preserved: " + str(work))
    result = json.loads(output.read_text())
    expected = json.loads((OWN / "expected-results.json").read_text())
    if result["canonical_coverage"] != expected:
        raise RuntimeError("Canonical results differ from accepted preparation scalars")
    validate(records, ROOT)
    for record in manifest["original_images"]:
        if identity(Path(record["path"]))["sha256"] != record["sha256"]:
            raise RuntimeError("Installed original changed during replay")
    print(json.dumps({"status": "passed_published_bounded_prevoice_preparation", "work": str(work),
                      "report": str(output), "full_plugin_equivalence": False}))


if __name__ == "__main__":
    main()
