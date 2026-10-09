#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum { VL_TYRELL_NOTIFY_CAPACITY = 213 };
typedef struct VLTyrellNotifyDescriptor {
 int32_t type;
 uint32_t flags;
 float minimum, maximum;
 int32_t special_index;
 uint32_t pointer_present;
} VLTyrellNotifyDescriptor;
typedef struct VLTyrellNotifySpecial {
 int32_t identifier;
 float increment;
 int32_t remaining;
 float target;
} VLTyrellNotifySpecial;
typedef struct VLTyrellNotifyState {
 uint32_t internal_count, special_count;
 int32_t queue_count, dirty;
 uint32_t immediate;
 int32_t depth;
 float raw[VL_TYRELL_NOTIFY_CAPACITY];
 uint32_t pointee_bits[VL_TYRELL_NOTIFY_CAPACITY];
 VLTyrellNotifySpecial special[VL_TYRELL_NOTIFY_CAPACITY];
 int32_t queue[VL_TYRELL_NOTIFY_CAPACITY];
} VLTyrellNotifyState;
typedef struct VLTyrellNotifyResult {
 float clipped;
 uint32_t ignored, effective_immediate;
 uint32_t unit_set_needed, unit_activity_needed, property_needed;
} VLTyrellNotifyResult;
// Independent prepared storage decision primitive, not the native C++ class.
// The whole state is initialized. All storage is external, valid, serialized
// and stable for the call. The
// descriptors array has internal_count readable entries and is disjoint from
// state/result; result and state are disjoint. Count<=213; queue_count=-1..S.
// Raw/target finite |x|<=4096, increments finite |x|<=8192, remaining=-1..50,
// dirty0/1, immediate0..255, pointer_present0/1, force0..255. Selected ranges
// finite [-4096,4096], minimum<=maximum; input finite |x|<=8192. Nearest-even
// gradual FP, no contraction or fast math. Call rejection is atomic.
// Models exact type0/type1 storage and low-byte3/4 ignored types. Other types
// (including callback-dependent type5) reject. Flag2 selects special routing;
// flag0x200 selects observed cyclic-difference arithmetic. Queue entries are
// special indexes. No native scheduler consumes the queue here.
// Pointer bits are copied scalar storage, not actual foreign pointees. Output
// callback decisions do not execute unit0xc8/0x278/property/audio callbacks;
// their effects and metadata changes are outside this primitive's contract.
// Success1/rejection0; successful ignored types leave state unchanged.
int vl_tyrell_notifier_storage(const VLTyrellNotifyDescriptor *,
 VLTyrellNotifyState *, int32_t identifier, uint32_t force, float value,
 VLTyrellNotifyResult *);
#ifdef __cplusplus
}
#endif
