#pragma once
#include "balance_native_abi.h"

// Reuses the independently measured FL arm64 C++ binary interface declaration.
// This effect has a separate factory/dylib and its own numerical implementation.
// No editor is advertised. UI and unused generator/voice callbacks are no-ops.
// Numerical preconditions match mute2_plugin.h; callbacks require serial host
// access. Actual FL application/project/mixer hosting remains a separate gate.
// State callbacks currently use synthetic 64-bit length/completion-count streams;
// the installed application's native stream count width remains unverified.
namespace veggie_loops::mute2::native {
using Info=veggie_loops::balance::native::Info;
using Stream=veggie_loops::balance::native::Stream;
using Functions=veggie_loops::balance::native::Functions;
using Plugin=veggie_loops::balance::native::Plugin;
}
