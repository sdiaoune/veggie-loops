#pragma once
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
// Independently written bounded numerical model. Public validation and
// serialized access contracts are in soft_clipper_plugin.h; this unchecked
// class expects valid indices/ranges/finite buffers and the documented
// compiler/FP settings. Native factory, UI, host streams and application parity
// are separate gates.
namespace vl::soft_clipper {
struct Processor {
  std::array<int32_t, 2> raw{100, 128};
  std::array<float, 3> knee{0x1.9p-1f, 0x1.cp-3f, 0x1.24924ap+2f};
  float gain = 1;
  std::array<float, 2> meters{};
  bool metering = true;
  int32_t parameter(int32_t index, int32_t value, uint32_t flags) {
    if (flags & 32) {
      const int32_t minimum = index == 0 ? 1 : 0,
                    maximum = index == 0 ? 127 : 160;
      value = int32_t(std::nearbyint(double(value) * 0x1p-30 *
                                     double(maximum - minimum))) +
              minimum;
    }
    if (flags & 1) {
      raw[size_t(index)] = value;
      const float unit = float(value) * 0x1p-7f;
      if (index == 0) {
        knee[0] = unit;
        knee[1] = 1.0f - unit;
        if (knee[1] <= 0)
          knee[1] = 0x1p-16f;
        knee[2] = 1.0f / knee[1];
      } else
        gain = unit == 1.0f
                   ? 1.0f
                   : float((std::exp(double(unit * 0x1.32ee3cp+1f)) - 1.0) *
                           double(0x1.99999ap-4f));
    } else if (flags & 2)
      value = raw[size_t(index)];
    return value;
  }
  void render(const float *input, float *output, int32_t frames) {
    if (input != output)
      std::memcpy(output, input, size_t(frames) * 8);
    for (int32_t i = 0; i < 2 * frames; ++i) {
      const float source = output[i];
      float magnitude = std::fabs(source);
      if (magnitude > knee[0]) {
        const float argument = (knee[0] - magnitude) * knee[2];
        magnitude = float(double(knee[0]) +
                          double(knee[1]) * (1.0 - std::exp(double(argument))));
      }
      output[i] = source < 0 ? -magnitude : magnitude;
    }
    if (metering) {
      const auto vectorFrames = frames / 8 * 8;
      std::array<float, 2> peak{};
      for (int32_t i = 0; i < frames; ++i)
        for (size_t c = 0; c < 2; ++c) {
          const float candidate = i < vectorFrames
                                      ? std::fabs(output[2 * i + c])
                                      : output[2 * i + c];
          if (candidate > peak[c])
            peak[c] = candidate;
        }
      for (size_t c = 0; c < 2; ++c)
        if (peak[c] > meters[c])
          meters[c] = peak[c];
    }
    if (gain != 1.0f)
      for (int32_t i = 0; i < 2 * frames; ++i)
        output[i] *= gain;
  }
};
} // namespace vl::soft_clipper
