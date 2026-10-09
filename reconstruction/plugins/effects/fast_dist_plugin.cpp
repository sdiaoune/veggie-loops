#include "fast_dist_plugin.h"
#include "fast_dist_dsp.hpp"
#include <cstring>
#include <new>
struct VLFastDistPlugin {
  veggie_loops::fast_dist::Processor numerical;
  const veggie_loops::fast_dist::Tables *tables;
  bool interpolate;
};
namespace {
constexpr std::array<int32_t, 5> minimum{64, 1, 0, 0, 0},
    maximum{192, 10, 1, 128, 128};
bool overlapsInstance(const VLFastDistPlugin *p, const void *buffer,
                      size_t bytes) {
  const auto start = reinterpret_cast<uintptr_t>(buffer);
  const auto instance = reinterpret_cast<uintptr_t>(p);
  return start >= instance ? start - instance < sizeof(*p)
                           : instance - start < bytes;
}
bool validRaw(int32_t index, int32_t value) {
  return value >= minimum[size_t(index)] && value <= maximum[size_t(index)];
}
uint32_t readWord(const uint8_t *bytes) {
  uint32_t word = 0;
  for (size_t i = 0; i < 4; ++i)
    word |= uint32_t(bytes[i]) << (i * 8);
  return word;
}
void writeWord(uint8_t *bytes, uint32_t word) {
  for (size_t i = 0; i < 4; ++i)
    bytes[i] = uint8_t(word >> (i * 8));
}
} // namespace
extern "C" VLFastDistPlugin *vl_fast_dist_create(int32_t quality) {
  if (quality < 0 || quality > 1)
    return nullptr;
  static const veggie_loops::fast_dist::Tables tables;
  return new (std::nothrow) VLFastDistPlugin{{}, &tables, quality != 0};
}
extern "C" void vl_fast_dist_destroy(VLFastDistPlugin *p) { delete p; }
extern "C" int vl_fast_dist_quality(VLFastDistPlugin *p, int32_t quality) {
  if (!p || quality < 0 || quality > 1)
    return 0;
  p->interpolate = quality != 0;
  return 1;
}
extern "C" int vl_fast_dist_parameter(VLFastDistPlugin *p, int32_t index,
                                      int32_t value, uint32_t flags,
                                      int32_t *result) {
  if (!p || !result || index < 0 || index >= 5 || (flags & ~35u) ||
      overlapsInstance(p, result, sizeof(*result)))
    return 0;
  if (flags & 32u) {
    if (value < 0 || value > (1 << 30))
      return 0;
    const double scaled = double(value) * 0x1p-30;
    value = int32_t(std::nearbyint(scaled * double(maximum[size_t(index)] -
                                                   minimum[size_t(index)]))) +
            minimum[size_t(index)];
  }
  if (((flags & 1u) || !(flags & 2u)) && !validRaw(index, value))
    return 0;
  if (flags & 1u)
    p->numerical.set(index, value);
  else if (flags & 2u)
    value = p->numerical.raw[size_t(index)];
  *result = value;
  return 1;
}
extern "C" int vl_fast_dist_render(VLFastDistPlugin *p, const float *in,
                                   float *out, int32_t frames) {
  if (!p || frames < 0 || frames > 1024 || (frames && (!in || !out)))
    return 0;
  const size_t bytes = size_t(frames) * 8;
  if (overlapsInstance(p, in, bytes) || overlapsInstance(p, out, bytes))
    return 0;
  if (in != out) {
    const auto a = reinterpret_cast<uintptr_t>(in),
               b = reinterpret_cast<uintptr_t>(out);
    if ((a >= b ? a - b : b - a) < bytes)
      return 0;
  }
  for (int32_t i = 0; i < 2 * frames; ++i)
    if (!std::isfinite(in[i]) || std::fabs(in[i]) > 16)
      return 0;
  p->numerical.render(*p->tables, in, out, frames, p->interpolate);
  return 1;
}
extern "C" int vl_fast_dist_save_state(const VLFastDistPlugin *p,
                                       uint8_t *bytes, size_t length) {
  if (!p || !bytes || length != 20 || overlapsInstance(p, bytes, length))
    return 0;
  for (size_t i = 0; i < 5; ++i)
    writeWord(bytes + i * 4, uint32_t(p->numerical.raw[i]));
  return 1;
}
extern "C" int vl_fast_dist_restore_state(VLFastDistPlugin *p,
                                          const uint8_t *bytes, size_t length) {
  if (!p || !bytes || length != 20 || overlapsInstance(p, bytes, length))
    return 0;
  std::array<int32_t, 5> raw{};
  for (int32_t i = 0; i < 5; ++i) {
    const auto word = readWord(bytes + size_t(i) * 4);
    if (word > uint32_t(maximum[size_t(i)]) ||
        word < uint32_t(minimum[size_t(i)]))
      return 0;
    raw[size_t(i)] = int32_t(word);
  }
  auto next = p->numerical;
  next.raw = raw;
  next.set(0, raw[0]);
  p->numerical = next;
  return 1;
}
extern "C" int vl_fast_dist_get_coefficients(const VLFastDistPlugin *p,
                                             float *values) {
  if (!p || !values || overlapsInstance(p, values, 3 * sizeof(float)))
    return 0;
  values[0] = p->numerical.dry;
  values[1] = p->numerical.wet;
  values[2] = p->numerical.multiplier;
  return 1;
}
