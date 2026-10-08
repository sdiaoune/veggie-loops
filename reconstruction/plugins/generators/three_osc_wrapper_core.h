#pragma once

// Original reconstruction of oscillator controls, integrated-editor control
// storage and raw-voice paths. Integrated-editor modulation DSP, envelopes,
// final mixing and GUI are not implemented by this bounded component.
// This is a new C ABI, not CreatePlugInstance or a VST/AU factory.
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
typedef struct vl_osc_core vl_osc_core;
typedef struct vl_osc_voice vl_osc_voice;
typedef void (*vl_osc_compute_lr)(void*, float*, float*, float, float);
typedef struct {
  int32_t pitch;
  float volume, left_gain, right_gain;
  uint32_t phase_offset;
  int32_t stereo_fine;
  uint8_t noise, non_sine;
} vl_osc_derived;
typedef struct {
  uint32_t words[624];
  uint32_t index, seed, previous_seed;
} vl_osc_random_state;

// Calls are serial; the reconstructed engine's noise/lifecycle globals are
// shared. compute_lr is the host-owned callback observed at host VMT+0x1c0.
vl_osc_core* vl_osc_core_create(vl_osc_compute_lr compute_lr, void* context);
void vl_osc_core_destroy(vl_osc_core*);
int vl_osc_core_set_sample_rate(vl_osc_core*, int32_t rate);
// Index 0..113, valid raw value in the observed control range, flags
// 1=set, 2=get, 32=normalized 2^30 value. Current rounding mode is honored.
int32_t vl_osc_core_parameter(vl_osc_core*, int32_t index, int32_t value, uint32_t flags);
void vl_osc_core_derived(const vl_osc_core*, vl_osc_derived result[3], uint32_t* ring, uint8_t* stereo);
// Valid version-14 prefix: 84 control bytes, four inversion/ring bytes,
// one HQ byte. The other 367 integrated-editor bytes are outside this API.
int vl_osc_core_restore_prefix(vl_osc_core*, const uint8_t* prefix, size_t length);
int vl_osc_core_save_prefix(const vl_osc_core*, uint8_t* prefix, size_t length);
// Entire 456-byte version-14 payload. Padding is written as zero; the native
// three bytes at payload+89 are undefined stack padding and are ignored on
// restore. Editor control storage is implemented; its modulation DSP is absent.
// Payload+432..439 and +448..451 are ignored and canonicalized to zero, as
// observed in native Restore/Save. 441 field bytes are preserved, 12 reserved
// output bytes are zero, and the other three bytes are undefined native padding.
int vl_osc_core_restore_payload(vl_osc_core*, const uint8_t* payload, size_t length);
int vl_osc_core_save_payload(const vl_osc_core*, uint8_t* payload, size_t length);
// Legacy host tables contain exactly 16384 samples each, in waveform 0..5
// order, and remain readable for the core's lifetime. No FL assets are embedded.
int vl_osc_core_host_tables(vl_osc_core*, const float* const tables[6]);
void vl_osc_core_render_mode(vl_osc_core*, uint32_t flags);
// Custom input is exactly 16384 readable floats. NULL selects native fallback
// waveform 3 for control value 6. The input is consumed before returning.
void vl_osc_core_custom_wave(vl_osc_core*, const float* wave);
// Fixture/state access for the independently reconstructed Pascal MT19937.
// index <=624; previous_seed must equal seed for an initialized state.
int vl_osc_core_random_state(vl_osc_core*, const vl_osc_random_state*);
vl_osc_voice* vl_osc_core_trigger(vl_osc_core*, intptr_t tag);
void vl_osc_core_release(vl_osc_core*, vl_osc_voice*);
void vl_osc_core_kill(vl_osc_core*, vl_osc_voice*);
// Raw per-voice rendering only, before integrated-editor envelopes/mixing.
// pitch is finite cents with every converted increment in [0,2^63),
// frames <=2^20, buffer has 2*frames writable floats. Invalid inputs are
// rejected before voice/RNG state changes, unlike the native low-level ABI.
// Legacy mode requires host tables; render-mode flag 2 enables its native
// multi-phase averaging path. HQ mode ignores that averaging flag.
int vl_osc_core_render(vl_osc_core*, vl_osc_voice*, float pitch, float* buffer, uint32_t frames);
void vl_osc_core_voice_phases(const vl_osc_voice*, uint32_t phases[6], uint8_t* stereo);
size_t vl_osc_core_voice_count(const vl_osc_core*);
#ifdef __cplusplus
}
#endif
