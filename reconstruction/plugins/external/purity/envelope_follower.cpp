#include "envelope_follower.h"
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>

static_assert(sizeof(VLPurityEnvelopeFollower) == 32);
static_assert(offsetof(VLPurityEnvelopeFollower, position) == 8);
static_assert(offsetof(VLPurityEnvelopeFollower, increment) == 20);
namespace {
double clip_position(double value) {
    value = value + -255.0;
    auto bits = std::bit_cast<std::uint64_t>(value);
    bits &= std::uint64_t{0} - (bits >> 63);
    value = std::bit_cast<double>(bits) + 255.0;
    bits = std::bit_cast<std::uint64_t>(value);
    bits &= ~(std::uint64_t{0} - (bits >> 63));
    return std::bit_cast<double>(bits) + 0.0;
}
float interpolate(double position, const float* curve, bool release) {
    const float x = static_cast<float>(position);
    const float shifted = x + 12582912.0f;
    const int index = std::bit_cast<std::int32_t>(
        std::bit_cast<std::uint32_t>(shifted) - 0x4b400000U);
    const float fraction = x - static_cast<float>(index);
    const float y0 = curve[index], y1 = curve[index + 1];
    const float y2 = curve[index + 2], y3 = curve[index + 3];
    const float cubic = (y3 + (y1 - y2) * 3.0f) - y0;
    // The release vector path adds a negative multiplier; the decay scalar
    // path subtracts a positive one. Keep their native operation ordering.
    float quadratic = y0 + y0;
    quadratic = release ? quadratic + y1 * -5.0f : quadratic - y1 * 5.0f;
    quadratic = y2 * 4.0f + quadratic;
    quadratic = quadratic - y3;
    float result = cubic * fraction;
    result = quadratic + result;
    result = fraction * result;
    result = (y2 - y0) + result;
    result = fraction * result;
    result = result * 0.5f;
    return y1 + result;
}
}
extern "C" int vl_purity_envelope_follow(float attack, float sustain,
    VLPurityEnvelopeFollower* state, const double* steps,
    const float* curve, int32_t count) {
    if (!state || !steps || !curve || count < 1 || count > 8192 ||
        !std::isfinite(attack) || attack < 0 || attack > 1 ||
        !std::isfinite(sustain) || sustain < 0 || sustain > 1 ||
        state->stage < 0 || state->stage > 5 ||
        !std::isfinite(state->position) || state->position < 0 || state->position > 255 ||
        !std::isfinite(state->level) || !std::isfinite(state->increment) ||
        !std::isfinite(state->release_scale) || std::fabs(state->release_scale) > 2) return 0;
    for (int i = 0; i < 3; ++i)
        if (!std::isfinite(steps[i]) || steps[i] < 0 || steps[i] > 510) return 0;
    for (int i = 0; i < 259; ++i)
        if (!std::isfinite(curve[i]) || curve[i] < 0 || curve[i] > 1) return 0;
    VLPurityEnvelopeFollower next;
    std::memcpy(&next, state, sizeof next);
    const float frames = static_cast<float>(count);
    if (next.stage == 1) {
        if (attack > 0 && next.position < 255) {
            const float before = static_cast<float>(next.position / -255.0);
            next.position = clip_position(next.position + steps[0]);
            next.increment = (static_cast<float>(next.position / 255.0) + before) / frames;
            std::memcpy(state, &next, sizeof next);
            return 1;
        }
        next.stage = 2;
        next.position = 255;
        next.level = 1;
    }
    if (next.stage == 2) {
        if (next.position > 0) {
            const float before = interpolate(next.position, curve, false);
            next.position = clip_position(next.position - steps[1]);
            const float after = interpolate(next.position, curve, false);
            next.increment = ((1.0f - sustain) * (after - before)) / frames;
        } else {
            next.stage = 3;
            next.position = 255;
        }
    } else if (next.stage == 5) {
        const double before_position = next.position;
        next.position = clip_position(next.position - steps[2]);
        next.increment = (next.release_scale *
            (interpolate(next.position, curve, true) - interpolate(before_position, curve, true))) / frames;
    }
    if (next.stage == 3) next.increment = (sustain - next.level) / frames;
    std::memcpy(state, &next, sizeof next);
    return 1;
}
