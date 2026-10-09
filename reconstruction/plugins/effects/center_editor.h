#pragma once
#include "center_plugin.h"
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct VLCenterEditorHost {
  void *context;
  void (*lock)(void *);
  void (*unlock)(void *);
  void (*changed)(void *, int32_t, int32_t);
  void (*hint)(void *, const char *);
} VLCenterEditorHost;
// Own AppKit editor: every view operation and destruction requires main.
// Numerical ownership remains external and outlives the view; paired locks or
// otherwise serialized access protect refresh/change. Notifications follow
// unlock. Host/context/module remain alive until successful main destruction.
int vl_center_editor_main_thread(void);
void *vl_center_editor_create(VLCenterPlugin *numerical,
                              const VLCenterEditorHost *host);
void vl_center_editor_attach(void *editor, void *parent_view);
void vl_center_editor_refresh(void *editor);
void vl_center_editor_hint(void *editor, int32_t index, int32_t value);
int vl_center_editor_destroy(void *editor);
#ifdef __cplusplus
}
#endif
