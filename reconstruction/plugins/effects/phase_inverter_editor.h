#pragma once
#include "phase_inverter_plugin.h"
#ifdef __cplusplus
extern "C" {
#endif
// Independently written AppKit editor. The editor, numerical instance and host
// context must remain alive until successful main-thread destruction. All GUI
// calls require the main thread. Numerical access is serialized or host-locked.
// Lock and unlock must both be supplied or both absent. Change/hint callbacks
// are synchronous and delivered after unlocking the numerical state.
typedef struct VLPhaseInverterEditorHost {
  void* context;
  void (*lock)(void*);
  void (*unlock)(void*);
  void (*changed)(void*,int32_t,int32_t);
  void (*hint)(void*,const char*);
} VLPhaseInverterEditorHost;
void* vl_phase_inverter_editor_create(VLPhaseInverterPlugin* plugin,const VLPhaseInverterEditorHost* host);
void vl_phase_inverter_editor_attach(void* editor,void* parent_nsview);
void vl_phase_inverter_editor_refresh(void* editor);
void vl_phase_inverter_editor_hint(void* editor,int32_t index,int32_t raw_value);
int vl_phase_inverter_editor_main_thread(void);
// Returns 0 off-main without changing ownership; retry on the main thread.
// A null editor or successful destruction returns 1.
int vl_phase_inverter_editor_destroy(void* editor);
#ifdef __cplusplus
}
#endif
