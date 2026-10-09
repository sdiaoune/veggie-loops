#pragma once
#include "balance_native_abi.h"

// Independently written native factory over the measured arm64 C++ boundary.
// This default build has no editor. All instance access (including getters,
// streams, rendering and destruction) must be serialized by the host.
// Numerical domains match stereo_shaper_plugin.h. Supported dispatch contracts
// are resume2, rate4 and parameter classification52. Other GUI/application
// dispatcher/events remain separate reconstruction obligations.
// Side output uses the measured C++ host slot37 -> PascalVMT+0x1f0 adapter,
// descriptor pointer0/flags32at8, flags0/1 lock/unlock, and dry-minus-processed
// addition. The supported topology is the four-output fixture (indices0..3).
// Stream status and completion width follow the measured actual engine:
// signed HRESULT32, length32, completion32 in wider zeroed storage. Actual FL
// application/project/mixer and original VCL/editor equivalence remain open.
namespace veggie_loops::stereo_shaper::native {
using Info=veggie_loops::balance::native::Info;
using Stream=veggie_loops::balance::native::Stream;
using Functions=veggie_loops::balance::native::Functions;
using Plugin=veggie_loops::balance::native::Plugin;
#pragma pack(push,4)
struct IOBuffer{float* buffer;std::uint32_t flags;};
#pragma pack(pop)
static_assert(offsetof(IOBuffer,flags)==8 && sizeof(IOBuffer)==12);
}
