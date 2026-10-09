#include "three_osc_sync_lfo.h"
#include <cmath>
extern "C" void vl_osc_sync_lfo_editor_changed(vl_osc_sync_lfo_state* state) {
  state->dirty = 1;
}
extern "C" void vl_osc_sync_lfo_prepare_frame(vl_osc_sync_lfo_state* state,
                                             const uint32_t* flags,
                                             int volumeEnabled, int hasVoices) {
  if (!hasVoices) return;
  state->release_refresh = 0;
  if (state->dirty == 1) {
    state->dirty = 0;
    state->release_refresh = volumeEnabled == 0;
    for (uint32_t group = 0; group < 5; ++group) {
      for (uint32_t index = 0; index < state->registered_count; ++index) {
        if (state->registered_order[index] != group) continue;
        --state->registered_count;
        if (index < state->registered_count)
          state->registered_order[index] = state->registered_order[state->registered_count];
        break;
      }
      if (flags[group] & 32u) state->registered_order[state->registered_count++] = group;
    }
    state->registered_mask = 0;
    for (uint32_t index = 0; index < state->registered_count; ++index)
      state->registered_mask |= 1u << state->registered_order[index];
  }
}
extern "C" void vl_osc_sync_lfo_new_tick(vl_osc_sync_lfo_state* state,
                                        const uint32_t* increments) {
  state->pending_tick = 1;
  for (uint32_t index = 0; index < state->registered_count; ++index) {
    const auto group = state->registered_order[index];
    state->phases[group] += increments[group];
  }
}
extern "C" int vl_osc_sync_lfo_song_position(vl_osc_sync_lfo_state* state,
                                            const uint32_t* increments, double ticks) {
  if (!std::isfinite(ticks) || ticks < -0x1p63 || ticks >= 0x1p63) return 0;
  const uint32_t lowTick = static_cast<uint32_t>(static_cast<int64_t>(std::trunc(ticks)));
  for (uint32_t index = 0; index < state->registered_count; ++index) {
    const auto group = state->registered_order[index];
    state->phases[group] = static_cast<uint32_t>(uint64_t(lowTick) * increments[group]);
  }
  return 1;
}
extern "C" void vl_osc_sync_lfo_finish_frame(vl_osc_sync_lfo_state* state, int hasVoices) {
  if (hasVoices) state->pending_tick = 0;
}
