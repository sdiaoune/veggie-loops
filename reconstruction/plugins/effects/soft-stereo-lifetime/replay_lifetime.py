#!/usr/bin/env python3
"""Unbuilt source-only Soft/Stereo lifetime recipe; explicit parent lease required.
All artifacts/logs go to a required fresh --work directory. No original is loaded.
"""
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")
import os
if os.environ.get("VL_SOFT_STEREO_PUBLIC_EXECUTION_COPY") != "1":
    raise SystemExit("Run the public wrapper in its fresh copied workspace.")

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

OWN = Path(__file__).resolve().parent
DEP = OWN / "dependencies"
FAMILIES = {
    "soft_clipper": {"api": "vl_soft_clipper", "macro": "VL_SOFT_CLIPPER_APPKIT_EDITOR", "label": "Soft Clipper"},
    "stereo_shaper": {"api": "vl_stereo_shaper", "macro": "VL_STEREO_SHAPER_APPKIT_EDITOR", "label": "Stereo Shaper"},
}
BASE = ["-arch", "arm64", "-std=c++20", "-fno-fast-math", "-ffp-contract=off", "-Wall", "-Wextra", "-Werror"]
FATAL = ["-fsanitize=address,undefined,float-cast-overflow", "-fno-sanitize-recover=all", "-fno-omit-frame-pointer"]
DIAGNOSTICS = ("AddressSanitizer:", "LeakSanitizer:", "UndefinedBehaviorSanitizer:", "runtime error:", "ThreadSanitizer:")


