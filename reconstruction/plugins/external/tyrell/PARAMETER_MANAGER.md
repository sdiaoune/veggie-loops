# Bounded TyrellN6 parameter manager

This independently written MIT component reconstructs the manager's scalar
write decision for the 92 published TyrellN6 descriptors. It uses the separately
accepted parameter-scale range source as a dependency. It is a prepared C API,
with caller-owned raw values and clock, rather than a native Tyrell C++ class,
audio engine, plugin factory or native preset initialization.

Public flag 1 decodes an index 0..91; flag 0 accepts one of those same internal
IDs. The actual map contains 33 type-0 integer controls and 59 type-1 float
controls. Integer writes use a single-precision addition of 0.5 followed by
`floorf`; the addition can itself round a value immediately below a half to the
next integer. Ranges describe controls but do not clamp writes. The manager
records the decoded ID before its getter, including equal-value suppression.
The getter's fallback is the converted new value and its flag is zero. Changed
values forward the internal ID, new value, flag zero and an unchanged float
clock. Positive and negative zero compare equal and suppress notification,
while preserving the previous storage's zero sign.

`VLTyrellParameterManager` is an independent, synchronous storage backend. Its
write result records the getter/notifier arguments and commits changed raw
values to its own array. This does not reconstruct the original notifier's
audio scheduling. Every operation on one state must be serialized. Finite raw
values in [-4096,4096], every finite float clock, nearest-even arithmetic and
gradual subnormals are the bounded contract. State and output bytes, including
partial overlaps, must be disjoint. Rejected calls preserve supplied state and
output bytes. Storage validity/alignment remains the caller's responsibility.

The extra prepared scalar API covers type 5 with the same floor rule and type
3 with an early ignored decision. No actual published type-3 or type-5 control
is claimed: that branch corpus uses a synthetic empty descriptor table. The
native meter-warning logger is excluded. Other byte types pass the raw value
through. Invalid NaN/Inf inputs are rejected by the new API and never sent to
the original.

Run `./reconstruction/plugins/external/tyrell/verify-parameter-manager.sh`.
`VL_TYRELL_MANAGER_WORK_DIR` selects a separate output tree. The script builds
the new library, an ASan/UBSan source fixture, and a signed Intel ASan/UBSan
native fixture. Only generated executables/libraries are signed. The original
installed binary is unmodified and not instrumented.

The native fixture pins the installed universal binary SHA-256
`a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54`
and checks actual manager method offsets 0x125630, 0x125780 and 0x1255b0 before
calling them. The actual factory creates the original instance; the fixture
compares all 92 real descriptor identities/types/ranges and public/internal
lookup pointers. The original map, setter, lookup and getter forwarding
methods execute unchanged. A controlled nested getter at slot 0x2d8 supplies
old values and records fallback/flag/last-ID ordering. A synthetic notifier at
slot 0x298 records both float arguments and commits the prepared values.
Target/clock pointers and the nested getter vtable are restored before the
original factory instance is destroyed. The synthetic descriptor table is
used only by the explicitly separate extra-type corpus.

The script writes a source/dependency/artifact-bound result manifest in its
private output tree. The maintained manifest records independent review of this prepared subset. Native audio-target behavior, complete state/presets,
GUI, real host clock, RT behavior, native class ABI, whole DSP and whole-plugin
equivalence remain unproved. No original machine code, assets or decompiler
text are distributed in this source.
