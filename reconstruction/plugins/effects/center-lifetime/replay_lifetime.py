"""Prepared Center recipe; execute only under a fresh root serial-slot lease."""
import sys
if sys.flags.optimize:
    raise SystemExit("Optimized Python is unsupported: Center verification must fail closed")
import os
if os.environ.get("VL_CENTER_PUBLIC_EXECUTION_COPY") != "1":
    raise SystemExit("Run verify.py in its fresh copied workspace.")
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

OWN = Path(__file__).resolve().parent
ROOT = OWN.parents[3]
SHARED = ROOT / "reconstruction/plugins/effects"
ENGINE = Path("/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib")
ENGINE_SHA = "22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37"
BASE = ["clang++", "-arch", "arm64", "-std=c++20", "-fno-fast-math", "-ffp-contract=off",
        "-Wall", "-Wextra", "-Werror", "-I", str(SHARED), "-framework", "Cocoa"]
FATAL = ["-fsanitize=address,undefined,float-cast-overflow", "-fno-sanitize-recover=all", "-fno-omit-frame-pointer"]
DIAGNOSTICS = ("Sanitizer", "runtime error:", "UndefinedBehavior")

def identity(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return {"sha256": h.hexdigest(), "bytes": path.stat().st_size}

def preflight():
    path = OWN / "candidate-source.json"
    candidate_identity = identity(path)
    records = json.loads(path.read_text())["records"]
    seen = set()
    for record in records:
        relative = Path(record["path"])
        if relative.is_absolute() or ".." in relative.parts or str(relative) in seen:
            raise RuntimeError("Invalid or duplicate frozen input path")
        seen.add(str(relative))
        if identity(ROOT / relative) != {key: record[key] for key in ("sha256", "bytes")}:
            raise RuntimeError("Frozen input changed: " + str(relative))
    return {"candidate": candidate_identity, "records": records}

def execute(argv, log, *, empty_output=False, allow_stderr=False, negative=None):
    log.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, ASAN_OPTIONS="halt_on_error=1:abort_on_error=1:detect_leaks=0",
               UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1")
    result = subprocess.run([str(a) for a in argv], capture_output=True, env=env)
    stdout, stderr = log.with_suffix(".stdout"), log.with_suffix(".stderr")
    stdout.write_bytes(result.stdout)
    stderr.write_bytes(result.stderr)
    command = {"argv": [str(a) for a in argv], "exit_code": result.returncode,
               "stdout": identity(stdout), "stderr": identity(stderr)}
    log.with_suffix(".command.json").write_text(json.dumps(command, indent=2) + "\n")
    text = (result.stdout + result.stderr).decode("utf8", errors="replace")
    if any(item in text for item in DIAGNOSTICS):
        raise RuntimeError("Diagnostic rejects replay: " + str(log))
    if empty_output and (result.stdout or result.stderr):
        raise RuntimeError("Compilation emitted diagnostics: " + str(log))
    if negative is not None:
        if result.returncode != 1 or result.stdout or negative.encode() not in result.stderr:
            raise RuntimeError("Negative missed required semantic rejection: " + str(log))
    elif result.returncode != 0 or (result.stderr and not allow_stderr):
        raise RuntimeError("Positive command failed or emitted diagnostics: " + str(log))
    return result, command

def build(sources, output, mode, *, defines=(), arc=False, fixture=False, dynamic=False):
    flags = BASE + (["-O0"] if mode == "O0" else ["-O2"])
    if mode == "sanitized": flags += FATAL
    if arc: flags += ["-fobjc-arc"]
    if fixture: flags += ["-Wno-deprecated-declarations"]
    flags += ["-D" + d + "=1" for d in defines]
    if dynamic: flags += ["-dynamiclib"]
    output.parent.mkdir(parents=True, exist_ok=True)
    execute([*flags, *sources, "-o", output], output.parent / (output.stem + "-compile"), empty_output=True)
    execute(["codesign", "--force", "--sign", "-", output], output.parent / (output.stem + "-sign"), allow_stderr=True)
    execute(["codesign", "--verify", "--strict", output], output.parent / (output.stem + "-strict-signature"))
    architecture, _ = execute(["lipo", "-archs", output], output.parent / (output.stem + "-architecture"))
    if architecture.stdout.decode().strip() != "arm64":
        raise RuntimeError("Unexpected executable/module architecture")
    return identity(output)

def run_exact(executable, arguments, log, expected):
    result, command = execute([executable, *arguments], log)
    value = json.loads(result.stdout)
    if value != expected:
        raise RuntimeError("Positive JSON differs from exact expected result: " + str(log))
    return {"result": value, "run": command}

def source_phase(work):
    results, per_variant = [], {}
    for mode in ("normal", "sanitized", "O0"):
        for variant in ("plain", "editor-disabled", "editor-enabled"):
            directory = work / "source" / mode / variant
            defines = [] if variant == "plain" else ["VL_TEST_CENTER_EDITOR_VARIANT"]
            editor = variant == "editor-enabled"
            if editor: defines.append("VL_CENTER_APPKIT_EDITOR")
            executable = directory / "test_lifetime"
            artifact = build([OWN / "test_lifetime.mm", SHARED / "center_plugin.cpp"], executable,
                             mode, defines=defines, arc=True, fixture=True)
            expected = {"status": "passed_source_Center_lifetime_contract", "pairs": 12,
                        "complete_caller_free": 4, "deleting": 4, "DestroyObject": 4,
                        "allocation_failures": 2, "offmain_refusals": 24 if editor else 0,
                        "attached_editors": 12 if editor else 0, "retained_view_actions": 12 if editor else 0,
                        "own_allocator_hooks": True, "original_images_loaded": False,
                        "original_extra_destructor_equivalence": False, "full_plugin_equivalence": False}
            row = run_exact(executable, [], directory / "lifetime", expected)
            row.update(mode=mode, variant=variant, artifact=artifact)
            results.append(row)
            per_variant.setdefault(variant, []).append(row["result"])
    for values in per_variant.values():
        if values[1:] != values[:-1]: raise RuntimeError("Source optimization/instrumentation results differ")
    cases = [
        ("complete-frees", "void completeDestructor(Plugin *p) { (void)finishLifetime(p); }",
         "void completeDestructor(Plugin *p) { if(finishLifetime(p))::operator delete(static_cast<void*>(p)); }",
         "Complete lifetime must retain caller raw storage", False),
        ("numerical-leak", "  vl_center_destroy(i->numerical);", "  /* deliberately omitted cleanup */",
         "Selected numerical resource must be released exactly once", False),
        ("deleting-retains", "void deletingDestructor(Plugin *p) { destroy(p); }",
         "void deletingDestructor(Plugin *p) { (void)finishLifetime(p); }",
         "Deleting lifetime must release selected raw storage once", False),
        ("worker-enters-editor", "  if (!vl_center_editor_main_thread())\n    return false;\n", "",
         "Worker lifetime entered editor cleanup", True)]
    negatives = []
    for name, before, after, expected, editor in cases:
        directory = work / "mutants" / name
        directory.mkdir(parents=True, exist_ok=False)
        cpp = "center_native_editor_candidate.cpp" if editor else "center_native_abi.cpp"
        source = (OWN / cpp).read_text()
        if source.count(before) != 1: raise RuntimeError("Mutant needle is not unique: " + name)
        changed = directory / cpp
        changed.write_text(source.replace(before, after))
        fixture = directory / "test_lifetime.mm"
        shutil.copy2(OWN / "test_lifetime.mm", fixture)
        defines = ["VL_TEST_CENTER_EDITOR_VARIANT", "VL_CENTER_APPKIT_EDITOR"] if editor else []
        executable = directory / "test_lifetime"
        artifact = build([fixture, SHARED / "center_plugin.cpp"], executable, "sanitized",
                         defines=defines, arc=True, fixture=True)
        _, rejection = execute([executable], directory / "rejection", negative=expected)
        negatives.append({"name": name, "source": identity(changed), "artifact": artifact,
                          "rejection": rejection, "expected_semantic_diagnostic": expected})
    return {"positive_profiles": results, "fatal_semantic_negatives": negatives,
            "original_images_loaded": False, "original_extra_destructor_equivalence": False,
            "full_plugin_equivalence": False}

LOADER_EXPECTED = {"status": "passed", "intact_original_engine_loaded": True,
    "actual_engine_dll_loader_accepted_rebuilt_plugin": True, "actual_engine_wrapper_allocated_and_freed": True,
    "callback_slots_exercised": 20, "state_saves": 1200, "state_restores": 240,
    "failed_read_preserves_state": True, "parameter_calls": 1200, "stereo_frames": 140700,
    "fl_application_host_created": False, "full_plugin_equivalence": False}
STREAM_EXPECTED = {"status": "passed", "actual_engine_memory_and_stream_classes": True,
    "actual_engine_plugin_wrapper": True, "completion_store_bits": 32, "adjacent_count_sentinel_preserved": True,
    "hresult_return_bits": 32, "actual_provider_invalid_pointer_error_checked": True,
    "state_saves": 128, "state_restores": 128, "failed_hresult_full_count_rejections": 2,
    "short_count_success_rejections": 2, "two_four_byte_transfers_checked": True, "filter_history_preserved": True,
    "application_host_created": False, "full_plugin_equivalence": False}
EDITOR_EXPECTED = {"status": "passed", "independently_written_appkit_editor": True,
    "actual_engine_plugin_and_host_adapters": True, "concurrent_first_attachment_worker_hints_checked": True,
    "concurrent_render_reattach_cycles": 128, "filter_display_cases": 65, "worker_tick_idle_skipped_gui": True,
    "off_main_destroy_preserves_state": True, "control_changes": 2, "hints": 3, "resize_notifications": 129,
    "source_gui_resources_copied": False, "actual_fl_application_created": False, "full_plugin_equivalence": False}

def native_phase(work):
    results = []
    for mode in ("normal", "sanitized"):
        for variant in ("plain", "editor-disabled", "editor-enabled"):
            directory = work / "native" / mode / variant
            cpp = "center_native_abi.cpp" if variant == "plain" else "center_native_editor_candidate.cpp"
            editor = variant == "editor-enabled"
            defines = ["VL_CENTER_APPKIT_EDITOR"] if editor else []
            module = directory / "VL Center" / "VL Center_X64.dylib"
            sources = [OWN / cpp, SHARED / "center_plugin.cpp"]
            if editor: sources.append(SHARED / "center_editor.mm")
            module_identity = build(sources, module, mode, defines=defines, arc=editor, dynamic=True)
            fixtures = [("test_center_native_editor.mm", EDITOR_EXPECTED)] if editor else [
                ("test_center_engine_loader.mm", LOADER_EXPECTED), ("test_center_engine_stream.mm", STREAM_EXPECTED)]
            for fixture, expected in fixtures:
                stem = Path(fixture).stem
                executable = directory / stem
                artifact = build([OWN / fixture], executable, mode, fixture=True)
                target = module.parent / "VL Center.dylib" if "loader" in stem else module
                row = run_exact(executable, [ENGINE, target], directory / stem, expected)
                row.update(mode=mode, variant=variant, fixture=fixture, module=module_identity, artifact=artifact)
                results.append(row)
    return {"positive_profiles": results, "source_and_harness_fatal_in_sanitized_modes": True,
            "installed_engine_instrumented": False, "original_extra_destructors_called": False,
            "original_extra_destructor_equivalence": False, "full_plugin_equivalence": False}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("source", "native"))
    parser.add_argument("--work", required=True, type=Path)
    args = parser.parse_args()
    if os.environ.get("VL_CENTER_LIFETIME_SLOT_GRANTED") != args.phase:
        raise RuntimeError("Root serial slot grant must match the requested source/native phase")
    if platform.system() != "Darwin" or platform.machine() not in ("arm64", "aarch64"):
        raise RuntimeError("Center fixtures require macOS arm64")
    inputs = preflight()
    engine_identity = None
    if args.phase == "native":
        engine_identity = identity(ENGINE)
        if engine_identity["sha256"] != ENGINE_SHA:
            raise RuntimeError("Installed engine identity differs before native replay")
    work = args.work.expanduser().resolve()
    if work == OWN or work in OWN.parents:
        raise RuntimeError("Work must be a fresh isolated output directory")
    work.mkdir(parents=True, exist_ok=False)
    try:
        compiler, _ = execute(["clang++", "--version"], work / "compiler")
        results = source_phase(work) if args.phase == "source" else native_phase(work)
        if preflight() != inputs: raise RuntimeError("Frozen inputs changed during replay")
        if engine_identity is not None and identity(ENGINE) != engine_identity:
            raise RuntimeError("Installed engine changed during replay")
        artifacts = [{"path": str(p), **identity(p)} for p in sorted(work.rglob("*")) if p.is_file()]
        report = {"status": "passed_scoped_Center_" + args.phase + "_lifetime_recipe", "phase": args.phase,
            "compiler": compiler.stdout.decode(), "bound_inputs": inputs, "engine": engine_identity,
            "results": results, "artifacts": artifacts, "source_extra_destructor_lifetime_only": True,
            "original_extra_destructor_equivalence": False, "application_created": False,
            "original_Center_GUI_names_or_events_equivalence": False, "full_plugin_equivalence": False}
        (work / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": report["status"], "report": str(work / "verification.json")}))
    except Exception as error:
        (work / "failure.json").write_text(json.dumps({"status": "failed_or_incomplete", "phase": args.phase,
            "error": str(error), "full_plugin_equivalence": False}, indent=2) + "\n")
        raise

if __name__ == "__main__":
    main()
