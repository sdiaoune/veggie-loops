#pragma once
#include "mute2_plugin.h"
#ifdef __cplusplus
extern "C" {
#endif
// Independent AppKit editor protocol. The editor, its numerical instance and
// host context must remain alive until successful main-thread destruction.
// All UI calls require the main thread. Numerical calls require serialization
// or host locking. Lock/unlock callbacks must both be present or both absent;
// change/hint callbacks are synchronous and delivered after unlocking.
typedef struct VLMute2EditorHost {
  void* context;
  void (*lock)(void*);
  void (*unlock)(void*);
  void (*changed)(void*,int32_t,int32_t);
  void (*hint)(void*,const char*);
} VLMute2EditorHost;
void* vl_mute2_editor_create(VLMute2Plugin* plugin,const VLMute2EditorHost* host);
void vl_mute2_editor_attach(void* editor,void* parent_nsview);
void vl_mute2_editor_refresh(void* editor);
void vl_mute2_editor_hint(void* editor,int32_t index,int32_t raw_value);
int vl_mute2_editor_main_thread(void);
// Returns 0 off-main without changing ownership; retry on the main thread.
// A null editor returns 1. Successful destruction returns 1.
int vl_mute2_editor_destroy(void* editor);
#ifdef __cplusplus
}
#endif
