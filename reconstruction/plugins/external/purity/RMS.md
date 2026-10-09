# Purity prepared RMS-named compressor

This MIT mathematical subset independently implements the inspected RMS-named
compressor process routine. Its detector is a one-pole follower of the mean
absolute stereo level, scaled by32768. It does not square samples or take a
square root. The rate coefficient is rounded as `(rate * 0.000333333f) * 0.001f`.
Coefficient smoothing, reduction, recovery and makeup follow the inspected
routine's operation order.

The new72-byte caller-owned record extends the companion peak record with the
detector and a reserved word. It is a prepared mathematical ABI, not a native
class/factory, constructor, parameter preparation or full Purity plugin. Native
assets, machine-code bytes and constructor source are not embedded.

Run `bash reconstruction/plugins/external/purity/verify-rms.sh` on macOS arm64
with the identity-bound installed Purity VST binary. Both the rebuilt library
and standalone fixture are compiled with AddressSanitizer and
UndefinedBehaviorSanitizer. The installed commercial reference is not
sanitizer-instrumented. The fixture directly invokes its exported process
method with controlled prepared state, without creating a native effect factory.

The maintained corpus compares14,112 complete state records and5,625,216
stereo frames exactly, including12,816 retained-state calls. It covers six
sample rates from8kHz to192kHz, zero and nonzero blocks through8192frames,
coefficient movement in both directions, unchanged targets, detector zero,
maximum and randomized histories, attack/recovery, signed-zero/subnormal audio,
guarded disjoint and identical channels. The identical-channel path preserves
the native ordered writes. All nonzero state and audio guards are checked after
both implementations. The new API also passes51 atomic invalid-argument cases
and null-audio completion at count zero. Invalid original inputs are not called.

The peak routine's documented domains/storage rules apply, with an additional
finite detector in[0,131072]. Each subsequent input block is freshly bounded
in[-4,4]; makeup output can exceed this input range. The prepared record must
outlive processing and the caller serializes its access. Tests establish this
finite corpus, not arbitrary state/float, threading or realtime equivalence.

Native constructor/setter preparation, the complete effects chain and voice
integration, host/project state, plugin factory, UI, MIDI and VST/AU hosting
remain unfinished.
