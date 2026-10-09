#pragma once
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
namespace vl::center {
// Independently written, unchecked private numerical model. Valid
// bool/normalized parameter inputs, finite samples, supported positive rates
// and external valid buffers are caller preconditions. Every instance operation
// is serialized.
struct Processor {
  int32_t enabled = 1;
  float step = 0x1.327c76p-18f;
  std::array<double, 2> position{}, velocity{};
  void sampleRate(int32_t rate) {
    step = float((44100.0 / double(rate)) * 0x1.327c766a8cde1p-18);
  }
  void resume() {
    position = {};
    velocity = {};
  }
  int32_t parameter(int32_t value, uint32_t flags) {
    if (flags & 32)
      value = int32_t(std::nearbyint(double(value) * 0x1p-30));
    if (flags & 1)
      enabled = value;
    else if (flags & 2)
      value = enabled;
    return value;
  }
  void render(const float *input, float *output, int32_t frames) {
    if (!enabled) {
      if (input != output && frames)
        std::memcpy(output, input, size_t(frames) * 8);
      return;
    }
    for (int32_t i = 0; i < frames; ++i)
      for (size_t c = 0; c < 2; ++c) {
        const double sample = input[2 * i + c];
        velocity[c] += (sample - position[c]) * double(step);
        position[c] += velocity[c];
        velocity[c] *= double(0x1.eb851ep-1f);
        output[2 * i + c] = float(sample - position[c]);
      }
    for (size_t c = 0; c < 2; ++c) {
      if (std::fabs(position[c]) < 0x1p-24)
        position[c] = 0;
      if (std::fabs(velocity[c]) < 0x1p-24)
        velocity[c] = 0;
    }
  }
};
} // namespace vl::center
