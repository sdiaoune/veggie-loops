#pragma once
#include "balance_native_abi.h"

// Reuses the independently measured FL arm64 C++ binary interface declaration.
// This effect has a separate factory/dylib and its own numerical implementation.
// The default build has no editor. VL_MUTE2_APPKIT_EDITOR adds an independent
// AppKit editor using the verified host bridge; unused generator/voice callbacks
// remain no-ops. GUI, hint flags and native destruction in an optional-editor build require the main
// thread. Refused off-main destruction preserves the instance/view until a main
// retry; keep its numerical state, module and host alive until then. Tick and
// MIDI tick never access GUI; off-main Idle returns before touching editor state.
// Numerical preconditions match mute2_plugin.h; callbacks require serial host
// access. Actual FL application/project/mixer hosting remains a separate gate.
// State callbacks use measured HRESULT32/length32 and wide zeroed completion
// storage, compatible with the real engine TStreamAdapter's 32-bit count writes
// and synthetic 64-bit providers. Application-created stream routing remains open.
namespace veggie_loops::mute2::native {
using Info=veggie_loops::balance::native::Info;
using Stream=veggie_loops::balance::native::Stream;
using Functions=veggie_loops::balance::native::Functions;
using Plugin=veggie_loops::balance::native::Plugin;
}
