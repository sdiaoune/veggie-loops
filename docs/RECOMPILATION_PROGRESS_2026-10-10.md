# Recompilation progress — 2026-10-10 UTC

Veggie Loops has a playable, independently written workstation. Complete FL Studio
and plugin reconstruction remains unfinished: **0 of 147 established obligations
have passed full recompilation and behavior verification**.

The checklist includes the application, 84 bundled effects, 49 bundled generators,
and **13 known third-party format entries: five AU, five VST2 and three VST3**.
Third-party entries include LABS, Purity, Tyrell, Vital, the FL Studio wrappers and
the discovered Adobe host-checker bundle. Discovery has unresolved filesystem
coverage, so these counts describe the established inventory.

This supplements the [earlier update](RECOMPILATION_UPDATE_2026-10-10.md). Earlier
reports remain historical snapshots.

| Work | Verified result | Remaining work |
| --- | --- | --- |
| LABS diagnostic helper | Ten preparation phases succeeded; an independently reviewed, signed arm64 helper was produced. Selected raw instruction topology and declared dependencies match. A repaired load controller passed two source reviews. | The original plugin has not been loaded by this helper. A concrete outer timeout guard and separate execution controls remain required. Factory, DSP, state, GUI and lifetime verification remain open. |
| Own sanitizer calibration | A debugger captured one controlled stop, a 64-byte PC read and a 32-byte stack read; independent review checked the recorded result. | No main breakpoint hit. Numeric stop IDs and an explicit asynchronous-state readback were not retained. The earlier timeout cause, live sanitizer binding and meter coverage remain unresolved. |
| Fast Dist diagnostic | Independent review checked the failed ownership-admission attempt and retained evidence. | The attempt refused before ownership approval or canonical checkpoints. The exact failed comparison field is unknown. Inner cleanup is uncertified; a later zombie snapshot does not repair it. |
| Intel Vial baseline | A pristine 3,069-file upstream source checkout and selected toolchain/filesystem snapshots were checked independently. A revised controller passed its input gate and one Xcode settings command exited successfully. | The first attempt misclassified virtual hash commitments. The revised attempt stopped at stream sealing because declared read caps exceeded the helper's limit; result publications also exceeded their cap. Independent review preserves both failures. No compiler or link phase was reached. |

The Vial baseline is upstream **1.0.6**; installed Vital formats are **1.0.7**.
Even a successful baseline build would leave version parity and two bundled
prebuilt Firebase archives unresolved. Filesystem checks establish declared file
contents; they do not certify every actual compiler, resource, linker or runtime
dependency read.

Implementation agents write to separate private areas. Independent reviewers do
not modify their candidates, and native attempts are serialized. Failed attempts
remain preserved; source review, helper compilation and bounded observations do
not promote a whole plugin to complete.

The published code consists of the original workstation and partial reconstruction
implementations. Commercial binaries, decompiler bodies, vendor assets and captured
runtime tables remain outside this repository. Full completion still requires the
format, factory, DSP, state/preset, host/audio, lifetime and applicable GUI checks in
the [reconstruction plan](PLUGIN_RECONSTRUCTION_PLAN.md).
