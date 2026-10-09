# Prepared native processing-mode delivery

These independently written replay fixtures execute the installed engine's
unchanged processing-mode provider and original Fast Dist receiver. They do
not reconstruct the provider implementation or the distortion selector writers.
The two fixtures are byte-identical to separately reviewed private sources;
the build recipe changes only its project/output paths and basename.

The native provider locks a supplied lock, stores an interpolation index/point
count and traverses a supplied recipient list. Its original recipient resolver
and retained-interface dispatcher send ID1/index0 with signed32 mode bits OR
point-count<<8. Lock, list and interface callbacks are controlled; actual
original Fast Dist factory, VFT, dispatcher, controls and DSP remain intact.
The original factory receives a prepared Pascal host/path manager rather than
an application-owned host. A second recipient independently captures packets.

Processing-mode flags do not select Fast Dist's DistWave branch in these
observations. Mode0 with independently supplied selector1 still interpolates.
Static setup writes selector1 before delivery; static cleanup sends mode0
before clearing selector0. Those complete writer lifecycles are not invoked.
Deriving quality from mode bit16 fails a separate critic control.

Each normal and fatal ASan/UBSan/float-cast-overflow replay covers420 provider
calls across ten interpolation indices, seven signed modes, three tail bytes
and two artificial selector values. The original receiver replay checks2,100
control calls,840 balanced retains,163,880 independently generated table
entries and143,240 exact audio floats. Opposite quality differs in10,329 sample
comparisons. Both branches, aliasing, input preservation and output guards
are checked. The separate critic's fixed-input420 cases compare215,880 floats;
that extension and the root signed-packet negative are private hash references,
not reproduced by this ordinary recipe.

Run from the project root:

    sh reconstruction/plugins/effects/quality-provider/verify.sh

The recipe requires the exact pinned installed FL Studio2024 arm64 binaries
and writes only ignored .tools/plugin-work/effects/quality-provider-public.
Only new fixtures and the independent numerical model are instrumented;
installed originals remain unmodified and uninstrumented. Both full JSON
outputs in both modes must succeed before the builder emits verification.
A fresh checkout does not require ignored private analysis or captured data.

Six selected globals are restored and read back before original destruction;
restoration guards also reapply at scope exit. The original table initializer
runs, but its table/global changes and unlisted TLS/class state are not wholly
snapshotted. Only32 original numerical class bytes and prepared object guards
are compared. Ordinary original factory/destructor side effects remain possible.
Nearest-even gradual nontrapping arithmetic is required; general FP exception
status, genuine selector production, real locks/recipient class construction,
HQ UI/persistence binding, full factory/state/GUI/application and real-time or
whole-plugin equivalence remain unfinished. No original code/assets/presets
are included. The separate CPP host ordinal24 mapping is not part of this proof.
