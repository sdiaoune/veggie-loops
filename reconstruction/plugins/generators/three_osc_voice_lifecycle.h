#pragma once
// Original metadata-only reconstruction. Native note objects, envelopes,
// sample rendering, scheduling and automatic host deletion are outside this API.
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
  int32_t position, wait_frames;
  uint8_t released;
} vl_osc_lifecycle_state;
// Flags have count readable bytes, each 0/1; count in [0,2^20]. A limit<=0
// disables soft voice limiting. A positive limit marks one existing voice for
// quick release when count>=limit; it does not delete it or prevent a new note.
// The first voice is the fallback; the last released voice at indices1..end
// takes precedence. Returns its index, or -1 when no quick release is required.
int32_t vl_osc_lifecycle_select(const uint8_t* flags, int32_t count, int32_t limit);
// Initialized metadata: position=-1 or nonnegative, wait_frames>=0, released0/1.
// Mark released; start at position0/wait0 only if release has not already begun.
void vl_osc_lifecycle_quick_release(vl_osc_lifecycle_state*);
// Advance prepared release position through a block. frames in [0,4096],
// position<=INT_MAX-4096 and wait_frames>=0. No audio buffer is processed.
void vl_osc_lifecycle_advance(vl_osc_lifecycle_state*, int32_t frames);
// release_length>=0, matching the prepared table length. This tests completion;
// the caller decides when to notify/remove the host-owned voice.
int vl_osc_lifecycle_finished(const vl_osc_lifecycle_state*, int32_t release_length);
#ifdef __cplusplus
}
#endif
