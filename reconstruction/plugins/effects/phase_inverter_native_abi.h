#pragma once
#include "balance_native_abi.h"

// Independent native factory using the measured FL arm64 C++ binary interface.
// The default build has no editor; VL_PHASE_INVERTER_APPKIT_EDITOR adds the
// independently written AppKit editor and verified host bridge. GUI, hints and
// all native destruction in an optional-editor build require the main thread. Refused off-main
// destruction preserves instance/view for a main-thread retry; keep numerical
// state, host and module alive until then. Tick/MIDI tick do no GUI work; Idle
// returns before editor/host access off-main. Unused generator, voice and MIDI
// operations are explicit no-ops. Numerical calls and
// mutable state require serialized host access, as in phase_inverter_plugin.h.
// Stream transfers use measured signed HRESULT32/length32 and wide zeroed count
// storage for the actual engine's 32-bit completion writes. Actual application,
// project/mixer integration and original VCL editor behavior are separate gates.
namespace veggie_loops::phase_inverter::native {
using Info=veggie_loops::balance::native::Info;
using Stream=veggie_loops::balance::native::Stream;
using Functions=veggie_loops::balance::native::Functions;
using Plugin=veggie_loops::balance::native::Plugin;
}
