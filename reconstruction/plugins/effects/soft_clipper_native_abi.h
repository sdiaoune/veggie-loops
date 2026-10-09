#pragma once
#include "balance_native_abi.h"
// Independent measured arm64 C++ factory candidate. All numerical/getter/state/
// render/destruction access is serialized. Native application/project/mixer and
// original editor/remaining dispatcher behavior are separate open gates.
// Caller audio/name buffers and stream interfaces are valid external storage,
// outside both factory and numerical objects. This C++ ABI does not validate
// arbitrary host pointers. Optional editor calls and all optional-build native
// destruction require main, even before first attachment; failed worker destroy
// preserves ownership until main retry. Keep host/module alive until then.
// Hint4 is a main GUI operation outside the mix lock. Tick/MIDI tick are no-ops.
// Attach/detach locks only the numerical meter-enable update internally; editor
// create/refresh acquire their own lock, so do not hold an outer nonrecursive lock.
// Stream Read/Write return signed HRESULT32 with length32 and count32 stores.
namespace veggie_loops::soft_clipper::native {
using Info = veggie_loops::balance::native::Info;
using Stream = veggie_loops::balance::native::Stream;
using Functions = veggie_loops::balance::native::Functions;
using Plugin = veggie_loops::balance::native::Plugin;
} // namespace veggie_loops::soft_clipper::native
