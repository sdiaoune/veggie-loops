"""Private staged native regression recipe; an explicit serial lease is required."""
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")
import os
if os.environ.get("VL_EFFECTS_NATIVE_SLOT_GRANTED") != "1":
    raise SystemExit("An explicit root effects native/compiler slot grant is required.")

import argparse
import hashlib
import json
import platform
from pathlib import Path
import subprocess

OWN = Path(__file__).resolve().parent
SOURCE = OWN / "project/reconstruction/plugins/effects"
MANIFEST = OWN / "source-bindings.json"
FATAL = ["-fsanitize=address,undefined,float-cast-overflow", "-fno-sanitize-recover=all",
         "-fno-omit-frame-pointer"]
COMMON = ["clang++", "-arch", "arm64", "-std=c++20", "-O2", "-ffp-contract=off",
          "-fno-fast-math", "-Wall", "-Wextra", "-Werror", "-I", str(SOURCE)]
FAMILIES = {
    "soft_clipper": {"label": "VL Soft Clipper", "macro": "VL_SOFT_CLIPPER_APPKIT_EDITOR",
                     "flags": ["-fno-builtin-exp"],
                     "checks": ["loader", "stream", "standalone_editor", "native_editor"]},
    "stereo_shaper": {"label": "VL Stereo Shaper", "macro": "VL_STEREO_SHAPER_APPKIT_EDITOR",
                      "flags": ["-fno-builtin-sin", "-fno-builtin-cos", "-fno-builtin-exp"],
                      "checks": ["loader", "stream", "routing", "standalone_editor", "native_editor"]}}


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def identity(path):
    return {"path": str(path), "sha256": digest(path), "bytes": path.stat().st_size}


def local_path(name):
    path = Path(name)
    if path.is_absolute() or ".." in path.parts:
        raise RuntimeError("Invalid staged input path")
    result = (OWN / path).resolve()
    if not result.is_relative_to(OWN):
        raise RuntimeError("Staged input escapes the private copy")
    return result


def preflight(manifest, initial_manifest_hash):
    if digest(MANIFEST) != initial_manifest_hash:
        raise RuntimeError("Frozen recipe binding manifest changed")
    seen = set()
    for record in manifest["staged_inputs"]:
        if record["path"] in seen:
            raise RuntimeError("Duplicate staged input")
        seen.add(record["path"])
        path = local_path(record["path"])
        if digest(path) != record["sha256"] or path.stat().st_size != record["bytes"]:
            raise RuntimeError("Staged source changed: " + record["path"])
    origin_root = Path(manifest["frozen_origin_root"])
    for record in manifest["origin_bindings"]:
        path = Path(record["path"])
        if not path.is_absolute():
            if ".." in path.parts:
                raise RuntimeError("Invalid frozen origin path")
            path = origin_root / path
        if digest(path) != record["sha256"] or path.stat().st_size != record["bytes"]:
            raise RuntimeError("Frozen origin changed: " + str(path))
    for record in manifest["original_images"]:
        path = Path(record["path"])
        if not path.is_absolute() or digest(path) != record["sha256"]:
            raise RuntimeError("Pinned installed original changed")


def command(argv, stem, env=None, allow_stderr=False):
    stem.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(a) for a in argv], capture_output=True, env=env)
    stem.with_suffix(".stdout").write_bytes(result.stdout)
    stem.with_suffix(".stderr").write_bytes(result.stderr)
    row = {"argv": [str(a) for a in argv], "exit": result.returncode,
           "stdout": str(stem.with_suffix(".stdout")),
           "stderr": str(stem.with_suffix(".stderr"))}
    stem.with_suffix(".command.json").write_text(json.dumps(row, indent=2) + "\n")
    if result.returncode or (result.stderr and not allow_stderr):
        raise RuntimeError("Failed command or unexpected diagnostic: " + str(stem))
    return result, row


def build(family, mode, sources, artifact, stem, *, module=False, editor=False):
    artifact.parent.mkdir(parents=True, exist_ok=True)
    flags = COMMON + FAMILIES[family]["flags"] + (FATAL if mode == "fatal" else [])
    if module:
        flags += ["-dynamiclib"]
    else:
        flags += ["-Wno-deprecated-declarations", "-framework", "Cocoa"]
    if editor:
        flags += ["-fobjc-arc"]
        if module:
            flags += ["-framework", "Cocoa", "-D" + FAMILIES[family]["macro"] + "=1"]
    result, compiled = command(flags + [SOURCE / name for name in sources] + ["-o", artifact],
                               stem.parent / (stem.name + "-compile"))
    if result.stdout:
        raise RuntimeError("Unexpected compiler stdout")
    _, signed = command(["codesign", "--force", "--sign", "-", artifact],
                        stem.parent / (stem.name + "-sign"), allow_stderr=True)
    result, verified = command(["codesign", "--verify", "--strict", artifact],
                               stem.parent / (stem.name + "-strict"))
    if result.stdout:
        raise RuntimeError("Unexpected strict-signature stdout")
    result, architecture = command(["lipo", "-archs", artifact],
                                   stem.parent / (stem.name + "-architecture"))
    if result.stdout.decode().strip() != "arm64":
        raise RuntimeError("A product is not the declared arm64 image")
    return {"artifact": identity(artifact), "compile": compiled, "sign": signed,
            "strict_signature": verified, "architecture": architecture}


