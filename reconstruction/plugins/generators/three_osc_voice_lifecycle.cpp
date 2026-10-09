#include "three_osc_voice_lifecycle.h"
#include <algorithm>
extern "C" int32_t vl_osc_lifecycle_select(const uint8_t* flags, int32_t count, int32_t limit) {
  if(limit<=0 || count<limit)return -1;
  int32_t selected=0;
  for(int32_t i=1;i<count;++i)if(flags[i])selected=i;
  return selected;
}
extern "C" void vl_osc_lifecycle_quick_release(vl_osc_lifecycle_state* state) {
  state->released=1;
  if(state->position<0) {state->position=0;state->wait_frames=0;}
}
extern "C" void vl_osc_lifecycle_advance(vl_osc_lifecycle_state* state, int32_t frames) {
  if(state->position<0)return;
  const int32_t skipped=std::min(state->wait_frames,frames);
  state->wait_frames-=skipped;state->position+=frames-skipped;
}
extern "C" int vl_osc_lifecycle_finished(const vl_osc_lifecycle_state* state, int32_t releaseLength) {
  return state->position>=releaseLength;
}
