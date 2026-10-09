#pragma once
#include "stereo_shaper_plugin.h"
#ifdef __cplusplus
extern "C" {
#endif
// Independent AppKit UI. All UI entry points require the main thread. The view,
// numerical instance and host must remain alive through main-thread destruction.
// All numerical access, including refresh/getters, uses paired host lock/unlock
// callbacks when supplied. Notifications occur synchronously after unlocking.
typedef struct VLStereoShaperEditorHost{
  void*context;
  void(*lock)(void*);
  void(*unlock)(void*);
  void(*changed)(void*,int32_t,int32_t);
  void(*hint)(void*,const char*);
  // Independent routing UI notification, separate from the six automatable
  // parameters. The native wrapper supplies the measured positive-send FHD73
  // transition protocol; remaining latency/application behavior is unverified.
  void(*routing)(void*,int32_t,int32_t);
}VLStereoShaperEditorHost;
void*vl_stereo_shaper_editor_create(VLStereoShaperPlugin*,const VLStereoShaperEditorHost*);
void vl_stereo_shaper_editor_attach(void*,void*parent_nsview);
void vl_stereo_shaper_editor_refresh(void*);
void vl_stereo_shaper_editor_hint(void*,int32_t index,int32_t raw_value);
int vl_stereo_shaper_editor_main_thread(void);
// Returns0 off-main, preserving ownership for a main-thread retry; null returns1.
int vl_stereo_shaper_editor_destroy(void*);
#ifdef __cplusplus
}
#endif
