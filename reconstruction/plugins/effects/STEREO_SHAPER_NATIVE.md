# VL Stereo Shaper native boundary

This original native wrapper builds over the measured arm64 FL C++ protocol and
the reviewed numerical C ABI. The three checks below passed independent copied
source builds and replays. This build has no editor. Original VCL behavior,
the actual FL application, projects, mixer topology, VST/AU and whole-plugin
equivalence remain separate open gates.

```sh
./reconstruction/plugins/effects/verify_stereo_shaper_engine_loader.sh
./reconstruction/plugins/effects/verify_stereo_shaper_host_routing.sh
./reconstruction/plugins/effects/verify_stereo_shaper_engine_stream.sh
```

The first test uses the intact engine's DLL loader and allocates/frees its actual
C++-to-Pascal plugin wrapper. All 20 callback slots are exercised: 7,200 parameter
sets, 1,200 state saves, 240 restores, and 140,700 stereo frames. The numerical
rate/resume behavior is replayed; unused generator/voice/MIDI callbacks are
explicit independent no-ops. Name labels are original descriptive labels.
The supported dispatchers are resume 2, sample rate 4, and classification 52;
remaining commercial dispatcher/event behavior is not claimed.

The routing test allocates both of the actual engine's host and plugin adapters.
The C++ host interface's slot 37 enters thunk `0xb4e990`, which subtracts the
interface offset and branches to `0xb4d040`. That body calls the Pascal host's
VMT slot `0x1f0` with the existing sender/index/descriptor arguments. Live probes
preserved pointer and flags values, including a null output. The measured packed
descriptor has a pointer at 0, a 32-bit flags value at 8, and size 12.

The own effect renders first, then requests the side buffer with flags 0, adds
dry minus processed samples when available, and releases it with flags 1.
The canonical adapter test passes 600 routing/state sequences, 450 active send
sequences and 64,890 frames. It covers the four-output fixture, indices 1..3,
pre/post selection, five rates, zero/odd/vector-boundary blocks, exact alias,
four-byte offsets, source immutability, and independent main/side guard checks.
Both a supplied and null output are exercised. This validates the actual engine
adapter and compiled wrapper with a synthetic Pascal host, not an instantiated
FL application or a project/mixer configuration.

The stream test uses actual engine TMemoryStream/TStreamAdapter objects and the
actual plugin wrapper. It passes 128 saves/restores of the 36-byte state, adjacent
completion-count sentinels, the provider's negative HRESULT32 invalid-pointer
path, and atomic rejection of synthetic full-count HRESULT32 failures on either
the first or second read. State transfers use 4 then 32 bytes. This wrapper
requests completion outputs and rejects malformed data; the commercial source
factory used null counts and only valid framing is compared to that source.

All native instance access, including getters, streams and destruction, requires
serialized host access. Numerical sample/rate/state domains and FP flags match
[STEREO_SHAPER.md](STEREO_SHAPER.md) and the public C header. A side buffer supplied
by the host must contain finite samples and be disjoint from both main buffers.
The host/module must remain alive until native destruction finishes. Fixed engine
offset tests refuse builds outside macOS arm64 and verify the universal engine
SHA-256 before calling its methods. No original runtime/assets are distributed.
