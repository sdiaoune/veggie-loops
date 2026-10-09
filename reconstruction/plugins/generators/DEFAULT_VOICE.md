# Bounded default editor voice output

This independent source connects the reconstructed raw oscillator voice,
prepared release declick, circular master pan, rate-scaled gain slew and stereo
accumulation. It has a new C API in `three_osc_default_voice.h`. The borrowed raw
core and voice remain caller-owned and must outlive the output object. Core and
voice operations are serialized across every raw-engine instance because the
reconstructed engine shares process-global factory and RNG state. Core and
output rate updates are explicit paired calls; the release table retains its
initial-rate length while the gain slew maximum follows the current rate.

The native rate routine first rounds `44100.0 / rate` to float, then multiplies
that rounded value by double `0.001` and rounds to float again. The release
table is created at the native factory's initial 44.1 kHz context (441 samples for
10 ms) and survives later rate changes. The native arithmetic's separate
multiply/add rounding and gain-ramp tail behavior are retained.

Run `./reconstruction/plugins/generators/verify-default-voice.sh` on macOS arm64
with the exact reviewed FL Studio 2024 installation. It builds the independent
library and compares the real original factory's public `GenRender` output in
180 fixtures, with two live voices per fixture. Its 2160 blocks cover both HQ and
legacy deterministic waveforms 0..4, valid oscillator controls, 1..4096 frames,
independent note pan/volume, release transitions and mid-note rate changes.
Each note uses a static pitch in [-2400,2400] cents. The C API's broader
[-9600,9600] range and mid-note pitch automation are not native pipeline coverage.
The result contains 2,046,600 exact stereo samples, 43,200 exact gain/release/
phase/stereo state values, and 180 direct comparisons of the actual native
441-sample release table against the independently generated table.

Each fixture checks that the native voice's filter stays inactive and its pan,
volume and pitch modulation stay at their observed defaults. The host's raw
oscillator pan callback is controlled, and its voice-kill callback is a no-op;
native voice destruction is performed explicitly afterward. Rendering uses a
zeroed internal accumulator in creation order. The original wrapper then
overwrites its host output with that accumulator. This corpus used only zero
host destinations; the overwrite of nonzero destinations remains outside this
function and has a separate channel regression. Other initializer rates,
noise/custom/random-phase modes, modulation, filter modes, voice stealing,
host timing/notification routing, GUI and native factory ABI are not established
by this corpus. This is not a complete Fruity, VST, AU or FL Studio rebuild.

The maintained script writes `default-voice-verification.json`, binding exact
source/header/doc files, rebuilt library and reviewed wrapper/engine/vector
dependency identities. The built library uses original reconstruction source
and Apple's system Accelerate calls; it embeds no commercial assets or binaries.
