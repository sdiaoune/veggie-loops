#include "center_native_abi.h"
#include "center_plugin.h"
#include <array>
#include <cstring>
#include <mutex>
#include <new>
namespace {
using namespace veggie_loops::center::native;
struct Instance {
  Plugin header{};
  VLCenterPlugin *numerical = vl_center_create();
};
static_assert(offsetof(Instance, header) == 0);
static_assert(offsetof(Instance, numerical) == sizeof(Plugin));
Instance &object(Plugin *p) { return *reinterpret_cast<Instance *>(p); }
const Info &commonInfo() {
  static Info info{};
  static std::once_flag once;
  std::call_once(once, [] {
    info.version = 1;
    info.longName = "VL Center";
    info.shortName = "VL Center";
    info.flags = 1 << 21;
    info.parameterCount = 1;
  });
  return info;
}
bool finishLifetime(Plugin *p) {
  if (!p)
    return false;
  auto *i = &object(p);
  vl_center_destroy(i->numerical);
  i->numerical = nullptr;
  i->~Instance();
  return true;
}
void completeDestructor(Plugin *p) { (void)finishLifetime(p); }
void destroy(Plugin *p) {
  if (finishLifetime(p))
    ::operator delete(static_cast<void *>(p));
}
void deletingDestructor(Plugin *p) { destroy(p); }
intptr_t dispatch(Plugin *p, intptr_t id, intptr_t, intptr_t value) {
  if (id == 2)
    vl_center_resume(object(p).numerical);
  if (id == 4 && value >= 8000 && value <= 384000)
    vl_center_sample_rate(object(p).numerical, int32_t(value));
  return 0;
}
void idle(Plugin *) {}
void state(Plugin *p, Stream *s, int32_t save) {
  if (!s || !s->functions)
    return;
  std::array<uint8_t, 8> bytes{};
  using Transfer = int32_t (*)(Stream *, void *, uint32_t, void *);
  if (save) {
    if (!vl_center_save_state(object(p).numerical, bytes.data(), bytes.size()))
      return;
    const auto write = reinterpret_cast<Transfer>(s->functions[4]);
    if (write) {
      uint64_t count = 0;
      write(s, bytes.data(), 4, &count);
      count = 0;
      write(s, bytes.data() + 4, 4, &count);
    }
  } else {
    const auto read = reinterpret_cast<Transfer>(s->functions[3]);
    uint64_t count = 0;
    if (!read || read(s, bytes.data(), 4, &count) < 0 || count != 4)
      return;
    uint32_t version = 0;
    for (size_t i = 0; i < 4; ++i)
      version |= uint32_t(bytes[i]) << (8 * i);
    if (version > 1)
      return;
    count = 0;
    if (read(s, bytes.data() + 4, 4, &count) >= 0 && count == 4)
      vl_center_restore_state(object(p).numerical, bytes.data(), bytes.size());
  }
}
void name(Plugin *, int32_t section, int32_t index, int32_t, char *out) {
  if (out)
    std::strcpy(out, section == 0 && index == 0 ? "Enabled" : "");
}
int32_t event(Plugin *, int32_t, int32_t, int32_t) { return 0; }
int32_t parameter(Plugin *p, int32_t index, int32_t value, int32_t flags) {
  int32_t result = 0;
  vl_center_parameter(object(p).numerical, index, value, uint32_t(flags) & 35u,
                      &result);
  return result;
}
void effect(Plugin *p, const float *in, float *out, int32_t frames) {
  vl_center_render(object(p).numerical, in, out, frames);
}
void generator(Plugin *, float *, int32_t &n) { n = 0; }
intptr_t voice(Plugin *, void *, intptr_t) { return -1; }
void voiceEnd(Plugin *, intptr_t) {}
int32_t voiceEvent(Plugin *, intptr_t, intptr_t, intptr_t, intptr_t) {
  return 0;
}
int32_t voiceRender(Plugin *, intptr_t, float *, int32_t &n) {
  n = 0;
  return 0;
}
void tick(Plugin *) {}
void midi(Plugin *, int32_t &) {}
void message(Plugin *, intptr_t) {}
const Functions functions{
    destroy,    dispatch,    idle,      state,  name,     event,
    parameter,  effect,      generator, voice,  voiceEnd, voiceEnd,
    voiceEvent, voiceRender, tick,      tick,   midi,     message,
    voiceEvent, voiceEnd,    completeDestructor, deletingDestructor};
} // namespace
extern "C" veggie_loops::balance::native::Plugin *
CreatePlugInstance(void *, intptr_t tag) {
  auto *i = new (std::nothrow) Instance;
  if (!i)
    return nullptr;
  if (!i->numerical) {
    delete i;
    return nullptr;
  }
  i->header.functions = &functions;
  i->header.hostTag = tag;
  i->header.info = &commonInfo();
  return &i->header;
}
