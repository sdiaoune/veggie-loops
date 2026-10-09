#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This identity-bound native editor test requires macOS arm64.
#endif
#include "center_native_abi.h"
#include "center_plugin.h"
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
using namespace veggie_loops::center::native;
void require(bool v, const char *m) {
  if (!v)
    throw std::runtime_error(m);
}
std::string sourceHash(const char *path) {
  std::ifstream in(path, std::ios::binary);
  require(in.good(), "Cannot read engine");
  std::vector<unsigned char> b{std::istreambuf_iterator<char>(in),
                               std::istreambuf_iterator<char>()};
  std::array<unsigned char, 32> h{};
  CC_SHA256(b.data(), static_cast<CC_LONG>(b.size()), h.data());
  std::ostringstream s;
  for (auto v : h)
    s << std::hex << std::setfill('0') << std::setw(2) << unsigned(v);
  return s.str();
}
template <class T> T get(void *o, std::size_t p) {
  T v;
  std::memcpy(&v, static_cast<char *>(o) + p, sizeof(v));
  return v;
}
template <class T> T method(void *o, std::size_t p) {
  return get<T>(get<void *>(o, 0), p);
}
struct Host {
  void **functions;
  std::mutex mix;
  int locks = 0, unlocks = 0, changes = 0, hints = 0, resizes = 0;
  std::int32_t index = -1, value = -1;
  std::string hint;
  void *pluginWrapper = nullptr;
};
thread_local Host *held = nullptr;
void hostLock(Host *h, std::intptr_t tag) {
  h->mix.lock();
  require(tag == 0x564c && NSThread.isMainThread && !held,
          "Host lock protocol failed");
  held = h;
  ++h->locks;
}
void hostUnlock(Host *h, std::intptr_t tag) {
  require(tag == 0x564c && NSThread.isMainThread && held == h,
          "Host unlock protocol failed");
  held = nullptr;
  ++h->unlocks;
  h->mix.unlock();
}
void hostChanged(Host *h, std::intptr_t tag, std::int32_t index,
                 std::int32_t value) {
  require(tag == 0x564c && NSThread.isMainThread && !held,
          "Change callback occurred inside lock");
  h->index = index;
  h->value = value;
  ++h->changes;
}
void hostHint(Host *h, std::intptr_t tag, const char *text) {
  require(tag == 0x564c && NSThread.isMainThread && !held && text,
          "Hint callback protocol failed");
  h->hint = text;
  ++h->hints;
}
std::intptr_t hostDispatch(Host *h, std::intptr_t tag, std::intptr_t id,
                           std::intptr_t, std::intptr_t) {
  require(tag == 0x564c && NSThread.isMainThread && !held,
          "Dispatch callback protocol failed");
  if (id == 2) {
    require(h->pluginWrapper && get<std::intptr_t>(h->pluginWrapper, 24) != 0,
            "Resize preceded editor-handle bridge");
    ++h->resizes;
  }
  return 0;
}
} // namespace
int main(int argc, char **argv) {
  @autoreleasepool {
    try {
      require(argc == 3, "Usage: test_center_native_editor "
                         "inspected-engine compiled-editor-plugin");
      require(sourceHash(argv[1]) == "22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a0"
                                     "7d441371e3c27704317bd37",
              "Engine identity changed");
      [NSApplication sharedApplication];
      void *engine = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
      require(engine, "Engine load failed");
      Dl_info image{};
      require(dladdr(dlsym(engine, "CreateFruityInstance"), &image),
              "Engine image unavailable");
      auto *base = static_cast<char *>(image.dli_fbase);
      std::array<void *, 96> hostMethods{};
      hostMethods[0xc8 / 8] = reinterpret_cast<void *>(&hostDispatch);
      hostMethods[0xd0 / 8] = reinterpret_cast<void *>(&hostChanged);
      hostMethods[0xd8 / 8] = reinterpret_cast<void *>(&hostHint);
      hostMethods[0x1c8 / 8] = reinterpret_cast<void *>(&hostLock);
      hostMethods[0x1d0 / 8] = reinterpret_cast<void *>(&hostUnlock);
      Host host{};
      host.functions = hostMethods.data();
      using Constructor = void *(*)(void *, std::intptr_t, void *);
      auto hostConstructor = reinterpret_cast<Constructor>(base + 0xb4cd20);
      void *hostWrapper = hostConstructor(base + 0x1497870, 1, &host);
      require(hostWrapper, "Actual engine host class allocation failed");
      void *library = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
      require(library, "Editor plugin load failed");
      auto factory = reinterpret_cast<Plugin *(*)(void *, std::intptr_t)>(
          dlsym(library, "CreatePlugInstance"));
      require(factory, "Missing native factory");
      Plugin *plugin = factory(static_cast<char *>(hostWrapper) + 16, 0x564c);
      require(plugin && plugin->info->flags == ((1 << 21) | (1 << 27)),
              "Editor plugin metadata failed");
      auto pluginConstructor = reinterpret_cast<Constructor>(base + 0xb4c7c0);
      void *wrapper = pluginConstructor(base + 0x1497618, 1, plugin);
      require(wrapper, "Actual engine plugin class allocation failed");
      host.pluginWrapper = wrapper;
      auto dispatch = method<std::intptr_t (*)(
          void *, std::intptr_t, std::intptr_t, std::intptr_t)>(wrapper, 0xd0);
      auto idle = method<void (*)(void *)>(wrapper, 0xd8);
      auto parameter = method<std::int32_t (*)(
          void *, std::int32_t, std::int32_t, std::int32_t)>(wrapper, 0xf8);
      std::thread unattachedDestroyWorker(
          [&] { method<void (*)(void *)>(wrapper, 0xc8)(wrapper); });
      unattachedDestroyWorker.join();
      require(parameter(wrapper, 0, 0, 2) == 1,
              "Worker unattached destruction released numerical state");
      auto *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
      std::atomic<bool> stopHints = false, hintFailed = false;
      std::atomic<size_t> workerHintCalls = 0;
      std::thread attachmentWorker([&] {
        while (!stopHints.load(std::memory_order_acquire)) {
          std::lock_guard<std::mutex> guard(host.mix);
          if (parameter(wrapper, 0, 0, 6) != 1)
            hintFailed.store(true);
          workerHintCalls.fetch_add(1, std::memory_order_release);
        }
      });
      while (workerHintCalls.load(std::memory_order_acquire) == 0)
        std::this_thread::yield();
      dispatch(wrapper, 0, 0,
               reinterpret_cast<std::intptr_t>((__bridge void *)parent));
      stopHints.store(true, std::memory_order_release);
      attachmentWorker.join();
      require(!hintFailed.load() && workerHintCalls.load() > 0 &&
                  host.hints == 0 && parent.subviews.count == 1 &&
                  get<std::intptr_t>(wrapper, 24) != 0,
              "Concurrent first attachment/worker hint failure");
      const auto locksBeforeWorker = host.locks;
      std::thread worker([&] {
        method<void (*)(void *)>(wrapper, 0x138)(wrapper);
        method<void (*)(void *)>(wrapper, 0x140)(wrapper);
        idle(wrapper);
        dispatch(wrapper, 0, 0, 0);
      });
      worker.join();
      require(host.resizes == 0 && host.locks == locksBeforeWorker &&
                  parent.subviews.count == 1 &&
                  get<std::intptr_t>(wrapper, 24) != 0,
              "Worker tick/Idle/detach accessed GUI");
      idle(wrapper);
      require(host.resizes == 1, "Deferred resize bridge");
      NSView *editor = parent.subviews[0];
      NSButton *toggle = nil;
      for (NSView *child in editor.subviews)
        if ([child isKindOfClass:NSButton.class])
          toggle = (NSButton *)child;
      require(toggle && toggle.state == NSControlStateValueOn,
              "Native enable widget/default");
      toggle.state = NSControlStateValueOff;
      [toggle sendAction:toggle.action to:toggle.target];
      require(host.index == 0 && host.value == 0 && host.changes == 1 &&
                  host.hints == 1 && host.hint == "DC centering: off" &&
                  parameter(wrapper, 0, 0, 2) == 0,
              "UI toggle did not reach native numerical/host adapter");
      const auto bind = [&](const char *name) {
        void *f = dlsym(library, name);
        require(f, "Missing numerical reference symbol");
        return f;
      };
      const auto create = reinterpret_cast<decltype(&vl_center_create)>(
          bind("vl_center_create"));
      const auto destroy = reinterpret_cast<decltype(&vl_center_destroy)>(
          bind("vl_center_destroy"));
      const auto render = reinterpret_cast<decltype(&vl_center_render)>(
          bind("vl_center_render"));
      const auto rate = reinterpret_cast<decltype(&vl_center_sample_rate)>(
          bind("vl_center_sample_rate"));
      const auto reset = reinterpret_cast<decltype(&vl_center_resume)>(
          bind("vl_center_resume"));
      const auto filterState =
          reinterpret_cast<decltype(&vl_center_get_filter_state)>(
              bind("vl_center_get_filter_state"));
      auto *reference = create();
      require(reference, "Reference allocation");
      const auto nativeRender =
          method<void (*)(void *, const float *, float *, int32_t)>(wrapper,
                                                                    0x100);
      std::array<float, 2048> input{}, output{}, expected{};
      for (size_t n = 0; n < 1024; ++n) {
        input[n * 2] = .5f;
        input[n * 2 + 1] = -.25f;
      }
      {
        std::lock_guard<std::mutex> guard(host.mix);
        nativeRender(wrapper, input.data(), output.data(), 1024);
      }
      require(std::memcmp(output.data(), input.data(), sizeof(input)) == 0,
              "UI bypass did not reach native DSP");
      toggle.state = NSControlStateValueOn;
      [toggle sendAction:toggle.action to:toggle.target];
      require(host.changes == 2 && host.hints == 2 &&
                  host.hint == "DC centering: on",
              "UI enable host notifications");
      size_t displayCases = 0;
      const auto displays = [&](const std::array<double, 4> &state) {
        const auto contains = [&](const char *text) {
          for (NSView *child in editor.subviews)
            if ([child isKindOfClass:NSTextField.class] &&
                [((NSTextField *)child).stringValue
                    isEqualToString:[NSString stringWithUTF8String:text]])
              return true;
          return false;
        };
        char text[96];
        std::snprintf(text, sizeof(text), "Left: %+.4f", state[0]);
        require(contains(text), "Native retained left offset display");
        std::snprintf(text, sizeof(text), "Right: %+.4f", state[1]);
        require(contains(text), "Native retained right offset display");
      };
      for (int32_t sampleRate : {8000, 44100, 96000, 384000}) {
        {
          std::lock_guard<std::mutex> guard(host.mix);
          dispatch(wrapper, 4, 0, sampleRate);
        }
        require(rate(reference, sampleRate), "Reference rate");
        for (int iteration = 0; iteration < 16; ++iteration) {
          {
            std::lock_guard<std::mutex> guard(host.mix);
            nativeRender(wrapper, input.data(), output.data(), 1024);
          }
          require(render(reference, input.data(), expected.data(), 1024) &&
                      std::memcmp(output.data(), expected.data(),
                                  sizeof(output)) == 0,
                  "Native editor numerical DSP differs from reference");
          std::array<double, 4> state{};
          require(filterState(reference, state.data()),
                  "Reference filter state");
          idle(wrapper);
          displays(state);
          ++displayCases;
        }
      }
      {
        std::lock_guard<std::mutex> guard(host.mix);
        dispatch(wrapper, 2, 0, 0);
      }
      require(reset(reference), "Reference resume");
      idle(wrapper);
      displays({});
      ++displayCases;
      parameter(wrapper, 0, 0, 17);
      idle(wrapper);
      require(toggle.state == NSControlStateValueOff && host.changes == 2,
              "Automation refresh emitted a UI change");
      parameter(wrapper, 0, 0, 6);
      require(host.hints == 3 && host.hint == "DC centering: off",
              "Native main hint flag");
      const auto hintsBeforeWorker = host.hints;
      std::thread destroyWorker([&] {
        parameter(wrapper, 0, 0, 6);
        method<void (*)(void *)>(wrapper, 0xc8)(wrapper);
      });
      destroyWorker.join();
      require(host.hints == hintsBeforeWorker && parent.subviews.count == 1 &&
                  parameter(wrapper, 0, 0, 2) == 0,
              "Worker hint/destroy touched GUI or freed state");
      std::atomic<bool> stopRender = false, renderFailed = false;
      std::atomic<size_t> renderCalls = 0;
      std::thread renderer([&] {
        std::array<float, 16> source{}, destination{};
        for (size_t n = 0; n < 8; ++n) {
          source[n * 2] = .5f;
          source[n * 2 + 1] = -.25f;
        }
        while (!stopRender.load(std::memory_order_acquire)) {
          {
            std::lock_guard<std::mutex> guard(host.mix);
            nativeRender(wrapper, source.data(), destination.data(), 8);
          }
          if (std::memcmp(source.data(), destination.data(), sizeof(source)) !=
              0)
            renderFailed.store(true);
          renderCalls.fetch_add(1, std::memory_order_release);
          std::this_thread::yield();
        }
      });
      while (renderCalls.load(std::memory_order_acquire) == 0)
        std::this_thread::yield();
      for (size_t iteration = 0; iteration < 128; ++iteration) {
        dispatch(wrapper, 0, 0, 0);
        require(parent.subviews.count == 0 &&
                    get<std::intptr_t>(wrapper, 24) == 0,
                "Native detach handle");
        dispatch(wrapper, 0, 0,
                 reinterpret_cast<std::intptr_t>((__bridge void *)parent));
        idle(wrapper);
        require(parent.subviews.count == 1 &&
                    toggle.state == NSControlStateValueOff,
                "Native reattach state");
      }
      stopRender.store(true, std::memory_order_release);
      renderer.join();
      require(!renderFailed.load() && renderCalls.load() > 0,
              "Concurrent render/refresh/reattach failure");
      destroy(reference);
      method<void (*)(void *)>(wrapper, 0xc8)(wrapper);
      require(parent.subviews.count == 0,
              "Attached view survives native destruction");
      method<void (*)(void *, std::intptr_t)>(wrapper, 0x60)(wrapper, 1);
      method<void (*)(void *, std::intptr_t)>(hostWrapper, 0x60)(hostWrapper,
                                                                 1);
      require(host.locks == host.unlocks && !held, "Unbalanced host locks");
      dlclose(library);
      dlclose(engine);
      std::cout
          << "{\"status\":\"passed\",\"independently_written_appkit_editor\":"
             "true,"
             "\"actual_engine_plugin_and_host_adapters\":true,"
             "\"concurrent_first_attachment_worker_hints_checked\":true,"
             "\"concurrent_render_reattach_cycles\":128,\"filter_display_"
             "cases\":"
          << displayCases
          << ",\"worker_tick_idle_skipped_gui\":true,"
             "\"off_main_destroy_preserves_state\":true,\"control_changes\":"
          << host.changes << ",\"hints\":" << host.hints
          << ",\"resize_notifications\":" << host.resizes
          << ",\"source_gui_resources_copied\":false,"
             "\"actual_fl_application_created\":false,\"full_plugin_"
             "equivalence\":false}\n";
    } catch (const std::exception &e) {
      std::cerr << e.what() << '\n';
      return 1;
    }
  }
}
