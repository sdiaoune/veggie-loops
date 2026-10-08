#include "VLNativeDSP.h"
#include "../../reconstruction/plugins/generators/three_osc_wrapper_core.h"
#include <array>
#include <cmath>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <stdexcept>

namespace {
struct EngineLifetime {
    std::mutex mutex;
    vl_osc_core* anchor = nullptr;
    bool shuttingDown = false;
};
EngineLifetime& engineLifetime();
void fenceEngineShutdown() noexcept {
    auto& lifetime = engineLifetime();
    std::lock_guard<std::mutex> lock(lifetime.mutex);
    lifetime.shuttingDown = true;
}
EngineLifetime& engineLifetime() {
    // Audio/export jobs may still be unwinding when AppKit terminates the
    // process. The raw engine's namespace globals registered their destructors
    // before main. Register our fence later, so it drains bridge calls and makes
    // future calls refuse before those globals are destroyed. Keep the mutex
    // alive until OS reclamation so waiting jobs can safely observe the fence.
    static auto* value = [] {
        auto result = std::make_unique<EngineLifetime>();
        if (std::atexit(fenceEngineShutdown) != 0)
            throw std::runtime_error("Cannot register oscillator shutdown fence");
        return result.release();
    }();
    return *value;
}
// This VL preset uses centered oscillator pans. The app's mixer applies the
// track pan law after folding raw stereo into mono.
void centeredGain(void*, float* left, float* right, float, float volume) {
    *left = volume; *right = volume;
}
}
struct vl_native_oscillator {
    vl_osc_core* core = nullptr;
    vl_osc_voice* voice = nullptr;
    float cents = 0;
    ~vl_native_oscillator() {
        if (core) { vl_osc_core_kill(core, voice); vl_osc_core_destroy(core); }
    }
};
extern "C" vl_native_oscillator* vl_native_oscillator_create(int32_t note, int32_t rate) {
    if (note < 0 || note > 127 || rate < 8000 || rate > 192000) return nullptr;
    try {
        auto& lifetime = engineLifetime();
        std::lock_guard<std::mutex> lock(lifetime.mutex);
        if (lifetime.shuttingDown) return nullptr;
        if (!lifetime.anchor) lifetime.anchor = vl_osc_core_create(centeredGain, nullptr);
        if (!lifetime.anchor) return nullptr;
        auto result = std::make_unique<vl_native_oscillator>();
        result->core = vl_osc_core_create(centeredGain, nullptr);
        if (!result->core || !vl_osc_core_set_sample_rate(result->core, rate)) return nullptr;
        // A new VL blend: main sine, quiet triangle one octave down, and saw
        // one octave up. This is an original preset, not an FL factory preset.
        vl_osc_core_parameter(result->core, 6, 24, 1);
        vl_osc_core_parameter(result->core, 13, 16, 1);
        vl_osc_core_parameter(result->core, 8, 1, 1);
        vl_osc_core_parameter(result->core, 9, -12, 1);
        vl_osc_core_parameter(result->core, 15, 3, 1);
        vl_osc_core_parameter(result->core, 16, 12, 1);
        result->voice = vl_osc_core_trigger(result->core, note);
        if (!result->voice) return nullptr;
        // The recovered FinalPitch coordinate is zero at MIDI72 (C5).
        result->cents = float(note - 72) * 100;
        return result.release();
    } catch (...) { return nullptr; }
}
extern "C" int vl_native_oscillator_render(vl_native_oscillator* value, float* mono, uint32_t frames) {
    if (!value || !mono || frames > 1024) return 0;
    auto& lifetime = engineLifetime();
    std::lock_guard<std::mutex> lock(lifetime.mutex);
    if (lifetime.shuttingDown) return 0;
    std::array<float, 2048> stereo{};
    if (!vl_osc_core_render(value->core, value->voice, value->cents, stereo.data(), frames)) return 0;
    for (uint32_t i = 0; i < frames; ++i) {
        if (!std::isfinite(stereo[2*i]) || !std::isfinite(stereo[2*i+1])) return 0;
    }
    for (uint32_t i = 0; i < frames; ++i) mono[i] = (stereo[2*i] + stereo[2*i+1]) * 0.5f;
    return 1;
}
extern "C" void vl_native_oscillator_destroy(vl_native_oscillator* value) {
    if (!value) return;
    auto& lifetime = engineLifetime();
    std::lock_guard<std::mutex> lock(lifetime.mutex);
    // The raw factory may already be gone after fencing; process termination
    // reclaims any remaining per-note allocation without running its destructor.
    if (!lifetime.shuttingDown) delete value;
}
