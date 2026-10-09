#pragma once
#include "balance_native_abi.h"
// Independent arm64 C++ factory candidate. Every numerical getter/parameter/
// state/render/destruction access is serialized or protected by the host mix
// lock. Default build has no editor. Original
// Pascal/VCL/name/metadata/remaining dispatch equivalence and actual
// application/project/mixer hosting are separate gates. Caller
// audio/name/stream storage is valid and external to the factory and numerical
// objects. Name capacity>=8bytes. Host addresses are not validated. Stream
// HRESULT/length/count widths32; state uses two4-byte transfers.
namespace veggie_loops::center::native {
using Info = veggie_loops::balance::native::Info;
using Stream = veggie_loops::balance::native::Stream;
using Functions = veggie_loops::balance::native::Functions;
using Plugin = veggie_loops::balance::native::Plugin;
} // namespace veggie_loops::center::native