def identity(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return {"sha256": h.hexdigest(), "bytes": path.stat().st_size}



def preflight():
    records = json.loads((OWN / "source-bindings.json").read_text())["files"]
    for record in records:
        path = OWN / record["relative_path"]
        if identity(path) != {key: record[key] for key in ("sha256", "bytes")}:
            raise RuntimeError("Source binding changed: " + record["relative_path"])
    return records



def execute(argv, output, *, expected_failure=None, require_empty_output=False, require_empty_stderr=True):
    output.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    # Deliberately leaked resources in semantic negative controls are checked by
    # own allocation counters, not LSan. Every memory/UB diagnostic remains fatal.
    env["ASAN_OPTIONS"] = "halt_on_error=1:abort_on_error=1:detect_leaks=0"
    env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    result = subprocess.run([str(arg) for arg in argv], capture_output=True, text=True, env=env)
    output.with_suffix(".stdout").write_text(result.stdout)
    output.with_suffix(".stderr").write_text(result.stderr)
    record = {"argv": [str(arg) for arg in argv], "exit_code": result.returncode,
              "stdout": identity(output.with_suffix(".stdout")), "stderr": identity(output.with_suffix(".stderr"))}
    output.with_suffix(".command.json").write_text(json.dumps(record, indent=2) + "\n")
    if any(text in result.stdout + result.stderr for text in DIAGNOSTICS):
        raise RuntimeError("Sanitizer diagnostic: " + str(output))
    if require_empty_output and (result.stdout or result.stderr):
        raise RuntimeError("Compile diagnostics/output: " + str(output))
    if expected_failure:
        if result.stdout or result.returncode != 1 or expected_failure not in result.stderr:
            raise RuntimeError("Negative did not reject at required semantic boundary: " + str(output))
    elif result.returncode != 0:
        raise RuntimeError("Command failed: " + str(output))
    elif require_empty_stderr and result.stderr:
        raise RuntimeError("Unexpected positive runtime diagnostic: " + str(output))
    return result, record



def compile_(sources, output, log, mode, *, defines=(), dynamic=False, arc=False, fixture=False):
    flags = BASE + (["-O0"] if mode == "O0" else ["-O2"])
    if mode == "fatal":
        flags += FATAL
    if arc:
        flags += ["-fobjc-arc"]
    if fixture:
        flags += ["-Wno-deprecated-declarations"]
    flags += ["-I", str(DEP)] + ["-D" + item + "=1" for item in defines]
    if dynamic:
        flags += ["-dynamiclib"]
    output.parent.mkdir(parents=True, exist_ok=True)
    execute(["clang++", *flags, *sources, "-framework", "Cocoa", "-o", output], log, require_empty_output=True)
    # Every own executable and module, including semantic mutants, is signed
    # and strictly verified before execution/import. Signing logs are retained;
    # codesign may report replacement of the linker's initial ad-hoc signature.
    execute(["codesign", "--force", "--sign", "-", output], log.parent / (log.name + "-sign"), require_empty_stderr=False)
    execute(["codesign", "--verify", "--strict", output], log.parent / (log.name + "-strict-signature"), require_empty_stderr=False)
    return identity(output)



def parse_result(result):
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise RuntimeError("Result is not a JSON object")
    return value



def replace_once(text, before, after):
    if text.count(before) != 1:
        raise RuntimeError("Mutant needle is not unique: " + before)
    return text.replace(before, after)



def source_profile(family, editor, mode, work, tree=OWN, expected_failure=None):
    cfg = FAMILIES[family]
    defines = (["VL_TEST_STEREO"] if family == "stereo_shaper" else [])
    if editor:
        defines.append(cfg["macro"])
    artifact = work / "test_lifetime"
    # Numerical CPP is an unchanged quoted dependency included by the fixture.
    compiled = compile_([tree / "test_lifetime.mm"], artifact, work / "compile", mode, defines=defines, arc=True)
    result, run = execute([artifact], work / "run", expected_failure=expected_failure)
    if expected_failure:
        return {"artifact": compiled, "run": run, "expected_rejection": expected_failure}
    value = parse_result(result)
    expected = {"status": "passed_own_Soft_Stereo_lifetime_contract", "family": cfg["label"],
                "pairs": 12, "instances": 24, "complete_caller_free": 8, "deleting": 8, "DestroyObject": 8,
                "allocation_failures": 2, "offmain_refusals": 36 if editor else 0,
                "attached_editors": 24 if editor else 0, "retained_view_cases": 24 if editor else 0,
                "live_peer_actions": 12 if editor else 0, "main_editor_cleanup_calls": 24 if editor else 0,
                "delay_ring_cleanups": 24 if family == "stereo_shaper" else 0,
                "borrowed_host_teardown_events": 0, "own_allocator_hooks": True,
                "original_images_loaded": False, "original_extra_destructor_equivalence": False,
                "full_plugin_equivalence": False}
    if value != expected:
        raise RuntimeError("Unexpected source lifetime result: " + str(work))
    return {"artifact": compiled, "run": run, "result": value}


def source_phase(work):
    results = []
    for family in FAMILIES:
        for editor in (False, True):
            values = []
            for mode in ("normal", "fatal", "O0"):
                directory = work / family / ("editor" if editor else "default") / mode
                row = source_profile(family, editor, mode, directory)
                row.update(family=family, editor=editor, mode=mode)
                results.append(row)
                values.append(row["result"])
            if values[1:] != values[:-1]:
                raise RuntimeError("Optimization/instrumentation result difference")
    negatives = []
    for family, cfg in FAMILIES.items():
        api = cfg["api"]
        variants = [
            ("complete-frees", False, "native", "void completeDestructor(Plugin* p){(void)finishLifetime(p);}",
             "void completeDestructor(Plugin* p){if(finishLifetime(p))::operator delete(static_cast<void*>(p));}",
             "Complete lifetime must retain caller raw storage"),
            ("numerical-omitted", False, "native", "  " + api + "_destroy(instance->numerical);", "  (void)instance->numerical;",
             "Numerical resource must be released exactly once"),
            ("deleting-retains", False, "native", "void deletingDestructor(Plugin* p){destroy(p);}",
             "void deletingDestructor(Plugin* p){(void)finishLifetime(p);}",
             "Deleting lifetime must release selected raw storage once"),
            ("worker-outer-guard-omitted", True, "native", "  if(!" + api + "_editor_main_thread())return false;", "",
             "Worker lifetime entered editor cleanup"),
            ("stale-callback-context", True, "editor", "v.callbacks={};" if family == "stereo_shaper" else "  v.callbacks = {};\n", "",
             "Retained view preserves numerical or host callback/context"),
            ("stale-slider-targets", True, "editor", "for(NSControl* control in v.sliders)control.target=nil;", "",
             "Retained control target remains"),
        ]
        if family == "stereo_shaper":
            variants += [
                ("stale-routing-targets", True, "editor", "v.send.target=nil;v.position.target=nil;", "",
                 "Retained routing control target remains"),
                ("invented-unregister", False, "native", "  vl_stereo_shaper_destroy(instance->numerical);",
                 "  notifyRouting(*instance,0);\n  vl_stereo_shaper_destroy(instance->numerical);",
                 "Cleanup delivered a borrowed-host teardown/routing event"),
            ]
        for name, editor, kind, before, after, expected in variants:
            directory = work / "negative" / family / name
            tree = directory / "source"
            tree.mkdir(parents=True, exist_ok=False)
            for file in ("test_lifetime.mm", "soft_clipper_native_abi.cpp", "stereo_shaper_native_abi.cpp", "soft_clipper_editor.mm", "stereo_shaper_editor.mm"):
                shutil.copyfile(OWN / file, tree / file)
            target = tree / (family + ("_native_abi.cpp" if kind == "native" else "_editor.mm"))
            target.write_text(replace_once(target.read_text(), before, after))
            row = source_profile(family, editor, "fatal", directory, tree, expected)
            row.update(family=family, mutant=name, mutated_source=identity(target), source_relative_path=str(target.relative_to(work)))
            negatives.append(row)
    return {"source_profiles": results, "fatal_semantic_negatives": negatives,
            "own_allocation_instrumentation_only": True, "original_images_loaded": False,
            "source_borrowed_host_policy_only": True, "application_registration_owner_known": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", required=True, choices=("source",))
    parser.add_argument("--work", required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() not in ("arm64", "aarch64"):
        raise RuntimeError("This source fixture requires macOS arm64")
    records = preflight()
    work = args.work.expanduser().resolve()
    if work == OWN or work in OWN.parents:
        raise RuntimeError("Work path must be a fresh isolated output directory")
    work.mkdir(parents=True, exist_ok=False)
    try:
        compiler, _ = execute(["clang++", "--version"], work / "compiler")
        result = source_phase(work)
        if preflight() != records:
            raise RuntimeError("Source bindings changed during replay")
        report = {"status": "passed_scoped_source_lifetime_recipe", "phase": args.phase,
                  "compiler": compiler.stdout, "results": result, "bound_inputs": records,
                  "extra_destructor_semantics": "own source C++ lifetime only",
                  "actual_application_registration_owner": False,
                  "original_extra_destructor_equivalence": False, "original_editor_parity": False,
                  "original_images_imported": False, "application_created": False,
                  "full_plugin_equivalence": False}
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": report["status"], "report": str(work / "result.json")}))
    except Exception as error:
        (work / "failure.json").write_text(json.dumps({"status": "failed_or_incomplete", "phase": args.phase,
                                                       "error": str(error), "full_plugin_equivalence": False}, indent=2) + "\n")
        raise


if __name__ == "__main__":
    main()
