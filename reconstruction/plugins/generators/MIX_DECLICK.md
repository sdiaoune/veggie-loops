# Stereo accumulation and prepared declick primitives

These independent modules rebuild two stereo accumulation routines and the
prepared raised-cosine/linear declick arithmetic. They have new C adapters and
the explicit finite-value/buffer preconditions in their headers. They do not
implement the native plugin factory or connect all voice DSP.

`./reconstruction/plugins/generators/verify-gain-mix.sh` builds and replays an
independent dynamic library against the identity-matched macOS arm64 wrapper.
It checks 48,000 fixed/ramp cases, 45,099,172 float outputs, 16 alignment pairs,
source preservation and output guards. The observed native gain ramp advances
separate even/odd gains by twice the increment in eight-frame groups. Its
scalar remainder swaps the channel increments. The reconstruction deliberately
preserves this behavior and tests unequal increments at a three-frame boundary.

`./reconstruction/plugins/generators/verify-declick.sh` compares 10,000 prepared
64-frame table cases and 6,000 precomputed release cases, including waits,
released/unreleased state, partial tables, exhaustion and output guards. The
native generation comparison covers count64; other generation counts are an
independent generalization. The release fixture supplies the same model-made
table to both release routines, so it proves application rather than native
generation for those variable-length tables. The
native raised-cosine/linear preparation uses float vector arithmetic. REA also
verified that the installed arm64 DSP dependency forwards cosine/exponential
to Apple's `vvcosf`/`vvexpf` and scalar multiply/add to `vDSP_vsmul`/`vDSP_vsadd`.
The new source calls Accelerate directly. It contains no commercial DSP library
or copied native table. Both wrapper and native DSP dependency identities are
checked before the declick native fixture loads them.

Each script writes a sanitized verification manifest with exact source, rebuilt
artifact and native target hashes. These results apply to normal prepared calls
on the reviewed macOS platform. The declick generator allocates temporary
storage; allocation failure can throw through its thin C adapter and is outside
this arithmetic contract. Mode1/2, dynamic table caches, filters, native object
allocation, UI, host routing and whole Fruity/VST/AU equivalence remain open.
