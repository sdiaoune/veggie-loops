# Purity prepared peak compressor

This MIT mathematical subset independently implements the inspected stereo
peak compressor process routine. It accepts a new caller-owned prepared state
record and updates its coefficient smoothing, gain and in-place audio. It is
not a native class or factory, parameter preparation, VST/AU or complete Purity
plugin. Reserved record bytes are carried through unchanged; no native assets,
machine-code bytes, presets or constructor implementation are embedded.

Run `bash reconstruction/plugins/external/purity/verify-peak.sh` on macOS arm64
with the identity-bound installed Purity VST binary. The script builds both the
independent library and fixture with AddressSanitizer and UndefinedBehaviorSanitizer.
The original reference is not sanitizer-instrumented. The fixture calls its
exported process method with controlled prepared numeric state; it does not
instantiate the original effect factory.

The maintained corpus compares 14,112 complete prepared state records and
5,625,216 stereo frames exactly. Its 12,816 repeated calls retain state across
new input blocks. Six sample rates span 8 kHz through 192 kHz. Blocks contain
0, 1, 3, 31, 64, 255, 512, 1024 or 8192 frames and cover coefficient movement
in both directions, stationary targets, compressor attack/recovery, signed zero,
subnormal inputs, guarded disjoint audio and exactly identical channel pointers.
The identical-pointer path preserves the native routine's ordered two writes.
Nonzero audio and state guards are checked after both original and rebuilt calls.
The new API also passes 47 atomic invalid-input checks and null-audio completion
at count zero; invalid original inputs are not called.

The bounded API requires finite sample rate [8000,192000], current/target
coefficient and gain fields [0,1], count 0..8192 and finite input audio [-4,4].
Callers provide valid storage of the documented size in the default floating-point
environment. State and audio storage must not overlap; partially overlapping
channels are rejected before any write. Output audio is in-place and can exceed
the allowed input range due to makeup gain. Callers supply each subsequent input
block within the input range; this is not a feedback loop or arbitrary floating
input equivalence proof.

Native constructor/setter preparation, compressor variants, complete effect
routing, realtime scheduling, host/project state, plugin factory, GUI and full
voice/audio integration remain unfinished.
