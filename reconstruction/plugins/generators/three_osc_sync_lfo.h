#pragma once
// Original metadata producer for synchronized five-group LFO phases. This new
// C API accepts explicit context delivery; it does not generate a host clock.
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
  uint32_t registered_mask;
  uint32_t registered_order[5];
  uint32_t registered_count;
  uint32_t phases[5];
  uint32_t pending_tick;
  uint32_t dirty;
  uint32_t release_refresh;
} vl_osc_sync_lfo_state;
// Every pointer is nonnull. State is writable; flags/increments each have five
// readable words and do not overlap state. Calls are serial. State starts zero;
// count<=5, order holds unique group indices 0..4, mask matches that prefix and
// tick/dirty/refresh are 0/1.
// Editor control updates mark an internal dirty latch, separate from public
// filter-mode parameter 113. Initialization through group writes also marks it.
void vl_osc_sync_lfo_editor_changed(vl_osc_sync_lfo_state*);
// Flags fit [0,63], volume_enabled and has_voices are 0/1. A nonempty frame clears
// the release-refresh flag and consumes dirty 1->0. Consuming it rebuilds the
// registry from flag 32 groups and sets release_refresh when volume is disabled.
// Empty renders retain all metadata. Registry updates preserve phase values.
// Unordered removal swaps the last group into a deleted slot before appending;
// unused order slots are ignored. No allocator or concurrent atomic ABI claim.
void vl_osc_sync_lfo_prepare_frame(vl_osc_sync_lfo_state*,const uint32_t flags[5],
 int volume_enabled,int has_voices);
// Each increment is an explicit prepared UInt32. Registered phases advance
// modulo 2^32; every tick sets the pending flag even with an empty registry.
void vl_osc_sync_lfo_new_tick(vl_osc_sync_lfo_state*,const uint32_t increments[5]);
// Host MixingTime/GT_Ticks is finite and in [-2^63,2^63). Native conversion
// truncates to signed 64, takes low 32, then multiplies each registered increment
// modulo 2^32. Unsupported scalar times return 0 without changing state. This is
// explicit controlled delivery, not proof of actual application time production.
int vl_osc_sync_lfo_song_position(vl_osc_sync_lfo_state*,const uint32_t increments[5],double mixing_ticks);
// Native GenRender clears the pending flag only for a nonempty voice list.
void vl_osc_sync_lfo_finish_frame(vl_osc_sync_lfo_state*,int has_voices);
#ifdef __cplusplus
}
#endif
