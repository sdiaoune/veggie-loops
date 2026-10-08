"""Retain reproducible measurements, hashes and a strict small-engine scope."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

repo = Path(sys.argv[1]).resolve()
original = Path(sys.argv[2]).resolve()
work = repo / ".tools/plugin-work/generators"
reports = repo / "analysis/plugins/generators/three-osc"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exports(path):
    result = subprocess.run(["nm", "-arch", "arm64", "-gU", str(path)],
                            text=True, check=True, capture_output=True)
    return sorted({line.split()[-1] for line in result.stdout.splitlines() if line.strip()})


target_exports = exports(original)
model_exports = exports(work / "libvl_three_osc_engine.dylib")
missing = sorted(set(target_exports) - set(model_exports))
if missing:
    raise SystemExit("Missing original public exports: " + ", ".join(missing))
measurements = {
    name: json.loads((reports / filename).read_text())
    for name, filename in [
        ("bounded_replay", "differential-tests.json"),
        ("dispatcher_fft_tables", "table-engine-tests.json"),
        ("public_class_abi", "public-abi-tests.json"),
        ("compiler_termination_helper", "exception-termination-tests.json"),
    ]
}
if any(result["status"] != "passed" for result in measurements.values()):
    raise SystemExit("A native verification gate did not pass")
result = {
    "status": "passed",
    "scope": "3x Osc small DSP engine, valid serial successful inputs",
    "source_sha256": sha(original),
    "architecture": "arm64",
    "target_public_export_count": len(target_exports),
    "target_public_exports": target_exports,
    "missing_public_exports": missing,
    "compiled_source_sha256": {
        p.name: sha(p) for p in sorted((repo / "reconstruction/plugins/generators").glob("*.?pp"))
    },
    "recompiled_library_sha256": sha(work / "libvl_three_osc_engine.dylib"),
    "measurements": measurements,
    "full_fruity_plugin_recompiled": False,
    "vst_au_recompiled": False,
    "fl_studio_feature_parity": False,
    "limitations": [
        "The separate multi-megabyte Fruity wrapper, UI, presets, automation and host integration are absent.",
        "Allocation failure, original allocation traces, C++ exception personality and malformed inputs are not equivalent.",
        "Factory teardown clears the global pointer defensively; the native implementation leaves a stale pointer until recreation.",
        "General FFT bounds and valid mipmap configurations are documented in source; evidence covers the tested configurations.",
        "No commercial executable, disassembly, asset or source payload is packaged in the rebuilt library.",
    ],
}
(repo / "reconstruction/plugins/generators/verification.json").write_text(json.dumps(result, indent=2) + "\n")
(reports / "export-coverage.json").write_text(json.dumps({
    "target": target_exports, "recompiled": model_exports, "missing": missing
}, indent=2) + "\n")
print(json.dumps({"status": result["status"], "public_exports": len(target_exports),
                  "missing_exports": missing, "full_fruity_plugin_recompiled": False}))
