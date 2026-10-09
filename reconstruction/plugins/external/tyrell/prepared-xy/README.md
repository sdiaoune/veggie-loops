# Prepared TyrellN6 XY consumer subset

This independently written C API reproduces a finite, prepared, empty-queue XY consumer. It is one reconstructed processing routine; the Tyrell sound engine, plugin factory, presets, editor and full VST/AU product remain unfinished. The installed original is required only for the macOS reference comparisons and is not included here.

The repair avoids raising floating-point flags when validating unused subnormal fields. It also evaluates the coordinate comparison before skipped targets, preserving the original exception behavior in optimized and unoptimized builds. Duplicate targets, shared cells and ordered clamps retain their measured behavior. See [the declared domain and history](REPAIR.md).

Two independent copied reviews passed the maintained normal, fatal sanitizer and unoptimized suites, all ten deliberately wrong variants, and separate reviewer tests. [Acceptance metadata](repaired-verification.json) binds their evidence and the published source. Source and harness sanitizers leave the installed original uninstrumented. Natural active XY, positive queues, native class/factory/state ownership, source audio, scheduling, GUI, real-time and whole-plugin equivalence remain unproved.

Run `python3 verify_public.py`. The helper verifies the published source hashes, copies the closure into a fresh ignored directory, and runs the native recipe there. It requires macOS, Xcode command-line tools, Python 3 and the pinned installed TyrellN6 VST; its Intel reference process requires Rosetta on Apple silicon. `VL_TYRELL_XY_PUBLIC_WORK` can select a new output directory. Generated reports and executables stay in that isolated copy.
