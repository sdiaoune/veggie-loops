#pragma once
#include "center_native_abi.h"
// Optional VL_CENTER_APPKIT_EDITOR build: every native destruction requires
// main thread, even before attachment. Off-main DestroyObject refuses without
// releasing ownership; host/context/module stay alive until main retry. Every
// numerical/getter/state/render access is serialized or uses the host mix lock.
// GUI-only fields are main-thread owned; tick/MIDI tick are no-ops. Host
// supplied CPP32/33 mix callbacks must be valid paired methods. Names/storage
// and bounded numeric contracts from center_native_abi.h/center_plugin.h remain
// required. Own editor, metadata/hints/host lifecycle differ from original
// Pascal/VCL; actual FL application and whole-plugin equivalence remain
// unproved.
