#pragma once
#include "soft_clipper_plugin.h"
#ifdef __cplusplus
extern "C" {
#endif
// Independently written AppKit view. All UI entry points require main.
// Numerical instance/host must remain alive until main-thread editor
// destruction completes. Numerical reads/writes use paired host lock/unlock
// callbacks when supplied; caller serialization is still required.
// Notifications run after unlocking.
typedef struct VLSoftClipperEditorHost {
  void *context;
  void (*lock)(void *);
  void (*unlock)(void *);
  void (*changed)(void *, int32_t, int32_t);
  void (*hint)(void *, const char *);
} VLSoftClipperEditorHost;
void *vl_soft_clipper_editor_create(VLSoftClipperPlugin *,
                                    const VLSoftClipperEditorHost *);
void vl_soft_clipper_editor_attach(void *, void *parent_nsview);
void vl_soft_clipper_editor_refresh(void *);
void vl_soft_clipper_editor_hint(void *, int32_t index, int32_t raw_value);
int vl_soft_clipper_editor_main_thread(void);
// Off-main returns0 without releasing ownership; null returns1.
int vl_soft_clipper_editor_destroy(void *);
#ifdef __cplusplus
}
#endif
