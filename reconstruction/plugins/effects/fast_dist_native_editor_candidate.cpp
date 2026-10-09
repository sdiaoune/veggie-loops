#include "fast_dist_native_editor_candidate.h"
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
#include "fast_dist_editor.h"
#endif
#include "fast_dist_plugin.h"
#include <array>
#include <cstring>
#include <mutex>
#include <new>
namespace {
using namespace veggie_loops::fast_dist::native;
struct Instance {
  Plugin header{};
  VLFastDistPlugin *numerical = vl_fast_dist_create(0);
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
  void *host = nullptr;
  void *editor = nullptr;
  bool resizePending = false;
#endif
};
static_assert(offsetof(Instance, header) == 0);
static_assert(offsetof(Instance, numerical) == sizeof(Plugin));
Instance &object(Plugin *p) { return *reinterpret_cast<Instance *>(p); }
const Info &commonInfo() {
  static Info info{};
  static std::once_flag once;
  std::call_once(once, [] {
    info.version = 1;
    info.longName = "VL Fast Dist";
    info.shortName = "VL Fast Dist";
    info.flags = 1 << 21;
    info.parameterCount = 5;
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
    info.flags |= 1 << 27;
#endif
  });
  return info;
}
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
template <class T> T hostMethod(Instance &i, size_t slot) {
  if (!i.host)
    return nullptr;
  auto **vmt = *static_cast<void ***>(i.host);
  return vmt ? reinterpret_cast<T>(vmt[slot]) : nullptr;
}
void hostLock(void *c) {
  auto &i = *static_cast<Instance *>(c);
  if (auto f = hostMethod<void (*)(void *, intptr_t)>(i, 32))
    f(i.host, i.header.hostTag);
}
void hostUnlock(void *c) {
  auto &i = *static_cast<Instance *>(c);
  if (auto f = hostMethod<void (*)(void *, intptr_t)>(i, 33))
    f(i.host, i.header.hostTag);
}
void hostChanged(void *c, int32_t index, int32_t value) {
  auto &i = *static_cast<Instance *>(c);
  if (auto f = hostMethod<void (*)(void *, intptr_t, int32_t, int32_t)>(i, 1))
    f(i.host, i.header.hostTag, index, value);
}
void hostHint(void *c, const char *text) {
  auto &i = *static_cast<Instance *>(c);
  if (auto f = hostMethod<void (*)(void *, intptr_t, const char *)>(i, 2))
    f(i.host, i.header.hostTag, text);
}
#endif
void destroy(Plugin *p) {
  if (p) {
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
    if (!vl_fast_dist_editor_main_thread())
      return;
    if (!vl_fast_dist_editor_destroy(object(p).editor))
      return;
#endif
    vl_fast_dist_destroy(object(p).numerical);
    delete &object(p);
  }
}
intptr_t dispatch(Plugin *p, intptr_t id, intptr_t index, intptr_t value) {
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
  if (id == 0) {
    if (!vl_fast_dist_editor_main_thread())
      return 0;
    auto &i = object(p);
    if (value && !i.editor) {
      const VLFastDistEditorHost callbacks{&i, hostLock, hostUnlock,
                                           hostChanged, hostHint};
      i.editor = vl_fast_dist_editor_create(i.numerical, &callbacks);
    }
    vl_fast_dist_editor_attach(i.editor, reinterpret_cast<void *>(value));
    i.header.editor =
        value && i.editor ? reinterpret_cast<intptr_t>(i.editor) : 0;
    i.resizePending = value && i.editor;
  }
#else
  (void)p;
  (void)value;
#endif
  if (id == 52 && index >= 0 && index < 5)
    return index == 2 ? 9 : 5;
  return 0;
}
void idle(Plugin *p) {
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
  if (!vl_fast_dist_editor_main_thread())
    return;
  auto &i = object(p);
  vl_fast_dist_editor_refresh(i.editor);
  if (i.resizePending) {
    i.resizePending = false;
    if (auto f = hostMethod<intptr_t (*)(void *, intptr_t, intptr_t, intptr_t,
                                         intptr_t)>(i, 0))
      f(i.host, i.header.hostTag, 2, 0, 0);
  }
#else
  (void)p;
#endif
}
void state(Plugin *p, Stream *s, int32_t save) {
  if (!s || !s->functions)
    return;
  std::array<uint8_t, 20> bytes{};
  using Transfer = int32_t (*)(Stream *, void *, uint32_t, void *);
  uint64_t count = 0;
  if (save) {
    if (!vl_fast_dist_save_state(object(p).numerical, bytes.data(),
                                 bytes.size()))
      return;
    const auto write = reinterpret_cast<Transfer>(s->functions[4]);
    if (write)
      write(s, bytes.data(), 20, &count);
  } else {
    const auto read = reinterpret_cast<Transfer>(s->functions[3]);
    if (read && read(s, bytes.data(), 20, &count) >= 0 && count == 20)
      vl_fast_dist_restore_state(object(p).numerical, bytes.data(),
                                 bytes.size());
  }
}
void name(Plugin *, int32_t section, int32_t index, int32_t, char *out) {
  constexpr std::array<const char *, 5> names{"Pre Gain", "Threshold", "Type",
                                              "Mix", "Post Gain"};
  if (out)
    std::strcpy(out, section == 0 && index >= 0 && index < 5
                         ? names[size_t(index)]
                         : "");
}
int32_t event(Plugin *, int32_t, int32_t, int32_t) { return 0; }
int32_t parameter(Plugin *p, int32_t index, int32_t value, int32_t flags) {
  int32_t result = 0;
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
  // GUI hint calls are outside the caller's mix lock. Serialize their numerical
  // work here, then notify after unlock. Worker calls retain caller locking.
  const bool mainHint = (flags & 4) && vl_fast_dist_editor_main_thread();
  if (mainHint)
    hostLock(&object(p));
#endif
  vl_fast_dist_parameter(object(p).numerical, index, value,
                         uint32_t(flags) & 35u, &result);
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
  if (mainHint) {
    hostUnlock(&object(p));
    vl_fast_dist_editor_hint(object(p).editor, index, result);
  }
#endif
  return result;
}
void effect(Plugin *p, const float *in, float *out, int32_t frames) {
  vl_fast_dist_render(object(p).numerical, in, out, frames);
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
    voiceEvent, voiceEnd,    destroy,   destroy};
} // namespace
extern "C" veggie_loops::balance::native::Plugin *
CreatePlugInstance(void *host, intptr_t tag) {
  auto *i = new (std::nothrow) Instance;
  if (!i)
    return nullptr;
  if (!i->numerical) {
    delete i;
    return nullptr;
  }
#if defined(VL_FAST_DIST_APPKIT_EDITOR)
  i->host = host;
#else
  (void)host;
#endif
  i->header.functions = &functions;
  i->header.hostTag = tag;
  i->header.info = &commonInfo();
  return &i->header;
}
