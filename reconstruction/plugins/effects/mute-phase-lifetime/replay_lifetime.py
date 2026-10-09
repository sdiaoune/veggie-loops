#!/usr/bin/env python3
"""Explicitly gated source/native recipe. Run only after a parent build lease.

The candidate is immutable: every artifact/log is written beneath a required
fresh --work directory. A source phase loads Cocoa only, never an original image.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

OWN = Path(__file__).resolve().parent
DEP = OWN / "dependencies"
ENGINE = Path("/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib")
ENGINE_SHA = "22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37"
FAMILIES = {
    "mute2": {"api": "vl_mute2", "macro": "VL_MUTE2_APPKIT_EDITOR", "label": "Mute 2", "bundle": "VL Mute 2", "parameters": 2400},
    "phase_inverter": {"api": "vl_phase_inverter", "macro": "VL_PHASE_INVERTER_APPKIT_EDITOR", "label": "Phase Inverter", "bundle": "VL Phase Inverter", "parameters": 1200},
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


def source_profile(family, editor, mode, work, tree=OWN, expected_failure=None):
    configuration = FAMILIES[family]
    defines = (["VL_TEST_PHASE"] if family == "phase_inverter" else [])
    if editor:
        defines.append(configuration["macro"])
    artifact = work / "test_lifetime"
    compiled = compile_([tree / "test_lifetime.mm", DEP / (family + "_plugin.cpp")], artifact,
                        work / "compile", mode, defines=defines, arc=True)
    result, run = execute([artifact], work / "run", expected_failure=expected_failure)
    if expected_failure:
        return {"artifact": compiled, "run": run, "expected_rejection": expected_failure}
    value = parse_result(result)
    expected = {"status": "passed_source_Mute_Phase_lifetime_contract", "family": configuration["label"],
                "pairs": 12, "complete_caller_free": 4, "deleting": 4, "DestroyObject": 4,
                "allocation_failures": 2, "offmain_refusals": 36 if editor else 0,
                "attached_editors": 12 if editor else 0, "retained_view_actions": 12 if editor else 0,
                "main_editor_cleanup_calls": 12 if editor else 0, "own_allocator_hooks": True,
                "original_images_loaded": False, "original_extra_destructor_equivalence": False,
                "full_plugin_equivalence": False}
    if value != expected:
        raise RuntimeError("Unexpected source lifetime result: " + str(work))
    return {"artifact": compiled, "run": run, "result": value}


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise RuntimeError("Mutant needle is not unique: " + before)
    return text.replace(before, after)


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
            ("complete-frees", False, "native", "void completeDestructor(Plugin* plugin){(void)finishLifetime(plugin);}",
             "void completeDestructor(Plugin* plugin){destroy(plugin);}",
             "Complete lifetime must retain caller raw storage"),
            ("numerical-omitted", False, "native", "  " + api + "_destroy(instance->numerical);", "  (void)instance->numerical;",
             "Selected numerical resource must be released exactly once"),
            ("deleting-retains", False, "native", "void deletingDestructor(Plugin* plugin){destroy(plugin);}",
             "void deletingDestructor(Plugin* plugin){(void)finishLifetime(plugin);}",
             "Deleting lifetime must release selected raw storage once"),
            ("worker-outer-guard-omitted", True, "native", "  if(!" + api + "_editor_main_thread())return false;", "",
             "Worker lifetime entered editor cleanup"),
            ("stale-callback-context", True, "editor", "view.callbacks={};", "",
             "Retained view still owns ended numerical/context/control access"),
        ]
        for name, editor, kind, before, after, expected in variants:
            directory = work / "negative" / family / name
            tree = directory / "source"
            tree.mkdir(parents=True, exist_ok=False)
            for file in ("test_lifetime.mm", "mute2_native_abi.cpp", "phase_inverter_native_abi.cpp", "mute2_editor.mm", "phase_inverter_editor.mm"):
                shutil.copyfile(OWN / file, tree / file)
            target = tree / (family + ("_native_abi.cpp" if kind == "native" else "_editor.mm"))
            text = target.read_text()
            if name == "complete-frees":
                # destroy is defined later; keep the mutant self-contained and
                # change only this complete entry's erroneous raw deallocation.
                after = "void completeDestructor(Plugin* plugin){if(finishLifetime(plugin))::operator delete(static_cast<void*>(plugin));}"
            target.write_text(replace_once(text, before, after))
            row = source_profile(family, editor, "fatal", directory, tree, expected)
            row.update(family=family, mutant=name, mutated_source=identity(target), source_relative_path=str(target.relative_to(work)))
            negatives.append(row)
    return {"source_profiles": results, "fatal_semantic_negatives": negatives,
            "own_allocation_instrumentation_only": True, "original_images_loaded": False}


def native_phase(work):
    if identity(ENGINE)["sha256"] != ENGINE_SHA:
        raise RuntimeError("Installed engine identity changed")
    results = []
    for family, cfg in FAMILIES.items():
        for mode in ("normal", "fatal"):
            modules = {}
            for editor in (False, True):
                directory = work / family / mode / ("editor" if editor else "default")
                if editor:
                    module = directory / "NativeEditor.dylib"
                else:
                    module = directory / cfg["bundle"] / (cfg["bundle"] + "_X64.dylib")
                sources = [DEP / (family + "_plugin.cpp"), OWN / (family + "_native_abi.cpp")]
                if editor:
                    sources.append(OWN / (family + "_editor.mm"))
                compiled = compile_(sources, module, directory / "compile-module", mode,
                                    defines=[cfg["macro"]] if editor else [], dynamic=True, arc=editor)
                modules[editor] = module
                kind = "native_editor" if editor else "engine_loader"
                executable = directory / ("test_" + kind)
                # Match the published editor fixture's ARC policy: Mute uses ARC,
                # Phase and the two loader fixtures use their original MRC policy.
                fixture_arc = editor and family == "mute2"
                test = compile_([OWN / ("test_" + family + "_" + kind + ".mm")], executable,
                                directory / "compile-fixture", mode, arc=fixture_arc, fixture=True)
                logical = module if editor else module.with_name(cfg["bundle"] + ".dylib")
                result, run = execute([executable, ENGINE, logical], directory / "run")
                value = parse_result(result)
                if value.get("status") != "passed" or value.get("full_plugin_equivalence") is not False:
                    raise RuntimeError("Native fixture did not report scoped success")
                if not editor and (value.get("callback_slots_exercised") != 20 or value.get("state_saves") != 1200 or value.get("state_restores") != 240 or value.get("parameter_calls") != cfg["parameters"] or value.get("stereo_frames") != 140700):
                    raise RuntimeError("Native loader fixture counts changed")
                if editor:
                    expected = {"status": "passed", "independently_written_appkit_editor": True,
                                "actual_engine_plugin_and_host_adapters": True,
                                "concurrent_first_attachment_worker_hints_checked": True,
                                "worker_tick_idle_skipped_gui": True, "off_main_destroy_preserves_state": True,
                                "control_changes": 2 if family == "mute2" else 3,
                                "hints": 3 if family == "mute2" else 4,
                                "resize_notifications": 2, "source_gui_resources_copied": False,
                                "actual_fl_application_created": False, "full_plugin_equivalence": False}
                else:
                    expected = {"status": "passed", "intact_original_engine_loaded": True,
                                "actual_engine_dll_loader_accepted_rebuilt_plugin": True,
                                "actual_engine_wrapper_allocated_and_freed": True,
                                "callback_slots_exercised": 20, "state_saves": 1200,
                                "state_restores": 240, "short_read_preserves_state": True,
                                "parameter_calls": cfg["parameters"], "stereo_frames": 140700,
                                "fl_application_host_created": False, "full_plugin_equivalence": False}
                if value != expected:
                    raise RuntimeError("Native positive JSON differs from exact expected result")
                results.append({"family": family, "editor": editor, "mode": mode, "module": compiled,
                                "fixture": test, "run": run, "result": value})
            if family == "phase_inverter":
                directory = work / family / mode / "real-stream"
                executable = directory / "test_engine_stream"
                test = compile_([OWN / "test_phase_inverter_engine_stream.mm"], executable,
                                directory / "compile-fixture", mode, fixture=True)
                result, run = execute([executable, ENGINE, modules[False]], directory / "run")
                value = parse_result(result)
                expected = {"status": "passed", "actual_engine_memory_and_stream_classes": True,
                            "actual_engine_plugin_wrapper": True, "completion_store_bits": 32,
                            "adjacent_count_sentinel_preserved": True, "hresult_return_bits": 32,
                            "actual_provider_invalid_pointer_error_checked": True,
                            "state_saves": 128, "state_restores": 128,
                            "failed_hresult_full_count_rejections": 2,
                            "first_and_second_read_failures_checked": True,
                            "application_host_created": False, "full_plugin_equivalence": False}
                if value != expected:
                    raise RuntimeError("Phase real stream positive JSON differs")
                results.append({"family": family, "mode": mode, "real_stream": True, "fixture": test, "run": run, "result": value})
    return {"native_fixtures": results, "engine": identity(ENGINE), "original_code_instrumented": False,
            "original_extra_destructors_called": False, "new_Mute_real_stream_replay": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", required=True, choices=("source", "native"))
    parser.add_argument("--work", required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() not in ("arm64", "aarch64"):
        raise RuntimeError("This measured fixture requires macOS arm64")
    records = preflight()
    work = args.work.expanduser().resolve()
    if work == OWN or work in OWN.parents:
        raise RuntimeError("Work path must be a fresh isolated output directory")
    work.mkdir(parents=True, exist_ok=False)
    try:
        compiler, _ = execute(["clang++", "--version"], work / "compiler")
        result = source_phase(work) if args.phase == "source" else native_phase(work)
        post = preflight()
        if post != records:
            raise RuntimeError("Source bindings changed during replay")
        report = {"status": "passed_scoped_" + args.phase + "_lifetime_recipe", "phase": args.phase,
                  "compiler": compiler.stdout, "results": result, "bound_inputs": records,
                  "extra_destructor_semantics": "own source/C++ lifetime only",
                  "original_extra_destructor_equivalence": False, "original_editor_parity": False,
                  "application_created": False, "full_plugin_equivalence": False}
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": report["status"], "report": str(work / "result.json")}))
    except Exception as error:
        (work / "failure.json").write_text(json.dumps({"status": "failed_or_incomplete", "phase": args.phase,
                                                       "error": str(error), "full_plugin_equivalence": False}, indent=2) + "\n")
        raise


if __name__ == "__main__":
    main()
