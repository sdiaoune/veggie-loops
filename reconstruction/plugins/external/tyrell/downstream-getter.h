// Independent raw-getter primitive over a bounded external storage view. MIT.
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct VLTyrellRawView {
 const void* descriptors;       // internal_count records,116 bytes each
 const void* raw_values;        // internal_count IEEE binary32 records
 const void* parameter_pointers;// internal_count native64-bit pointer records
 const void* special_map;       // internal_count signed32 indices
 const void* special_records;   // special_count records,16 bytes each,target+12
 const void* public_map;        // public_count signed32 internal IDs
 uint32_t internal_count;
 uint32_t special_count;
 uint32_t public_count;
} VLTyrellRawView;
// Every view/array/pointee remains valid and unchanged throughout this call;
// serialized or host-mix-locked access and native64-bit storage are required.
// Descriptor type is signed32 at+72;flags are uint32 at+92. Flag mask0x2 routes
// to special target. Otherwise type0 with nonnull pointer converts an int32;
// type3 loads a float pointee;all other cases load raw_values[id]. Type0/3
// require the pointer table;type0 permits a null entry,type3 rejects one.
// Arrays required by the selected route must be present. Fallback is
// ignored,matching the actual getter's XMM0 zeroing;it is not a default value.
// Float loads preserve every binary32 payload. Int32-to-float conversion uses
// nearest-even/default gradual FP. No audio/class/factory/scheduling promise.
// Flag exactly0 accepts internal ID,flag1 maps public index. Counts are bounded
// by213internal/213special/92public. Null view or null descriptor table returns
// positive zero for a bounded index;new malformed-input rejection is defensive
// and does not certify native malformed-input behavior. Null descriptors still
// require a valid public map when flag1,matching the original read order.
// Success1/rejection0. Output is valid float storage,disjoint from the view,
// supplied arrays and ALL nonnull4-byte parameter pointees. Rejection preserves
// all output/input bytes;arbitrary pointer validity is a caller precondition.
int vl_tyrell_raw_get(const VLTyrellRawView* view,int32_t index,int32_t public_flag,
                      float ignored_fallback,float* output);
#ifdef __cplusplus
}
#endif
