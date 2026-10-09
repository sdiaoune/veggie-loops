# Bounded 3x Osc preparation and voice handoff

This experimental own C++ factory prepares five coefficient groups before the
first voice. Tempo and group controls prepare coefficients immediately; PPQ
delivery stores the clock without changing previously prepared coefficients.
The first voice imports the prepared cache and its zero-curve history. Valid
version14 restore prepares defaults, including volume release -101, before its
payload. This module preserves those measured ordering rules.

Two independent runtime reviews accepted the preparation repair. The factory
also includes the separately reviewed complete/deleting lifetime split. The
combined public factory passed its own public replay in normal, fatal and O0
builds, including all 18 expected documents, five numerical mutants and five
summary guards. Current replay status is recorded in `verification.json`.

Run on macOS arm64 with Xcode command-line tools and the pinned FL Studio 2024
installation:

```sh
python3 reconstruction/plugins/generators/prevoice-preparation/verify_public.py
```

Use `--check-only` to verify source hashes without compiling or loading originals.
The wrapper creates a fresh ignored copy, runs normal/fatal ASan/UBSan/float-cast-
overflow/O0 recipes, five source mutants and five summary negatives, and compares
all 18 result documents with accepted scalars. Own products are signed and
strictly verified before use; installed originals remain unmodified. The lower
recipes require the wrapper's copied workspace and refuse optimized Python.

The measured tests cover 192 cache callback pairs, 352 handoff callback pairs,
142,080 cached words, 300,096 exact handoff audio floats and 705 malformed-source
state rejections per mode, plus the earlier active/prevoice regressions. The
immutable core implementation is included once by the factory and omitted from
separate link inputs. No original machine code, tables or presets are included.

Access is serialized across instances sharing tables/RNG. Rate8000..384000,
tempo(0,1000] and PPQ4..2^20 are bounded, nontrapping nearest-even contexts with
gradual underflow. The fresh measured context is44100 Hz/140 BPM/PPQ96; its
phase scaler is zero until rate delivery. The delivered phase scaler is distinct
from44100/rate. Zero volume release after restore inherits default preparation
history. Undefined native padding, borrowed pointers and synchronized phase words
are excluded from cache comparisons.

Fresh audio without rate delivery, arbitrary active controls/state/synchronization,
full phase-consumer fenv, original factory/class/GUI, application clock production,
VST/AU, real-time and whole-plugin equivalence remain unproved. Malformed original
reads are not executed; source atomic rejection differs from original reset-before-
read behavior. Keep the host, module, tables and caller-owned notes alive until
cleanup completes.
