#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
namespace veggie_loops::fast_dist {
// Independently computed tables, not copied target table data. Verified math
// order from pinned FLEngine initializer0x3e5980; default nearest-even FP.
struct Tables {
  using Row = std::array<int16_t, 8194>;
  std::array<std::array<Row, 10>, 2> values{};
  Tables() {
    constexpr double toDb = 0x1.15f2ced384f28p+3;
    constexpr double fromDb = 0x1.d791c5f888824p-4;
    for (int32_t j = 0; j < 10; ++j) {
      const size_t threshold = size_t(9 - j);
      const double slope = double(int64_t(j) + 1) * 0.1;
      const double lift = double(int64_t(9 - j)) * 1.6;
      for (int32_t index = 0; index < 8192; ++index) {
        const double input = double(index) / 8191.0;
        double level = input != 0.0 ? std::log(input) * toDb : -10000.0;
        if (level >= -25.0)
          level = -25.0 + (level - -25.0) * slope;
        if (level <= -lift)
          level += lift;
        const double output = std::exp(level * fromDb);
        values[0][threshold][size_t(index) + 1] =
            int16_t(int64_t(std::nearbyint(output * 32767.0)));
        const double shaped = input != 0.0 ? std::log(input) * toDb : -1000.0;
        const double base = -shaped;
        const double power = 0.8 + double(j) * 0.02;
        const double curved =
            base == 0.0 ? 0.0 : std::exp(power * std::log(base));
        const double second = std::exp(-curved * fromDb);
        values[1][threshold][size_t(index) + 1] =
            int16_t(int64_t(std::nearbyint(second * 32767.0)));
      }
      for (auto &type : values) {
        type[threshold][0] = type[threshold][1];
        type[threshold][8193] = type[threshold][8192];
      }
    }
  }
  const int16_t *row(int32_t type, int32_t threshold) const {
    return values[size_t(type)][size_t(threshold - 1)].data() + 1;
  }
};
inline void integerProcess(const float *input, float *output, int32_t count,
                           const int16_t *table, float dry, float wet,
                           float multiplier) {
  multiplier *= 8191.0f;
  wet *= 0x1p-15f;
  for (int32_t index = 0; index < count; ++index) {
    const float value = input[index];
    const int32_t sign = value < 0.0f ? -1 : 1;
    const float scaled = std::fabs(value) * multiplier;
    const int64_t position = std::min(int64_t(double(scaled)), int64_t(8191));
    const int64_t sample = int64_t(table[position]) * sign;
    const float shaped = float(sample) * wet;
    const float clean = value * dry;
    output[index] = clean + shaped;
  }
}
inline void interpolatedProcess(const float *input, float *output,
                                int32_t count, const int16_t *table, float dry,
                                float wet, float multiplier) {
  multiplier *= 8191.0f;
  wet *= 0x1p-15f;
  for (int32_t index = 0; index < count; ++index) {
    const float value = input[index];
    const float scaled = value * multiplier;
    int32_t position = int32_t(int64_t(double(scaled)));
    const float fraction = scaled - float(position);
    const float clean = value * dry;
    float shaped;
    if (position < 0) {
      position = std::min(-position, 8191);
      const float first = float(table[position]);
      const float difference = float(table[position + 1]) - first;
      const float interpolated = first - difference * fraction;
      shaped = 0.0f - interpolated;
    } else {
      position = std::min(position, 8191);
      const float first = float(table[position]);
      const float difference = float(table[position + 1]) - first;
      shaped = first + difference * fraction;
    }
    shaped *= wet;
    output[index] = clean + shaped;
  }
}
struct Processor {
  std::array<int32_t, 5> raw{128, 10, 0, 128, 128};
  float dry = 0, wet = 1, multiplier = 1;
  static float gain(int32_t value) {
    const float normalized = float(value) * 0x1p-7f;
    if (normalized == 1.0f)
      return 1.0f;
    const float exponent = normalized * 0x1.32ee3cp+1f;
    return float((std::exp(double(exponent)) - 1.0) * double(0x1.99999ap-4f));
  }
  void set(int32_t index, int32_t value) {
    raw[size_t(index)] = value;
    if (index == 0 || index == 3 || index == 4) {
      multiplier = gain(raw[0]);
      const float post = gain(raw[4]), mix = gain(raw[3]);
      wet = mix * post;
      dry = (post - wet) * multiplier * post;
    }
  }
  void render(const Tables &tables, const float *input, float *output,
              int32_t frames, bool interpolate) const {
    if (interpolate)
      interpolatedProcess(input, output, frames * 2, tables.row(raw[2], raw[1]),
                          dry, wet, multiplier);
    else
      integerProcess(input, output, frames * 2, tables.row(raw[2], raw[1]), dry,
                     wet, multiplier);
  }
};
} // namespace veggie_loops::fast_dist
