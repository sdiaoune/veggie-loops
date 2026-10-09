#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum { VL_TYRELL_XY_CAPACITY=213, VL_TYRELL_XY_RECORD_CAPACITY=64 };
typedef struct VLTyrellXYDescriptor { int32_t full_type; float minimum,maximum; } VLTyrellXYDescriptor;
typedef struct VLTyrellXYRecord {
 int32_t target_id;
 float negative_depth,positive_depth,last_contribution;
} VLTyrellXYRecord;
typedef struct VLTyrellXYState {
 uint32_t internal_count,xy_count,targets_per_control,cell_count;
 int32_t queue_count,dirty;
 float raw[VL_TYRELL_XY_CAPACITY];
 int32_t cell_slots[VL_TYRELL_XY_CAPACITY];
 VLTyrellXYRecord records[VL_TYRELL_XY_RECORD_CAPACITY];
 int32_t marks[VL_TYRELL_XY_CAPACITY];
 float cells[VL_TYRELL_XY_CAPACITY];
 int32_t touched[VL_TYRELL_XY_RECORD_CAPACITY];
} VLTyrellXYState;
typedef struct VLTyrellXYResult { uint32_t touched_count; } VLTyrellXYResult;
// Independent prepared scalar XY consumer. No native class, factory, unit
// callbacks, audio, positive queue processing or natural XY generation.
// Caller-owned valid/stable initialized storage; d has descriptor_count
// readable entries, s/r writable. These three spans must be disjoint.
// descriptor_count==N, 2<=N<=213; X1..4,T1..16, X*T<=64; M1..N cells.
// Exactly X full int32 type2 descriptors in IDs1..N-1; ID0 is not type2.
// Queuecount is0 or-1. Active marks are-1,-3 or0. Every cell slot is0..M-1;
// equal slots explicitly model aliasing. Record target is-1 or0..N-1.
// Raw/cells/endpoints finite in[-1024,1024], min<=max; XY coordinates within
// [-100,100] and depths within[-100,100]. Contributions/scratch/inactive array
// bytes are prior output bits and need not be numerically interpreted.
// Nearest-even, gradual underflow, masked exceptions and strict float order:
// compile without fast math or contraction with supported strict fenv pragma
// semantics. Coordinate sign comparison runs before skipped target records.
// Selected FE masks are tested;
// general floating environments/unmasked traps are not an equivalence claim.
// Returns1 on success,0 on rejection. Rejects atomically, preserving every
// state/result byte. Success preserves untouched fields, inactive records and
// scratch suffix; clears dirty and normalizes queue-1 to0. Every nonnegative
// record contributes and enters scratch, including repeated logical IDs.
// Scratch capacity counts occurrences, not distinct IDs. Final clamps follow
// first occurrence of each logical ID, retaining shared-cell order effects.
// Finite magnitude/order validation uses integer float bits and does not
// evaluate unused values or clear/restore/raise caller FP flags. Actual XY
// operations retain their measured order and exception side effects.
// Serialize all access to shared descriptor/state/result storage.
// This function does not validate arbitrary foreign addresses or lifetimes.
int vl_tyrell_xy_step(const VLTyrellXYDescriptor* d,uint32_t descriptor_count,
 VLTyrellXYState* s,VLTyrellXYResult* r);
#ifdef __cplusplus
}
#endif
