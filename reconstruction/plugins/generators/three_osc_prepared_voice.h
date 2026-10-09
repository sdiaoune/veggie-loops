#pragma once
// Original bounded composer for active five-group modulation, single-pole
// filtering, release, gain slew and voice accumulation. This is a new C ABI.
#include "three_osc_wrapper_core.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct vl_osc_prepared_voice vl_osc_prepared_voice;
typedef struct {float pan, volume, pitch, mod_x, mod_y;} vl_osc_prepared_parameters;
// Caller owns the live raw core/voice and serializes operations across every
// raw-engine instance, which shares factory/RNG state. Core and tables outlive
// the composer. Legacy host tables are configured before creation. The core
// observes its existing raw control/voice/buffer contracts throughout.
// initial_rate/current_rate are in [8000,384000]; tempo is in (0,1000], raw
// clock is the PPQ field delivered by native dispatcher14 SetTimeSig and is
// in [4,2^20]. Actual host time-signature/context delivery remains unproved.
// Each LFO table has 16384 readable finite samples in [-1,1].
// Editor flags are in [0,31] (synchronized LFO bit32 excluded), enabled is 0/1,
// times are in [0,65536], sustain in [0,128], curves/depths in [-128,128], and
// waveform choice in [0,2]. Cutoff/resonance-group depths are limited to [-32,32].
// Globals110/111 are in [0,256], global113 is zero. Filter type is fixed at zero.
// Returns NULL for unsupported scalar/configuration inputs or allocation
// failure. Pointer validity remains a caller precondition; no raw voice is owned.
// The corpus fixes initial_rate=44100; other release-table lengths are an
// independent generalization. Native factory/host context/editor ABI are absent.
vl_osc_prepared_voice* vl_osc_prepared_voice_create(vl_osc_core*, vl_osc_voice*, int32_t initial_rate,
 int32_t current_rate, double tempo, uint32_t raw_clock, const float* const tables[3]);
void vl_osc_prepared_voice_destroy(vl_osc_prepared_voice*);
void vl_osc_prepared_voice_release(vl_osc_prepared_voice*);
// Rate, tempo and explicit PPQ remain fixed for the core and this explicit context.
// new_tick is 0/1; finite |pan|<=1, volume in [0,1], pitch in [-2400,2400],
// |mod_x/y|<=.25; frames in [1,4096]. Caller resets the base pitch each block.
// Destination has 2*frames writable floats and begins as positive zero once
// per block, before voices accumulate in creation order. Final pitch is updated
// in place. Borrowed storage must not overlap output/parameters; snapshot output
// buffers must not overlap the composer. Successful calls are serial.
// Native replay covers deterministic oscillator waves0..4, random-phase0 and
// default inversion/ring switches. Other raw modes retain separate core proofs;
// they are not additional native evidence for this composed pipeline.
int vl_osc_prepared_voice_render(vl_osc_prepared_voice*, vl_osc_prepared_parameters*,
 int new_tick, float* destination, uint32_t frames);
// Optional fixture/debug destinations have the indicated lengths.
void vl_osc_prepared_voice_snapshot(const vl_osc_prepared_voice*, uint32_t modulation_words[45],
 uint8_t filter_bytes[112], float gains[2], int32_t release_values[3]);
#ifdef __cplusplus
}
#endif
