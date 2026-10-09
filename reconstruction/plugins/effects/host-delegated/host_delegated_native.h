#pragma once
#include "fast_dist_native_abi.h"
// Separately compiled optional no-editor C++ factory. fast_dist_plugin.h defines
// Fast Dist numerical/control/FP domains; Balance supplies protocol layout only.
// Controls/coefficient arithmetic are independent; rendered DSP is delegated to
// provided immutable C++ host VMT ordinal24, signature below. No quality flags,
// native globals, independent table processing or common-host changes are used.
// Host/VMT/callback remains borrowed/live through destruction; callbacks are
// nonthrowing, synchronous and nonreentrant. ALL instance/host access is serial
// or protected by the caller host mix lock. External valid audio/state/name/
// stream buffers must not overlap instance/host/VMT storage. Frames0..1024,
// finite stereo abs(input)<=16; exact alias/disjoint only; null samples at0 only.
// Partial/instance alias and unsupported audio reject before copy/host callback.
// Tested nearest-even, gradual, nontrapping FP; contraction off/no-fast-math
// and no-builtin-exp/log. Other host FP policies remain unproved.
// One20-byte LE state packet; signed HRESULT32/length-count32; atomic raw restore.
// Names need10 writable bytes. No editor. Actual application host ownership,
// selector production, general ABI/provider/write failures/remaining semantics,
// GUI/VST/AU/reentrancy/RT/whole-plugin equivalence remain open.
namespace veggie_loops::fast_dist::host_delegated {
using Plugin=veggie_loops::fast_dist::native::Plugin;
using DistWave=void(*)(void*,int32_t,int32_t,float*,int32_t,float,float,float);
inline constexpr size_t host_ordinal=24;
}
// Private inspection/validation exports for source-only and adapter fixtures.
extern "C" void* vl_private_fast_dist_host_pointer(veggie_loops::fast_dist::native::Plugin*);
extern "C" int vl_private_fast_dist_host_coefficients(veggie_loops::fast_dist::native::Plugin*,float[3]);
extern "C" int vl_private_fast_dist_host_render(veggie_loops::fast_dist::native::Plugin*,const float*,float*,int32_t);
