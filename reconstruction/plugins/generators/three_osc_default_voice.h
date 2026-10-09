#pragma once
// New independent C API for a narrowly bounded default editor voice path.
// Caller owns the raw core/voice. All raw-engine instances share factory/RNG
// state: caller serializes access across every core/voice for their lifetime.
// Integrated-editor controls must remain at their observed defaults, final
// ModX/ModY must be0, and the observed master pan preference is circular law0.
// Native replay covers deterministic waveform controls0..4, random phase0,
// bothHQ/legacy paths, and an initial44.1kHz release context. Other supported
// initializer rates and oscillator modes remain independent generalizations.
// Native note pitch is static in[-2400,2400]; the broader API range and
// mid-note pitch automation have no pipeline-equivalence proof in this corpus.
// No filter mode, envelope/LFO modulation, native factory, UI or host scheduling
// is implied. Initial sample-rate context affects the10ms release table;
// subsequent core sample-rate changes do not regenerate it, as observed.
#include "three_osc_wrapper_core.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct vl_osc_default_voice vl_osc_default_voice;
typedef struct {float left_gain,right_gain;int32_t release_position;uint8_t initial;} vl_osc_default_voice_state;
// Initial rate in[8000,384000], valid borrowed core and live raw voice. Returns
// NULL on invalid inputs/allocation failure; allocation precedes raw rendering.
vl_osc_default_voice* vl_osc_default_voice_create(vl_osc_core*,vl_osc_voice*,int32_t initial_rate);
void vl_osc_default_voice_destroy(vl_osc_default_voice*);
void vl_osc_default_voice_release(vl_osc_default_voice*);
// Call alongside the raw core rate change; updates its observed rate-scaled
// gain slew maximum while retaining the table's initial-rate length.
int vl_osc_default_voice_set_sample_rate(vl_osc_default_voice*,int32_t rate);
// Finite |pan|<=1, volume in[0,1], pitch cents in[-9600,9600]; frames in[1,4096].
// destination has2*frames writable floats and does not overlap core storage.
// It represents the internal voice accumulator: initialize to positive zero
// once per block, then render voices in creation order. A host's separate final
// addition into a preexisting output buffer remains outside this function.
// Returns1 on rendered success,0 on rejected input/allocation failure. Mixing
// accumulates into destination. This does not kill the borrowed raw voice;
// the caller reads state and performs its own lifecycle/host notification.
int vl_osc_default_voice_render(vl_osc_default_voice*,float pan,float volume,float pitch,
                                float* destination,uint32_t frames);
void vl_osc_default_voice_get_state(const vl_osc_default_voice*,vl_osc_default_voice_state*);
#ifdef __cplusplus
}
#endif
