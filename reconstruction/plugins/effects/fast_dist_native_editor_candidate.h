#pragma once
#include "fast_dist_native_abi.h"
// Optional VL_FAST_DIST_APPKIT_EDITOR build: every native destruction requires
// main, including before attachment. Off-main destruction preserves the native
// object, numerical state and view for main retry. The host must also retain
// its original wrapper, host/context and module until that retry completes. ALL
// numerical/getter/state/render access is serialized or host mix locked. GUI
// fields are main-thread owned; tick/MIDI tick do not access GUI. Host CPP32/33
// are valid paired mix methods. Hint4 calls are outside the caller mix lock;
// main hints internally lock numerical work and notify after unlock.
// fast_dist_plugin.h numerical/control/alias/FP limits remain required. Own UI
// and host behavior do not establish original
// VCL/application/quality-production or full-plugin parity. Default numerical
// quality remains integer0.
