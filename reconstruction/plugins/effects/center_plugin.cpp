#include "center_plugin.h"
#include "center_dsp.hpp"
#include <cmath>
#include <cstring>
#include <new>
#include <type_traits>
struct VLCenterPlugin {
  vl::center::Processor numerical;
};
static_assert(sizeof(VLCenterPlugin) == sizeof(vl::center::Processor));
static_assert(offsetof(VLCenterPlugin, numerical) == 0);
static_assert(std::is_trivially_copyable_v<vl::center::Processor>);
namespace {
bool overlapsInstance(const VLCenterPlugin *instance, const void *buffer,
                      size_t bytes) {
  const auto start = reinterpret_cast<uintptr_t>(buffer);
  const auto object = reinterpret_cast<uintptr_t>(instance);
  return start >= object ? start - object < sizeof(*instance)
                         : object - start < bytes;
}
uint32_t readWord(const uint8_t *bytes) {
  uint32_t result = 0;
  for (size_t i = 0; i < 4; ++i)
    result |= uint32_t(bytes[i]) << (8 * i);
  return result;
}
void writeWord(uint8_t *bytes, uint32_t value) {
  for (size_t i = 0; i < 4; ++i)
    bytes[i] = uint8_t(value >> (8 * i));
}
} // namespace
extern "C" VLCenterPlugin *vl_center_create() {
  return new (std::nothrow) VLCenterPlugin;
}
extern "C" void vl_center_destroy(VLCenterPlugin *p) { delete p; }
extern "C" int vl_center_parameter(VLCenterPlugin *p, int32_t index,
                                   int32_t value, uint32_t flags,
                                   int32_t *result) {
  if (!p || !result || index != 0 || (flags & ~35u) || value < 0 ||
      value > ((flags & 32) ? (1 << 30) : 1) ||
      overlapsInstance(p, result, sizeof(*result)))
    return 0;
  *result = p->numerical.parameter(value, flags);
  return 1;
}
extern "C" int vl_center_sample_rate(VLCenterPlugin *p, int32_t rate) {
  if (!p || rate < 8000 || rate > 384000)
    return 0;
  p->numerical.sampleRate(rate);
  return 1;
}
extern "C" int vl_center_resume(VLCenterPlugin *p) {
  if (!p)
    return 0;
  p->numerical.resume();
  return 1;
}
extern "C" int vl_center_render(VLCenterPlugin *p, const float *in, float *out,
                                int32_t frames) {
  if (!p || frames < 0 || frames > 1024 || (frames && (!in || !out)))
    return 0;
  const auto length = size_t(frames) * 8;
  if (overlapsInstance(p, in, length) || overlapsInstance(p, out, length))
    return 0;
  if (in != out) {
    const auto a = reinterpret_cast<uintptr_t>(in),
               b = reinterpret_cast<uintptr_t>(out);
    if ((a >= b ? a - b : b - a) < length)
      return 0;
  }
  for (int32_t i = 0; i < 2 * frames; ++i)
    if (!std::isfinite(in[i]) || std::fabs(in[i]) > 16)
      return 0;
  p->numerical.render(in, out, frames);
  return 1;
}
extern "C" int vl_center_save_state(const VLCenterPlugin *p, uint8_t *bytes,
                                    size_t length) {
  if (!p || !bytes || length != 8 || overlapsInstance(p, bytes, 8))
    return 0;
  writeWord(bytes, 1);
  writeWord(bytes + 4, uint32_t(p->numerical.enabled));
  return 1;
}
extern "C" int vl_center_restore_state(VLCenterPlugin *p, const uint8_t *bytes,
                                       size_t length) {
  if (!p || !bytes || length != 8 || overlapsInstance(p, bytes, 8))
    return 0;
  const auto version = readWord(bytes), enabled = readWord(bytes + 4);
  if (version > 1 || enabled > 1)
    return 0;
  p->numerical.enabled = int32_t(enabled);
  return 1;
}
extern "C" int vl_center_get_filter_state(const VLCenterPlugin *p, double *v) {
  if (!p || !v || overlapsInstance(p, v, 4 * sizeof(double)))
    return 0;
  std::memcpy(v, p->numerical.position.data(), 2 * sizeof(double));
  std::memcpy(v + 2, p->numerical.velocity.data(), 2 * sizeof(double));
  return 1;
}
