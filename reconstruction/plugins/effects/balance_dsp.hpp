#pragma once

// Independent, bounded reconstruction of the installed Balance DSP callback.
// This is not a plugin factory, editor, or state/automation implementation.
// Verified domain: finite float stereo input/coefficients, nonnegative frame
// counts at tested sizes 0..1024, finite nonnegative slew limit and zero floor,
// pan -128..128, volume 0..a positive maximum, parameter flags 1/2. Exactly
// identical source/destination buffers are supported; partial overlap, NaN/Inf,
// other flags and larger frame counts are outside the differential proof.
#include <array>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace veggie_loops::balance {

struct State {
  std::array<float, 4> current{};
  std::array<double, 4> target{};
  std::array<float, 4> blockStart{};
  std::array<float, 4> increment{};
  std::array<float, 2> meters{};
};

struct Controls {
  std::array<std::int32_t, 2> raw{};
  double panUnit = 0;
  double panSigned = 0;
  double volumeUnit = 0;
  double panScale = 0;
  // Constructor math observed in this exact installed version.
  double normalization = 1.0 / (std::cos(0.7853981633974483) * 10.0);
};

// Verified numerical set/get subset of ProcessParam. Native UI flags and knob
// normalization are deliberately outside this API. volumeMaximum is the knob
// maximum supplied by the synthetic replay, not an assumed factory default.
inline std::int32_t parameter(Controls& controls, State& state,
                              std::int32_t index, std::int32_t value,
                              std::uint32_t flags, std::int32_t volumeMaximum) {
  if (index < 0 || index >= 2) return value;
  if (flags & 32) {
    const std::int64_t minimum = index == 0 ? -128 : 0;
    const std::int64_t maximum = index == 0 ? 128 : volumeMaximum;
    value = static_cast<std::int32_t>(static_cast<std::int64_t>(std::nearbyint(
      static_cast<double>(value) * 0x1p-30 * static_cast<double>(maximum - minimum))) + minimum);
  }
  if (flags & 1) {
    controls.raw[index] = value;
    if (index == 0) {
      controls.panUnit = static_cast<float>(static_cast<std::int64_t>(value) + 128) * 0.00390625f;
      controls.panSigned = static_cast<float>(value) * 0.0078125f;
      controls.panScale = (1.0 - std::sin(std::fabs(controls.panUnit - 0.5) *
                                        3.141592653589793) * 0.5) * controls.normalization;
    } else {
      controls.volumeUnit = static_cast<double>(value) / static_cast<double>(volumeMaximum);
    }
    const auto curved = static_cast<float>(std::exp(
      static_cast<double>(static_cast<float>(controls.volumeUnit * 1.25)) *
      2.3978952727983707) - 1.0);
    const double gain = static_cast<double>(curved) * controls.panScale;
    const double angle = (1.0 + controls.panSigned) * 0.7853981633974483;
    state.target[0] = gain * std::cos(angle);
    state.target[1] = gain * std::sin(angle);
    state.target[2] = state.target[3] = 0;
    if (controls.panUnit >= 0.5) state.target[3] = state.target[1] - state.target[0];
    else state.target[2] = state.target[0] - state.target[1];
  } else if (flags & 2) {
    value = controls.raw[index];
  }
  return value;
}

inline std::uint32_t bits(float value) {
  return std::bit_cast<std::uint32_t>(value);
}

inline void slew(float target, float maximumStep, std::int32_t frames,
                 float zeroFloor, float& current, float& start, float& step) {
  start = current;
  step = target - start;
  // The observed branch compares the representation, including negative zero.
  if (bits(step) == 0) return;
  current = target;
  step = step / static_cast<float>(frames);
  if (!(std::fabs(step) > maximumStep)) return;
  step = std::bit_cast<float>(bits(maximumStep) | (bits(step) & 0x80000000u));
  current = start + step * static_cast<float>(frames);
  if (static_cast<std::int32_t>(bits(current) & 0x7fffffffu) <
      static_cast<std::int32_t>(bits(zeroFloor))) {
    current = 0;
    step = -start / static_cast<float>(frames);
  }
}

// Interleaved L/R frames. Exact aliasing is supported; partial overlap is not.
// Returns whether the original vector kernel takes its ramp path.
inline bool matrix(const float* input, float* output, std::int32_t frames,
                   const std::array<float, 4>& initial,
                   const std::array<float, 4>& increment) {
  auto gain = initial;
  const bool ramp = (bits(increment[0]) | bits(increment[1]) |
                     bits(increment[2]) | bits(increment[3])) != 0;
  const bool cross = (bits(gain[2]) | bits(gain[3])) != 0;
  for (std::int32_t i = 0; i < frames; ++i) {
    const float left = input[2 * i];
    const float right = input[2 * i + 1];
    if (ramp || cross) {
      output[2 * i] = left * gain[0] + right * gain[2];
      output[2 * i + 1] = right * gain[1] + left * gain[3];
    } else {
      output[2 * i] = left * gain[0];
      output[2 * i + 1] = right * gain[1];
    }
    if (ramp) {
      for (std::size_t j = 0; j < gain.size(); ++j) gain[j] = increment[j] + gain[j];
    }
  }
  return ramp;
}

inline std::array<float, 2> meter(const float* output, std::int32_t frames) {
  std::array<float, 2> result{};
  const auto vectorFrames = frames > 0 ? frames / 8 * 8 : 0;
  for (std::int32_t i = 0; i < frames; ++i) {
    for (std::size_t channel = 0; channel < 2; ++channel) {
      // The observed NEON tail omits absolute value. Preserve that quirk.
      const float sample = output[2 * i + channel];
      const float candidate = i < vectorFrames ? std::fabs(sample) : sample;
      if (candidate > result[channel]) result[channel] = candidate;
    }
  }
  return result;
}

inline void process(State& state, const float* input, float* output,
                    std::int32_t frames, float maximumStep, float zeroFloor) {
  for (std::size_t i = 0; i < state.current.size(); ++i) {
    slew(static_cast<float>(state.target[i]), maximumStep, frames, zeroFloor,
         state.current[i], state.blockStart[i], state.increment[i]);
  }
  matrix(input, output, frames, state.blockStart, state.increment);
  state.meters = meter(output, frames);
}

} // namespace veggie_loops::balance
