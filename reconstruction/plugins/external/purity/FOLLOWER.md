# Purity envelope follower primitive

This independently compiled mathematical subset updates a caller-owned32-byte
envelope follower. It reproduces the inspected attack, decay, sustain and
release block transition math using the separately generated259-float curve.
It is MIT source, contains no target assets or machine-code bytes, and is not
a native Purity factory, voice pipeline, VST/AU, editor or state loader.

Run `bash reconstruction/plugins/external/purity/verify-follower.sh` on macOS
arm64 with the identity-bound installed Purity VST binary. The script builds
the new library and fixture with AddressSanitizer and UndefinedBehaviorSanitizer.
The commercial reference itself is not sanitizer-instrumented. Its local
follower procedure is called by an address bound to the exported curve helper
and the verified universal binary identity; native code stays in the installed
file and is neither modified nor copied into this source.

The maintained corpus compares 970,888 complete follower records
(31,068,416 bytes) exactly, including reserved bytes, with state guards and
unchanged input checks. It covers all six inspected stage values, nine curve
amounts, position/rounding boundaries, signed zero, block sizes1/3/31/511/8192,
zero/tiny/overshooting coefficients, 414 multi-block transition sequences and
10,000 deterministic randomized configurations. The sequence fixture performs
the caller's linear level accumulation and note-off initialization explicitly;
that operation is outside this primitive. A further 57 new-ABI invalid argument
cases require atomic rejection. Invalid native inputs are not called.

The verified new-ABI domain requires finite attack/sustain in[0,1], stage0..5,
position[0,255], finite level/prior increment, release scale[-2,2], three coefficients[0,510], count1..8192
and259 finite curve values[0,1]. Callers must supply valid, non-overlapping
storage of the documented size and use the default floating-point environment.
The fixture supplies curves from the companion mathematical generator; it does
not establish equivalence for every arbitrary caller-authored curve. No shared
global curve or plugin state is required by the new implementation.

The critic found two repeated-call boundary failures in the first candidate: cubic
interpolation can yield an increment below -1 or a caller-accumulated level above
1. The corrected API accepts finite prior increment/level and permits release
scale[-2,2]. Repeated one-sample steep-curve sequences include immediate note-off
capture of both overshoots; finite extreme prior-state fields are also compared.

Native transition details are preserved: a completed or disabled attack falls
through to decay within the same call, completed decay enters sustain with
position255, and release updates its increment without changing the stage.
The caller remains responsible for starting stages, accumulating level and
detecting final release. The scalar decay and vector release paths have distinct
floating-point operation ordering. Their cubic interpolation uses a rounded
index and the curve's boundary padding.

Whole-plugin reconstruction remains incomplete. MIDI, oscillator/sample engine,
effects, full voice scheduling, resources, presets, factory ABI, host/project
state, editor and host integration require separate implementation and review.
