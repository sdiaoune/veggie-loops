#!/usr/bin/env python3
"""Verify the published closure and replay the scoped Mute/Phase lifetime checks."""
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

OWN = Path(__file__).resolve().parent
ROOT = OWN.parents[3]


def identity(path):
    return {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("source", "native", "all"), default="all")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((OWN / "verification.json").read_text())
    records = manifest["files"]
    seen_paths, seen_copies = set(), set()
    for record in records:
        relative = Path(record["path"])
        if relative.is_absolute() or ".." in relative.parts or str(relative) in seen_paths:
            raise RuntimeError("Invalid published source path")
        seen_paths.add(str(relative))
        if "execution_path" in record:
            target = Path(record["execution_path"])
            if target.is_absolute() or ".." in target.parts or str(target) in seen_copies:
                raise RuntimeError("Invalid copied source path")
            seen_copies.add(str(target))
        if identity(ROOT / relative) != {key: record[key] for key in ("sha256", "bytes")}:
            raise RuntimeError("Published input changed: " + str(relative))
    if args.check_only:
        print(json.dumps({"status": "published_source_bindings_verified", "files": len(records)}))
        return
    work_parent = ROOT / ".tools" / "plugin-work" / "review"
    work_parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="mute-phase-public-", dir=work_parent))
    tree = work / "source"
    tree.mkdir()
    copied = []
    for record in records:
        if "execution_path" not in record:
            continue
        destination = tree / record["execution_path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / record["path"], destination)
        copied.append({"relative_path": record["execution_path"], **identity(destination)})
    (tree / "source-bindings.json").write_text(json.dumps({"files": copied}, indent=2) + "\n")
    phases = ("source", "native") if args.phase == "all" else (args.phase,)
    reports = []
    for phase in phases:
        output = work / (phase + "-run")
        result = subprocess.run([sys.executable, str(tree / "verify_lifetime.py"),
                                 "--phase", phase, "--work", str(output)],
                                capture_output=True, text=True)
        (work / (phase + ".stdout")).write_text(result.stdout)
        (work / (phase + ".stderr")).write_text(result.stderr)
        if result.returncode or result.stderr:
            raise RuntimeError("Lifetime replay failed; preserved outputs: " + str(work))
        reports.append({"phase": phase, "report": str(output / "result.json")})
    for record in records:
        if identity(ROOT / record["path"]) != {key: record[key] for key in ("sha256", "bytes")}:
            raise RuntimeError("Published input changed during replay")
    print(json.dumps({"status": "passed_published_scoped_lifetime_replay", "work": str(work),
                      "reports": reports, "full_plugin_equivalence": False}))


if __name__ == "__main__":
    main()
