#!/usr/bin/env python3
"""Replay the bounded own 3x Osc factory lifetime checks in a fresh source copy."""
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
        if identity(ROOT / relative) != {key: record[key] for key in ("sha256", "bytes")}:
            raise RuntimeError("Published input changed: " + str(relative))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((OWN / "verification.json").read_text())
    records = manifest["files"]
    validate(records)
    if args.check_only:
        print(json.dumps({"status": "published_source_bindings_verified", "files": len(records)}))
        return
    parent = ROOT / ".tools" / "plugin-work" / "review"
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="three-osc-lifetime-public-", dir=parent))
    project = work / "project"
    prefix = ".tools/plugin-work/review/three-osc-lifetime-repair-generators-v3"
    candidate = project / prefix
    candidate.mkdir(parents=True)
    own_files, external = [], []
    for record in records:
        if "execution_path" not in record:
            continue
        target = project / record["execution_path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / record["path"], target)
        item = {"path": record["execution_path"], "sha256": record["sha256"], "size": record["bytes"]}
        if target.parent == candidate:
            item["name"] = target.name
            own_files.append(item)
        else:
            external.append(item)
    seed = {"owned_sources": own_files, "external_compilation_closure": external}
    (candidate / "candidate-source.json").write_text(json.dumps(seed, indent=2) + "\n")
    env = dict(os.environ, VL_SOURCE_LIFETIME_SLOT_GRANTED="1")
    result = subprocess.run([sys.executable, str(candidate / "verify_lifetime.py"), "source",
                             "--work", str(work / "results")], env=env, capture_output=True, text=True)
    (work / "stdout").write_text(result.stdout)
    (work / "stderr").write_text(result.stderr)
    if result.returncode or result.stderr:
        raise RuntimeError("Lifetime replay failed; outputs preserved: " + str(work))
    validate(records)
    print(json.dumps({"status": "passed_published_own_three_factory_lifetimes", "work": str(work),
                      "report": str(work / "results/verification.json"), "full_plugin_equivalence": False}))


if __name__ == "__main__":
    main()
