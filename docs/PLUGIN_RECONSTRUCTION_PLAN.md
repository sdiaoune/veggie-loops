# Plugin reconstruction work

This work is in progress. The playable workstation's original instruments and mixer do not establish recompilation of FL Studio or installed commercial plugins.

The requested scope includes the installed FL Studio build, its bundled native plugins and engines, and third-party installed VST, VST3 and AU plugins. Inventory records retain exact paths, versions, architectures and binary digests locally under ignored `analysis/plugins/`. Duplicate wrappers and shared engines must be distinguished from independent product implementations.

## Exclusive ownership

| Owner | Writable paths | Responsibility |
| --- | --- | --- |
| Root | `reconstruction/plugins/catalog.py`, `reconstruction/plugins/STATUS.md`, `reconstruction/plugins/common/`, `reconstruction/plugins/external/`, `docs/PLUGIN_RECONSTRUCTION_PLAN.md`, root repository files, `analysis/plugins/inventory/`, `.tools/plugin-work/sdk/`, `.tools/plugin-work/vital/`, `.tools/plugin-work/common/`, `.tools/plugin-work/external/` | Global inventory, shared ABI, integration, source builds, scheduling |
| Effects agent | `reconstruction/plugins/effects/`, `analysis/plugins/effects/`, `.tools/plugin-work/effects/` | Bundled effect analysis and verified reconstructions |
| Generators agent | `reconstruction/plugins/generators/`, `analysis/plugins/generators/`, `.tools/plugin-work/generators/` | Bundled generator analysis and verified reconstructions |
| Independent critic | `reconstruction/plugins/review/`, `analysis/plugins/review/`, `.tools/plugin-work/review/` | Acceptance gates and independent evidence checks |

Agents may read other owners' outputs and send findings, but may not edit them. Package/app changes and Git operations belong to root. Analysis processes, snapshots, temporary binaries and output directories must be separate. Builders cross-review each other's work after submitting their own evidence. Shared APIs require root integration.

## Completion gates

Every in-scope component must have all applicable gates supported by reproducible evidence:

1. Exact source binary identity, architecture and dependencies recorded.
2. Entry points, state, parameters, processing, GUI and host interactions accounted for; decompilation coverage measured rather than inferred from exports.
3. Independently reconstructed source, or properly licensed corresponding upstream source, builds successfully.
4. A native plugin module loads through the correct FL, VST, VST3 or AU ABI.
5. Audio/MIDI processing, automation and relevant edge cases compare against the original with stated tolerances.
6. Presets and state roundtrip, and repeated construction/teardown are verified.
7. GUI and host integration work where required.
8. An independent critic accepts the evidence and any findings have been repaired and retested.

A tiny DSP routine, an export inventory, a host using the original binary, or a source build of a different version cannot satisfy whole-plugin completion. Unknown or absent evidence fails its gate. Captured target code, binaries, factory payloads and commercial assets remain local; original reconstruction code and external source licenses stay distinct.

## Iteration

Inventory → assign an exclusive component → analyze → reconstruct/build → test against the original → independent critique → repair → rerun the affected checks. Record every unresolved component and continue with work that can progress. Full recompilation is complete only when all in-scope components meet the gates; the ledger must remain incomplete otherwise.
