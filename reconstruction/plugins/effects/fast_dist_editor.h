#pragma once
#include "fast_dist_plugin.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct VLFastDistEditorHost {
  void *context;
  void (*lock)(void *);
  void (*unlock)(void *);
  void (*changed)(void *, int32_t, int32_t);
  void (*hint)(void *, const char *);
} VLFastDistEditorHost;
// Independently written AppKit controls. Every GUI operation and destruction
// requires main thread. Numerical ownership is external and outlives the view;
// paired locks or otherwise serialized access protect snapshots and changes.
// Notifications follow unlock. Host/context/module remain alive until a
// successful main destruction. Quality selection is outside these controls.
int vl_fast_dist_editor_main_thread(void);
void *vl_fast_dist_editor_create(VLFastDistPlugin *,
                                 const VLFastDistEditorHost *);
void vl_fast_dist_editor_attach(void *, void *parent_view);
void vl_fast_dist_editor_refresh(void *);
void vl_fast_dist_editor_hint(void *, int32_t index, int32_t raw);
int vl_fast_dist_editor_destroy(void *);
#ifdef __cplusplus
}
#endif
