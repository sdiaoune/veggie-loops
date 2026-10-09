#pragma once
#include "balance_native_abi.h"
// See fast_dist_plugin.h for this effect's control, input/frame, alias and FP
// contracts. balance_native_abi.h supplies the shared protocol layout.
// Private own no-editor C++ factory bridge. Numerical rendering initially uses
// integer-quality0; original application host-quality selection is unproved.
// ALL instance access including getters/state/render/destruction is serialized
// or host mix locked. Valid external caller audio/state/name/stream storage;
// name capacity>=10bytes. Signed HRESULT32,len/count32;state single20byte
// transfer. Original Pascal/VCL/metadata/names/base events/remaining dispatch,
// general provider/failed-write/extra destructors/application/full parity open.
namespace veggie_loops::fast_dist::native {
using Info = veggie_loops::balance::native::Info;
using Stream = veggie_loops::balance::native::Stream;
using Functions = veggie_loops::balance::native::Functions;
using Plugin = veggie_loops::balance::native::Plugin;
} // namespace veggie_loops::fast_dist::native