def exact_json(actual, expected):
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(exact_json(actual[k], v) for k, v in expected.items())
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(exact_json(a, b) for a, b in zip(actual, expected))
    return actual == expected


def family_profile(family, mode, directory, engine, expected, environment):
    cfg = FAMILIES[family]
    default_module = directory / "default" / cfg["label"] / (cfg["label"] + "_X64.dylib")
    editor_module = directory / "editor" / (cfg["label"] + "_X64.dylib")
    products = [build(family, mode, [family + "_plugin.cpp", family + "_native_abi.cpp"],
                      default_module, directory / "default-module", module=True),
                build(family, mode, [family + "_plugin.cpp", family + "_native_abi.cpp", family + "_editor.mm"],
                      editor_module, directory / "editor-module", module=True, editor=True)]
    cases = []
    for check in cfg["checks"]:
        fixture = {"loader": "test_" + family + "_engine_loader.mm",
                   "stream": "test_" + family + "_engine_stream.mm",
                   "routing": "test_" + family + "_host_routing.mm",
                   "standalone_editor": "test_" + family + "_editor.mm",
                   "native_editor": "test_" + family + "_native_editor.mm"}[check]
        path = directory / check
        artifact = path / "test_fixture"
        sources = [fixture]
        if check == "standalone_editor":
            sources = [family + "_plugin.cpp", family + "_editor.mm", fixture]
        products.append(build(family, mode, sources, artifact, path / "fixture",
                              editor=check == "standalone_editor"))
        if check == "standalone_editor":
            argv = [artifact, path / "editor.png"]
        elif check == "loader":
            argv = [artifact, engine, default_module.parent / (cfg["label"] + ".dylib")]
        else:
            argv = [artifact, engine, editor_module if check == "native_editor" else default_module]
        result, run = command(argv, path / "run", env=environment)
        value = json.loads(result.stdout)
        if not exact_json(value, expected[check]):
            raise RuntimeError("Native scalar result differs: " + family + "/" + mode + "/" + check)
        cases.append({"check": check, "result": value, "run": run})
    return {"family": family, "mode": mode, "products": products, "cases": cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() not in ("arm64", "aarch64"):
        raise RuntimeError("The measured native engine offsets require macOS arm64")
    initial_hash = digest(MANIFEST)
    manifest = json.loads(MANIFEST.read_text())
    preflight(manifest, initial_hash)
    work = args.work.expanduser().resolve()
    if work == OWN or work.is_relative_to(OWN) or OWN.is_relative_to(work):
        raise RuntimeError("Outputs must be a fresh separate directory")
    work.mkdir(parents=True, exist_ok=False)
    expected = json.loads((OWN / "expected-results.json").read_text())
    engine = Path(next(r["path"] for r in manifest["original_images"] if r["role"] == "executed_intact_engine"))
    environment = dict(os.environ, ASAN_OPTIONS="halt_on_error=1:detect_leaks=0", UBSAN_OPTIONS="halt_on_error=1")
    profiles = []
    failure = None
    postflight_failure = None
    try:
        for mode in ("normal", "fatal"):
            for family in FAMILIES:
                profiles.append(family_profile(family, mode, work / mode / family, engine,
                                               expected[family], environment))
    except Exception as error:
        failure = str(error)
    finally:
        try:
            preflight(manifest, initial_hash)
        except Exception as error:
            postflight_failure = str(error)
    passed = failure is None and postflight_failure is None
    engine_process_attempts = sum(1 for path in work.rglob("run.command.json")
                                  if str(engine) in json.loads(path.read_text())["argv"])
    report = {"status": "passed_bounded_staged_engine_regressions" if passed else "failed_or_incomplete",
              "profiles": profiles, "error": failure, "postflight_error": postflight_failure,
              "manifest_sha256": initial_hash, "expected_checks": 18, "expected_products": 26,
              "staged_sources_and_originals_unchanged": postflight_failure is None,
              "original_engine_imported_by_completed_profiles": bool(profiles),
              "engine_fixture_process_attempts": engine_process_attempts,
              "partial_engine_execution_possible": not passed and engine_process_attempts > 0,
              "installed_effect_originals_loaded": False,
              "original_extra_destructor_equivalence": False,
              "actual_application_or_registration_owner_known": False,
              "independent_acceptance": False, "full_plugin_equivalence": False,
              "artifacts": [identity(p) for p in sorted(work.rglob("*")) if p.is_file()]}
    (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    if not passed:
        raise RuntimeError("Preserved native regression failure: " + str(work))
    print(json.dumps({"status": report["status"], "report": str(work / "result.json")}))


if __name__ == "__main__":
    main()
