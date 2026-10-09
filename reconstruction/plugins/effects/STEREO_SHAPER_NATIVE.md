# VL Stereo Shaper native boundary

This independently written wrapper builds over the measured arm64 FL C++
protocol and reviewed numerical C ABI. The optional AppKit editor supplies six
sliders, a side-output selector and before/after processing controls. Numerical,
loader, routing, stream and editor checks pass under the commands below. The
editor/registration candidate passed independent copied-source replay; its final
maintained-path binding is recorded in the verification manifest. Original VCL
behavior, actual FL application hosting, projects, mixer topology, VST/AU and
whole-plugin equivalence remain separate open gates.

```sh
./reconstruction/plugins/effects/verify_stereo_shaper.sh
./reconstruction/plugins/effects/verify_stereo_shaper_engine_loader.sh
./reconstruction/plugins/effects/verify_stereo_shaper_host_routing.sh
./reconstruction/plugins/effects/verify_stereo_shaper_engine_stream.sh
./reconstruction/plugins/effects/verify_stereo_shaper_editor.sh
```

The loader test uses the intact engine's DLL loader and allocates/frees its actual
C++-to-Pascal plugin wrapper. All 20 callback slots are exercised: 7,200 parameter
sets, 1,200 state saves, 240 restores and 140,700 stereo frames. Rate/resume
behavior is replayed; unused generator/voice/MIDI callbacks are explicit
independent no-ops. Name labels are original descriptive labels. Supported
numerical dispatchers are resume 2, sample rate 4 and classification 52. The
optional editor adds attach/detach dispatcher 0 and GUI Idle.

The routing test allocates the actual engine host and plugin adapters. C++ host
slot 37 enters thunk `0xb4e990`, subtracts the interface offset and branches to
`0xb4d040`, which calls Pascal host VMT slot `0x1f0`. Live probes preserved the
sender, index, descriptor pointer and flags, including a null output. The packed
descriptor has a pointer at 0, 32-bit flags at 8 and size 12.

The effect renders, requests the side buffer with flags 0, adds dry minus
processed samples when available, and releases with flags 1. The canonical test
passes 1,200 routing/state restores, 450 active send sequences and 64,890 frames.
It covers four outputs, indices 1..3, pre/post selection, five rates,
zero/odd/vector-boundary blocks, exact alias, four-byte offsets, source
immutability and independent main/side guards. Supplied and null outputs pass.
Positive send changes unregister the previous index with FHD73 value 0 and
register the new index with value 1. Repetition emits no event. The test verifies
899 registration events through the actual host adapter. Source-factory
repetition and destruction were independently replayed under the pinned source
SHA: destruction with final positive send 3 emitted no FHD73. Our destruction
also emits none. Actual application host cleanup ownership remains untraced.

The stream test uses actual TMemoryStream/TStreamAdapter objects and the plugin
wrapper. It passes 128 saves/restores of the 36-byte state, adjacent count
sentinels, the provider's negative HRESULT32 invalid-pointer path and atomic
rejection of synthetic full-count HRESULT32 failures on either read. Transfers
use 4 then 32 bytes. This wrapper requests completion outputs and rejects
malformed data; valid framing is compared with the commercial source factory.

The editor script first checks the standalone AppKit view: six parameter changes,
two routing changes and 50 automation displays. It then builds with
`VL_STEREO_SHAPER_APPKIT_EDITOR=1` and checks attachment, detachment, main-thread
retry after refused worker destruction, six controls, seven hints and two resize
notifications through actual engine host/plugin adapters. Host automation
refreshes on GUI Idle. Change/hint notifications occur after the numerical lock
is released. Worker hint/get calls during first attachment, pre-attachment
worker destruction, tick/MIDI tick/Idle and worker UI entry points preserve the
main-thread UI boundary. Tick/MIDI tick are no-ops. GUI state is inspected only
after a main-thread check. No commercial GUI resources or artwork are copied.

All native instance access, including getters, streams, numerical/routing
updates, registration notifications and destruction, requires serialized host
access. UI numerical reads/writes use paired host lock/unlock callbacks. Hint
flag 4 is a main-thread GUI operation outside the mixer lock. In an optional
editor build, all native destruction must run on main even before attachment;
an off-main attempt retains the instance for a main-thread retry. Keep the
instance, host and module alive until destruction completes. Other UI calls
require main as well. The default build contains no editor.

The current factory/editor use the reviewed [own lifetime repair](soft-stereo-lifetime/README.md).
Successful complete callback20 ends the instance and retains raw storage for the
matching caller release; callbacks0/21 end and free it. Successful editor cleanup
clears retained callbacks/context and slider, send and position targets. The
existing policy of emitting no invented send-unregister event is preserved; the
actual application cleanup owner remains unknown. Two independent source and two
engine runtime critics accepted the bounded repair. Original extra-destructor,
class/GUI and application ownership equivalence remain unproved.

Numerical domains and FP flags match [STEREO_SHAPER.md](STEREO_SHAPER.md) and the
public C header. A supplied side buffer must contain finite samples and be
disjoint from both main buffers. Fixed engine-offset tests refuse non-macOS-arm64
builds and verify the universal engine SHA before calls. These fixtures use a
synthetic Pascal host behind the real adapters; an actual FL application or
project/mixer configuration is not instantiated. Remaining dispatcher/event,
latency and host-topology behavior is open. No original runtime is distributed.
