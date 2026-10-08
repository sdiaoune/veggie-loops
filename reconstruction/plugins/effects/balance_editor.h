#pragma once
#include "balance_plugin.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
// Original AppKit editor; no commercial UI resources are included. Main-thread
// calls only. Host lock/unlock serialize numerical access with audio rendering;
// change/hint callbacks happen after unlock. Without a host, callers must
// serialize numerical access themselves. This callback structure is our own ABI.
typedef struct VLBalanceEditorHost {
  void* context;
  void (*lock)(void*);
  void (*unlock)(void*);
  void (*changed)(void*,int32_t,int32_t);
  void (*hint)(void*,const char*);
} VLBalanceEditorHost;
void* vl_balance_editor_create(VLBalancePlugin*,const VLBalanceEditorHost*);
void vl_balance_editor_attach(void* editor,void* parent_nsview);
void vl_balance_editor_refresh(void* editor);
void vl_balance_editor_hint(void* editor,int32_t index,int32_t value);
int vl_balance_editor_destroy(void* editor); // 0 off-main: no lifetime changes
int vl_balance_editor_main_thread(void);
#ifdef __cplusplus
}
#endif
