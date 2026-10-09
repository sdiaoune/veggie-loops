#include "soft_clipper_native_abi.h"
#include "soft_clipper_plugin.h"
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
#include "soft_clipper_editor.h"
#endif
#include <array>
#include <cstring>
#include <mutex>
#include <new>
namespace {
using namespace veggie_loops::soft_clipper::native;
struct Instance {
  Plugin header{};
  VLSoftClipperPlugin *numerical = vl_soft_clipper_create();
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
  void *host = nullptr;
  void *editor = nullptr;
  bool resizePending = false;
#endif
};
static_assert(offsetof(Instance, header) == 0);
Instance &object(Plugin *p) { return *reinterpret_cast<Instance *>(p); }
const Info &commonInfo() {
  static Info info{};
  static std::once_flag once;
  std::call_once(once, [] {
    info.version = 1;
    info.longName = "VL Soft Clipper";
    info.shortName = "VL Soft Clip";
    info.flags = 1 << 21;
    info.parameterCount = 2;
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
    info.flags |= 1 << 27;
#endif
  });
  return info;
}
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
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
bool finishLifetime(Plugin* p){
  if(!p)return false;
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
  if(!vl_soft_clipper_editor_main_thread())return false;
  if(!vl_soft_clipper_editor_destroy(object(p).editor))return false;
#endif
  auto* instance=&object(p);
  vl_soft_clipper_destroy(instance->numerical);
  instance->numerical=nullptr;
  instance->~Instance();
  return true;
}
void completeDestructor(Plugin* p){(void)finishLifetime(p);}
void destroy(Plugin* p){if(finishLifetime(p))::operator delete(static_cast<void*>(p));}
void deletingDestructor(Plugin* p){destroy(p);}
intptr_t dispatch(Plugin *p, intptr_t id, intptr_t index, intptr_t value) {
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
  if (id == 0) {
    if (!vl_soft_clipper_editor_main_thread())
      return 0;
    auto &i = object(p);
    if (value && !i.editor) {
      const VLSoftClipperEditorHost callbacks{&i, hostLock, hostUnlock,
                                              hostChanged, hostHint};
      i.editor = vl_soft_clipper_editor_create(i.numerical, &callbacks);
    }
    vl_soft_clipper_editor_attach(i.editor, reinterpret_cast<void *>(value));
    i.header.editor =
        value && i.editor ? reinterpret_cast<intptr_t>(i.editor) : 0;
    i.resizePending = value && i.editor;
    hostLock(&i);
    vl_soft_clipper_metering(i.numerical, value && i.editor ? 1 : 0);
    hostUnlock(&i);
  }
#else
  (void)p;
  (void)value;
#endif
  if (id == 52 && index >= 0 && index < 2)
    return index == 0 ? 1 : 5;
  return 0;
}
void idle(Plugin *p) {
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
  if (!vl_soft_clipper_editor_main_thread())
    return;
  auto &i = object(p);
  vl_soft_clipper_editor_refresh(i.editor);
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
void tick(Plugin *) {}
void state(Plugin *p, Stream *stream, int32_t save) {
  if (!stream || !stream->functions)
    return;
  std::array<uint8_t, 8> bytes{};
  uint64_t count = 0;
  using Transfer = int32_t (*)(Stream *, void *, uint32_t, void *);
  if (save) {
    if (!vl_soft_clipper_save_state(object(p).numerical, bytes.data(),
                                    bytes.size()))
      return;
    const auto write = reinterpret_cast<Transfer>(stream->functions[4]);
    if (write)
      write(stream, bytes.data(), 8, &count);
  } else {
    const auto read = reinterpret_cast<Transfer>(stream->functions[3]);
    if (read && read(stream, bytes.data(), 8, &count) >= 0 && count == 8)
      vl_soft_clipper_restore_state(object(p).numerical, bytes.data(),
                                    bytes.size());
  }
}
void name(Plugin *, int32_t section, int32_t index, int32_t, char *out) {
  if (out)
    std::strcpy(out, section == 0 && index >= 0 && index < 2
                         ? (index == 0 ? "Threshold" : "Post Gain")
                         : "");
}
int32_t event(Plugin *, int32_t, int32_t, int32_t) { return 0; }
int32_t parameter(Plugin *p, int32_t index, int32_t value, int32_t flags) {
  int32_t result = 0;
  vl_soft_clipper_parameter(object(p).numerical, index, value,
                            uint32_t(flags) & 35u, &result);
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
  if ((flags & 4) && vl_soft_clipper_editor_main_thread())
    vl_soft_clipper_editor_hint(object(p).editor, index, result);
#endif
  return result;
}
void effect(Plugin *p, const float *in, float *out, int32_t frames) {
  vl_soft_clipper_render(object(p).numerical, in, out, frames);
}
void generator(Plugin *, float *, int32_t &length) { length = 0; }
intptr_t voice(Plugin *, void *, intptr_t) { return -1; }
void voiceEnd(Plugin *, intptr_t) {}
int32_t voiceEvent(Plugin *, intptr_t, intptr_t, intptr_t, intptr_t) {
  return 0;
}
int32_t voiceRender(Plugin *, intptr_t, float *, int32_t &length) {
  length = 0;
  return 0;
}
void midi(Plugin *, int32_t &) {}
void message(Plugin *, intptr_t) {}
const Functions functions{
    destroy,    dispatch,    idle,      state,  name,     event,
    parameter,  effect,      generator, voice,  voiceEnd, voiceEnd,
    voiceEvent, voiceRender, tick,      tick,   midi,     message,
    voiceEvent, voiceEnd,    completeDestructor, deletingDestructor};
} // namespace
extern "C" veggie_loops::balance::native::Plugin *
CreatePlugInstance(void *host, intptr_t tag) {
  auto *instance = new (std::nothrow) Instance;
  if (!instance)
    return nullptr;
  if (!instance->numerical) {
    delete instance;
    return nullptr;
  }
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
  instance->host = host;
#else
  (void)host;
#endif
  instance->header.functions = &functions;
  instance->header.hostTag = tag;
  instance->header.info = &commonInfo();
  return &instance->header;
}
