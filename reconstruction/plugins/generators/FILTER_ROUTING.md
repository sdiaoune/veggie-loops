# Prepared wrapper filter routing

This independent source connects the reviewed filter kernels to the wrapper's
activation latch, bypass, initial/ongoing cutoff slew, one/two-pass processing
and output-gain compensation. The caller supplies explicit prepared state,
normalized controls and the reviewed context. It does not create a native
plugin/editor object or obtain controls/timing from an actual host.

Run `./reconstruction/plugins/generators/verify-filter-routing.sh` on macOS arm64
with the identity-matched installed wrapper. The maintained replay compares
1,200 synthetic voice/context fixtures over 14,400 original routine calls and
16,747,200 exact audio/state/gain values. It covers supported filter types 0
through 7, both one and two passes, persistent histories, bypass and activation,
cutoff slew, six rate contexts and frame lengths 1 through 4096. The input is
preserved and nonzero output guards are checked. An inactive result preserves
the temporary output buffer, leaving pointer swapping and final mixing to the
caller.

Each retained-state fixture fixes filter type, double-order mode and sample rate.
Changing them within a live state is outside this corpus; the shared history
representation and native configuration/reset routing need separate proof.

The combined-control boundaries at -2 and 2 are explicit fixtures. Carried
history reaches magnitude 130,936 in this corpus while native and rebuilt state
remain exact. This is a separate proof of the routing path's broader carried
state, extending the standalone kernel corpus's initial history bound of 2.
Routing starts from zero histories and preserves subsequent finite native state;
the observed magnitude is not a bound for arbitrary caller-provided state.

The single filter begins inactive and latches active after a non-identity
coefficient update. Positive types begin active. The native biquad second pass
adjusts both output gains using a separately rounded double compensation
expression. The special second pass temporarily modifies resonance and restores
it afterward. The reconstruction preserves those operations and their state.

The fixture supplies synthetic native layouts with controlled configuration,
parameter, buffer and state pointers. It checks the original arithmetic routine
rather than original constructors, editor control dispatch or actual host
routing. General design type 8, native context production, filter-mode property
mapping, configuration update routing, UI and complete modulation/voice audio
pipeline remain open. The new C adapter and source do not establish full
Fruity/VST/AU/FL equivalence. No commercial binary or asset is embedded.
