#pragma once
#include "balance_native_abi.h"

// Independently written native factory over the measured arm64 C++ boundary.
// All instance access (including getters, streams, rendering, numerical/routing
// updates, registration notifications and destruction) must be serialized by
// the host. Numerical domains match stereo_shaper_plugin.h. Supported dispatch
// contracts are resume2, rate4 and parameter classification52. The optional
// VL_STEREO_SHAPER_APPKIT_EDITOR build adds own AppKit attachment0 and GUI Idle,
// hint flag4, host change/hint/resize callbacks and lock/unlock for UI numerical
// access. Hint flag4 is for main-thread GUI calls outside the host mixer lock.
// In the optional build, ALL native destruction requires the main thread, even
// before editor attachment. Off-main destruction preserves ownership for a
// main-thread retry; keep the plugin, host and module alive until that finishes.
// Tick/MIDI tick never access GUI state. Original VCL and remaining application
// dispatcher/events remain separate reconstruction obligations.
// Side output uses C++ host slot37 -> PascalVMT+0x1f0, packed pointer0/flags32at8,
// flags0/1 lock/unlock and dry-minus-processed addition. Supported topology is
// four outputs (indices0..3). Send transitions unregister/register positive
// indices through FHD73; repetition emits no event. Destruction emits no FHD73,
// matching the measured source fixture; actual host cleanup ownership is open.
// Stream status/completion follow the measured actual engine: signed HRESULT32,
// length32, completion32 in wider zeroed storage. Actual FL application/project/
// mixer and original VCL/editor/full-plugin equivalence remain open.
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
