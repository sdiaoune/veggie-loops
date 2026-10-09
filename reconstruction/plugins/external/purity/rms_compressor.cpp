#include "rms_compressor.h"
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

static_assert(sizeof(VLPurityRMSCompressor) == 72);
static_assert(offsetof(VLPurityRMSCompressor, base) == 0);
static_assert(offsetof(VLPurityRMSCompressor, detector) == 64);
static_assert(offsetof(VLPurityPeakCompressor, threshold) == 32);
static_assert(offsetof(VLPurityPeakCompressor, dirty) == 56);
static_assert(offsetof(VLPurityPeakCompressor, gain) == 60);
namespace {
float smooth(float current, float target) {
    if (target > current) {
        const float difference = (current + 0.0003f) - target;
        auto bits = std::bit_cast<std::uint32_t>(difference);
        bits &= std::uint32_t{0} - (bits >> 31);
        return target + std::bit_cast<float>(bits);
    }
    if (target < current) {
        const float difference = (current + -0.0003f) - target;
        auto bits = std::bit_cast<std::uint32_t>(difference);
        bits &= ~(std::uint32_t{0} - (bits >> 31));
        return target + std::bit_cast<float>(bits);
    }
    return current;
}
bool overlap(const void* a, std::size_t as, const void* b, std::size_t bs) {
    const auto av = reinterpret_cast<std::uintptr_t>(a), bv = reinterpret_cast<std::uintptr_t>(b);
    if (av > std::numeric_limits<std::uintptr_t>::max() - as ||
        bv > std::numeric_limits<std::uintptr_t>::max() - bs) return true;
    return av < bv + bs && bv < av + as;
}
bool unit(float v) { return std::isfinite(v) && v >= 0 && v <= 1; }
}
extern "C" int vl_purity_rms_compress(VLPurityRMSCompressor* state,
    float* left, float* right, int32_t count) {
    if (!state || count < 0 || count > 8192 || !std::isfinite(state->base.sample_rate) ||
        state->base.sample_rate < 8000 || state->base.sample_rate > 192000 ||
        !unit(state->base.threshold) || !unit(state->base.ratio) || !unit(state->base.release) ||
        !unit(state->base.target_threshold) || !unit(state->base.target_ratio) || !unit(state->base.target_release) ||
        !unit(state->base.gain) || !std::isfinite(state->detector) ||
        state->detector < 0 || state->detector > 131072) return 0;
    if (count > 0) {
        if (!left || !right) return 0;
        const auto bytes = static_cast<std::size_t>(count) * sizeof(float);
        if ((left != right && overlap(left, bytes, right, bytes)) ||
            overlap(state, sizeof *state, left, bytes) || overlap(state, sizeof *state, right, bytes)) return 0;
        for (int i = 0; i < count; ++i)
            if (!std::isfinite(left[i]) || std::fabs(left[i]) > 4 ||
                !std::isfinite(right[i]) || std::fabs(right[i]) > 4) return 0;
    }
    const float detector_coefficient = (state->base.sample_rate * 0.000333333f) * 0.001f;
    for (int i = 0; i < count; ++i) {
        state->base.threshold = smooth(state->base.threshold, state->base.target_threshold);
        state->base.ratio = smooth(state->base.ratio, state->base.target_ratio);
        state->base.release = smooth(state->base.release, state->base.target_release);
        const float threshold = state->base.threshold * 0.99f + 0.01f;
        float compressed = threshold + (1.0f - threshold) / (state->base.ratio * 19.0f + 1.0f);
        const float reduction = 1.0f - compressed;
        const float peak = (std::fabs(left[i]) + std::fabs(right[i])) * 0.5f * 32768.0f;
        state->detector = state->detector + detector_coefficient * (peak - state->detector);
        if (state->detector > threshold * 32767.5f) {
            state->base.gain = state->base.gain + reduction / (state->base.sample_rate * -0.001f);
            if (state->base.gain < compressed) state->base.gain = compressed;
        } else if (state->base.gain < 1.0f) {
            const float release_squared = state->base.release * state->base.release;
            const float release_cubed = state->base.release * release_squared;
            const int release_ms = static_cast<int>(release_cubed * 4990.0f + 0.5f) + 10;
            const float divisor = (state->base.sample_rate * static_cast<float>(release_ms)) * 0.001f;
            state->base.gain = reduction / divisor + state->base.gain;
            compressed = 1.0f;
            if (state->base.gain > compressed) state->base.gain = compressed;
        }
        const float gain = (1.0f / threshold) * state->base.gain;
        left[i] = left[i] * gain;
        right[i] = gain * right[i];
    }
    state->base.dirty = 0;
    return 1;
}
