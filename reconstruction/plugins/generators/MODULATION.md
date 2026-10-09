# Prepared five-group modulation state

This independent source combines the five prepared envelope/LFO states into
pan, volume, cutoff, resonance and pitch modulation, handles release of groups
1 through 4, and updates final pitch only for an explicit new tick or positive
initializer counter. The caller supplies prepared configurations, initialized
states, readable synthetic/independently generated LFO tables and host timing.
The native pan combination uses the LFO contribution. Pitch uses raw integer
depth controls; cutoff and resonance use their normalized depth coefficients.

Run `./reconstruction/plugins/generators/verify-modulation.sh` on macOS arm64
with the identity-matched installed wrapper. It compiles an independent dynamic
library and compares1,800 prepared five-group fixtures: 108,000 direct tick steps,
3,600 releases, 216,000 conditional pitch ticks and 15,940,800 exact state/pitch
values. Native calls use identity-bound original routine addresses and synthetic
object layouts that supply the prepared configuration/state pointers. No native
factory, GUI, asset or table data is embedded in the new source.

The prepared-state domain is the envelope primitive's successful coefficient
contract, with raw depth controls in [-128,128] and finite final pitch bounded by
24000 cents. Each LFO table contains16384 readable finite samples in[-1,1],
matching the native corpus's controlled sine data. The fixture initializes
states with the already verified envelope
initializer and supplies controlled tick conditions. It does not reconstruct
native constructor/lifecycle, automatic host clock production, configuration
updates, voice stealing, filters, sample processing or audio routing. New C
adapters expose these prepared routines; no complete Fruity/VST/AU/plugin
equivalence is claimed. The maintained sanitized manifest binds exact source,
artifact and target identities.
