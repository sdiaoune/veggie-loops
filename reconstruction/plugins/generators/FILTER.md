# Prepared filter coefficients and kernels

This independent source rebuilds three native coefficient families and their
scalar stereo kernels: the single-pole double-state filter, biquad native types
1 through 5, and special-filter types 6/7. The explicit context uses the reviewed
initialized exponent/denormal defaults and the native double-to-float rate ratio.
The native production and routing of that context remain separate work.

`./reconstruction/plugins/generators/verify-filter.sh` builds and separately loads
the independent library, verifies the installed macOS arm64 wrapper identity
and initialized context, then compares 54,000 coefficient cases and 54,000 render
cases. The corpus contains 46,446,912 exact float/state words across 7 rate
contexts from 8000 to 384000 Hz. Coefficient inputs cover finite [-2,2] values and
clamping boundaries. Audio tests use a narrower stable normalized [0,1] domain,
both in-place and disjoint buffers, frame lengths 0 through 4096, coefficient
sweeps, tiny-state cleanup, preserved input and nonzero output guards.

Single-pole histories are double values and are cleared at the observed float
silence threshold. Biquad histories are float, with separate multiply/add
rounding and no extra history clearing. The special kernel clears all eight
history floats after processing, including its unused history tail. The new
source preserves those different operations. Biquad sin/cos preparation calls
double math and rounds each result to float, matching the original helper.

This is prepared coefficient/kernel arithmetic with new C adapters and explicit
header preconditions. It does not implement native context/preference setters,
general biquad design types 6 through 8, object lifecycle, filter activation
routing, double-order compensation, voice modulation or sample-pipeline
integration. Those remain whole-plugin gates, along with editor, native Fruity
factory and host VST/AU/FL equivalence. The source embeds no native assets or
commercial DSP library. The maintained script writes a sanitized manifest
binding exact sources, rebuilt artifact and native target identities.
