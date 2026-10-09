#include "soft_clipper_plugin.h"
#include "soft_clipper_dsp.hpp"
#include <bit>
#include <new>
struct VLSoftClipperPlugin {
  vl::soft_clipper::Processor processor;
};
namespace {
// Distance comparisons avoid wrapping end-address arithmetic. Even a zero-frame
// buffer starting inside the live object is rejected before caller storage use.
bool overlapsInstance(const VLSoftClipperPlugin *instance, const void *buffer,
                      size_t bytes) {
  const auto start = reinterpret_cast<uintptr_t>(buffer),
             object = reinterpret_cast<uintptr_t>(instance);
  return start >= object ? start - object < sizeof(*instance)
                         : object - start < bytes;
}
void word(uint8_t *p, uint32_t value) {
  for (size_t i = 0; i < 4; ++i)
    p[i] = uint8_t(value >> (8 * i));
}
uint32_t readWord(const uint8_t *p) {
  uint32_t value = 0;
  for (size_t i = 0; i < 4; ++i)
    value |= uint32_t(p[i]) << (8 * i);
  return value;
}
} // namespace
extern "C" {
VLSoftClipperPlugin *vl_soft_clipper_create(void) {
  return new (std::nothrow) VLSoftClipperPlugin;
}
void vl_soft_clipper_destroy(VLSoftClipperPlugin *p) { delete p; }
int vl_soft_clipper_parameter(VLSoftClipperPlugin *p, int32_t index,
                              int32_t value, uint32_t flags, int32_t *result) {
  if (!p || !result || index < 0 || index > 1 || (flags & ~35u) ||
      overlapsInstance(p, result, sizeof(*result)))
    return 0;
  if (flags & 32) {
    if (value < 0 || value > 0x40000000)
      return 0;
  } else if ((flags & 1) &&
             (value < (index == 0 ? 1 : 0) || value > (index == 0 ? 127 : 160)))
    return 0;
  *result = p->processor.parameter(index, value, flags);
  return 1;
}
int vl_soft_clipper_render(VLSoftClipperPlugin *p, const float *input,
                           float *output, int32_t frames) {
  if (!p || !input || !output || frames < 0 || frames > 1024)
    return 0;
  const auto a = reinterpret_cast<uintptr_t>(input),
             b = reinterpret_cast<uintptr_t>(output), size = size_t(frames) * 8;
  if (overlapsInstance(p, input, size) || overlapsInstance(p, output, size))
    return 0;
  if (a != b && (a < b ? b - a : a - b) < size)
    return 0;
  for (int32_t i = 0; i < 2 * frames; ++i)
    if (!std::isfinite(input[i]) || std::fabs(input[i]) > 16.0f)
      return 0;
  p->processor.render(input, output, frames);
  return 1;
}
int vl_soft_clipper_metering(VLSoftClipperPlugin *p, int enabled) {
  if (!p || (enabled != 0 && enabled != 1))
    return 0;
  p->processor.metering = enabled != 0;
  return 1;
}
int vl_soft_clipper_clear_meters(VLSoftClipperPlugin *p) {
  if (!p)
    return 0;
  p->processor.meters.fill(0);
  return 1;
}
int vl_soft_clipper_get_meters(const VLSoftClipperPlugin *p, float *peaks) {
  if (!p || !peaks || overlapsInstance(p, peaks, 2 * sizeof(float)))
    return 0;
  std::memcpy(peaks, p->processor.meters.data(), 8);
  return 1;
}
int vl_soft_clipper_save_state(const VLSoftClipperPlugin *p, void *bytes,
                               size_t size) {
  if (!p || !bytes || size != 8 || overlapsInstance(p, bytes, size))
    return 0;
  auto *out = static_cast<uint8_t *>(bytes);
  for (size_t i = 0; i < 2; ++i)
    word(out + 4 * i, std::bit_cast<uint32_t>(p->processor.raw[i]));
  return 1;
}
int vl_soft_clipper_restore_state(VLSoftClipperPlugin *p, const void *bytes,
                                  size_t size) {
  if (!p || !bytes || size != 8 || overlapsInstance(p, bytes, size))
    return 0;
  auto *in = static_cast<const uint8_t *>(bytes);
  const std::array<int32_t, 2> raw{std::bit_cast<int32_t>(readWord(in)),
                                   std::bit_cast<int32_t>(readWord(in + 4))};
  if (raw[0] < 1 || raw[0] > 127 || raw[1] < 0 || raw[1] > 160)
    return 0;
  for (int32_t i = 0; i < 2; ++i)
    p->processor.parameter(i, raw[size_t(i)], 1);
  return 1;
}
}
