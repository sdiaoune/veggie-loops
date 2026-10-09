#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum { VL_TYRELL_QUEUE_CAPACITY = 213 };
typedef struct VLTyrellQueueDescriptor {
 float minimum, maximum;
 uint32_t flags;
 int32_t pointee_index;
} VLTyrellQueueDescriptor;
typedef struct VLTyrellQueueRecord {
 int32_t identifier;
 float increment;
 int32_t remaining;
 float target;
} VLTyrellQueueRecord;
typedef struct VLTyrellQueueState {
 uint32_t internal_count, special_count, pointee_count;
 uint32_t xy_count, xy_targets_per_control;
 int32_t queue_count, dirty;
 float raw[VL_TYRELL_QUEUE_CAPACITY];
 uint32_t pointee_words[VL_TYRELL_QUEUE_CAPACITY];
 VLTyrellQueueRecord records[VL_TYRELL_QUEUE_CAPACITY];
 int32_t queue[VL_TYRELL_QUEUE_CAPACITY];
 int32_t marks[VL_TYRELL_QUEUE_CAPACITY];
 int32_t changed[VL_TYRELL_QUEUE_CAPACITY];
} VLTyrellQueueState;
typedef struct VLTyrellQueueResult { uint32_t visited_count; } VLTyrellQueueResult;
// One independently reconstructed prepared scalar queue-consumer step.
// No native class, unit callbacks, host timing or XY modulation executes.
// All state bytes are initialized and caller-owned; all access is serialized.
// Counts<=213; special_count<=internal_count; queue_count=-1..special_count.
// Both XY counts must be0. Raw finite |x|<=32768; increments finite |x|<=8192;
// targets and descriptor endpoints finite |x|<=4096; min<=max; remaining=-1..50.
// Each active record has a valid internal ID. Each descriptor's pointee_index
// is -1 or a valid scalar-word index; queued IDs require a present index.
// Equal indexes model aliased native pointees; reverse visitation copy order
// is preserved. Words are scalar bits, not foreign pointers or captured data.
// All descriptor entries are readable and disjoint from state/result; state
// and result are disjoint. All storage remains valid/stable during the call.
// Nearest-even, gradual FP, no fast math/contraction. General FP flags unproved.
// Any rejected call, including unsupported XY or nonfinite/unbounded computed
// current value, preserves state/result. Success1/rejection0. Completion uses
// remaining=-1 and swap-last/revisit; dirty clears after a successful step.
int vl_tyrell_queue_step(const VLTyrellQueueDescriptor*, VLTyrellQueueState*,
 VLTyrellQueueResult*);
#ifdef __cplusplus
}
#endif
