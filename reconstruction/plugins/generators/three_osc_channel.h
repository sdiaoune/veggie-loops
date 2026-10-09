#pragma once
// Original bounded channel composer. This is a new C API, not a native
// Fruity/VST/AU factory. Actual FL host scheduling/editor ABI remain outside.
#include "three_osc_wrapper_core.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct vl_osc_channel vl_osc_channel;
typedef struct vl_osc_channel_voice vl_osc_channel_voice;
typedef struct {float pan,volume,pitch,mod_x,mod_y;} vl_osc_channel_levels;
typedef struct {vl_osc_channel_levels initial,final;} vl_osc_channel_parameters;
// Callbacks are serial and nonthrowing. Notification callbacks must defer all
// channel mutations until render returns. The caller owns parameter/table
// storage and serializes access across all raw-engine instances.
typedef void (*vl_osc_channel_notify_kill)(void*,intptr_t,int32_t);
// Initial rate is44100; current rate[8000,384000], tempo(0,1000], PPQ[4,2^20].
// These explicit contexts remain fixed. Tables[0..5] each have16384 readable
// finite samples in[-1,1], with the first three also used as LFO waveforms.
// Tables/callback context outlive the channel. ReturnsNULL for unsupported
// scalars/allocation failure; valid pointer storage is a precondition.
vl_osc_channel* vl_osc_channel_create(vl_osc_compute_lr,vl_osc_channel_notify_kill,
 void* context,int32_t current_rate,double tempo,uint32_t ppq,const float* const tables[6]);
void vl_osc_channel_destroy(vl_osc_channel*);
// Delegated raw control/storage API. Controls/configuration follow the prepared
// voice contract: flags0..31, global113=0, type0 filter, filter depths[-32,32].
int32_t vl_osc_channel_parameter(vl_osc_channel*,int32_t index,int32_t value,uint32_t flags);
int vl_osc_channel_restore(vl_osc_channel*,const uint8_t* payload,size_t length);
// limit<=0 disables soft limiting; otherwise one existing voice is marked for
// quick release when count>=limit. A new voice is still appended. Parameters
// are caller-owned and remain readable/writable until explicit voice kill.
void vl_osc_channel_max_poly(vl_osc_channel*,int32_t limit);
vl_osc_channel_voice* vl_osc_channel_trigger(vl_osc_channel*,vl_osc_channel_parameters*,intptr_t tag);
// Ordinary release enters prepared envelope-release stages. Quick release only
// changes released/declick metadata, preserving envelope stages/positions.
int vl_osc_channel_release(vl_osc_channel*,vl_osc_channel_voice*);
int vl_osc_channel_quick_release(vl_osc_channel*,vl_osc_channel_voice*);
int vl_osc_channel_kill(vl_osc_channel*,vl_osc_channel_voice*);
void vl_osc_channel_new_tick(vl_osc_channel*);
// frames1..4096; host output has2*frames writable floats.
// Every final level meets the prepared voice bounds; caller resets base pitch
// per block. Voices accumulate in creation order into positive zero, then
// overwrite host output. Completion emits(tag,-1) during voice iteration; it does
// not remove a voice. Output must not overlap borrowed parameters/tables/state
// or callback context. No reentrant mutation is supported. Empty renders leave
// output and pending tick unchanged. Valid supported serial calls are the
// differential domain; no allocation-failure/invalid native-call proof.
int vl_osc_channel_render(vl_osc_channel*,float* host_output,uint32_t frames);
size_t vl_osc_channel_voice_count(const vl_osc_channel*);
// Optional destinations have the indicated lengths; no output overlaps state.
int vl_osc_channel_snapshot(const vl_osc_channel*,const vl_osc_channel_voice*,
 uint32_t modulation_words[45],uint8_t filter_bytes[112],float gains[2],
 int32_t release_values[3],uint32_t phases[6],uint8_t* stereo);
#ifdef __cplusplus
}
#endif
