# Reconstruction update — 2026-10-10 UTC

The completion checklist includes FL Studio's bundled plugins and the established
third-party AU, VST2 and VST3 installations. It currently tracks **147 obligations,
with zero fully recompiled and verified components**. Filesystem coverage remains
incomplete, so this is an established inventory rather than an exhaustive count.

| Group | Tracked | Fully verified |
| --- | ---: | ---: |
| FL Studio application | 1 | 0 |
| Bundled effects | 84 | 0 |
| Bundled generators | 49 | 0 |
| Installed third-party formats | 13 | 0 |
| Total | 147 | 0 |

The 13 external entries comprise five AU, five VST2 and three VST3 formats. The
review checks each binary's architecture and bundle version separately. This
includes the FL Studio wrappers, LABS, Purity, Tyrell, Vital and the discovered
Adobe host-checker bundle. A result for one format or architecture does not finish
the other entries.

Since the [previous checkpoint](RECOMPILATION_CHECKPOINT_2026-10-10.md):

- The workstation's revised last-window close proposal passed two source reviews
  and compiled successfully in a private build with no observed warnings. An
  independent reviewer checked the build evidence. Actual Cancel, Save, save-error,
  delegate forwarding, tabbing and window lifecycle behavior still require GUI
  testing. This proposal has not been integrated into the published application.
- The independently written CPU probe completed all ten preparation and execution
  phases. Its measured packet contains 24 typed fields. Raw binary checks confirm
  that the entry calls the defined register-capture function first. Independent
  review accepts only the recorded instruction and register subset. This run did
  not load LABS or establish general native ABI, floating-point, dependency or
  initializer readiness.
- A separate 120-second diagnostic run of the unchanged sanitizer meter product
  timed out. It emitted only an AddressSanitizer initialization line and no standard
  output. The failure and recorded process closure passed independent review;
  the cause and sanitizer coverage remain unresolved. A minimal calibration
  program has been proposed to investigate this separately.
- The Fast Dist debugger attempt passed its startup policy check, then refused an
  unsupported LLDB cache setting before creating or launching the test target.
  Independent review preserves this as a failed host attempt. A version-specific
  source revision preserves the two supported setting checks and explicitly leaves
  the unavailable cache policy uncertified. The canonical lifetime failure remains
  unresolved.
- The revised static-analysis and runtime controllers preserve malformed or
  overlapping input declarations in their audit records. Source acceptance of
  these repairs does not establish successful analysis or plugin reconstruction.

The Intel Vial rebuild proposal passed two source reviews. It uses pinned upstream
**Vial 1.0.6** source; the three installed **Vital 1.0.7** formats are Intel binaries.
The version difference remains unresolved. The proposed private AU/VST3 build
disables seven installed-plugin validation scripts in a separate project copy and
preserves the upstream C++/DSP. A fresh verified source checkout, concrete build
controller, toolchain and resource checks, actual build and independent review
are still required. Two bundled Firebase archives remain prebuilt dependencies.

The public repository contains independently written workstation and reconstruction
source. Complete plugin factories, format wrappers, DSP, presets/state, repeated
lifetime, host/audio and required GUI behavior remain unfinished across the
inventory. Completion requirements are recorded in the
[reconstruction plan](PLUGIN_RECONSTRUCTION_PLAN.md).

Commercial binaries, decompiler bodies, captured runtime tables and vendor assets
remain outside this publication. Analysis and implementation agents use distinct
write paths; independent reviewers do not edit the candidates they review. Native
execution is serialized, and failed attempts are preserved before revised attempts.
