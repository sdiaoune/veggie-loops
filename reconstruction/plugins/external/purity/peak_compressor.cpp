#include "peak_compressor.h"
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

static_assert(sizeof(VLPurityPeakCompressor) == 64);
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
extern "C" int vl_purity_peak_compress(VLPurityPeakCompressor* state,
    float* left, float* right, int32_t count) {
    if (!state || count < 0 || count > 8192 || !std::isfinite(state->sample_rate) ||
        state->sample_rate < 8000 || state->sample_rate > 192000 ||
        !unit(state->threshold) || !unit(state->ratio) || !unit(state->release) ||
        !unit(state->target_threshold) || !unit(state->target_ratio) || !unit(state->target_release) ||
        !unit(state->gain)) return 0;
    if (count > 0) {
        if (!left || !right) return 0;
        const auto bytes = static_cast<std::size_t>(count) * sizeof(float);
        if ((left != right && overlap(left, bytes, right, bytes)) ||
            overlap(state, sizeof *state, left, bytes) || overlap(state, sizeof *state, right, bytes)) return 0;
        for (int i = 0; i < count; ++i)
            if (!std::isfinite(left[i]) || std::fabs(left[i]) > 4 ||
                !std::isfinite(right[i]) || std::fabs(right[i]) > 4) return 0;
    }
    for (int i = 0; i < count; ++i) {
        state->threshold = smooth(state->threshold, state->target_threshold);
        state->ratio = smooth(state->ratio, state->target_ratio);
        state->release = smooth(state->release, state->target_release);
        const float threshold = state->threshold * 0.99f + 0.01f;
        float compressed = threshold + (1.0f - threshold) / (state->ratio * 19.0f + 1.0f);
        const float reduction = 1.0f - compressed;
        const float peak = (std::fabs(left[i]) + std::fabs(right[i])) * 0.5f * 32768.0f;
        if (peak > threshold * 32767.5f) {
            state->gain = state->gain + reduction / (state->sample_rate * -0.001f);
            if (state->gain < compressed) state->gain = compressed;
        } else if (state->gain < 1.0f) {
            const float release_squared = state->release * state->release;
            const float release_cubed = state->release * release_squared;
            const int release_ms = static_cast<int>(release_cubed * 4990.0f + 0.5f) + 10;
            const float divisor = (state->sample_rate * static_cast<float>(release_ms)) * 0.001f;
            state->gain = reduction / divisor + state->gain;
            compressed = 1.0f;
            if (state->gain > compressed) state->gain = compressed;
        }
        const float gain = (1.0f / threshold) * state->gain;
        left[i] = left[i] * gain;
        right[i] = gain * right[i];
    }
    state->dirty = 0;
    return 1;
}
