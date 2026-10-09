#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This identity-bound native editor test requires macOS arm64.
#endif
#include "fast_dist_native_editor_candidate.h"
#include "fast_dist_plugin.h"
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
using namespace veggie_loops::fast_dist::native;
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
struct MemoryStream {
  Stream interface{};
  std::array<void *, 5> functions{};
  std::array<uint8_t, 20> bytes{};
  size_t cursor = 0, calls = 0;
  bool failRead = false;
  MemoryStream() {
    functions[3] = reinterpret_cast<void *>(&read);
    functions[4] = reinterpret_cast<void *>(&write);
    interface.functions = functions.data();
  }
  static int32_t read(Stream *stream, void *output, uint32_t length,
                      uint32_t *count) {
    auto &self = *reinterpret_cast<MemoryStream *>(stream);
    if (self.cursor + length > 20 || self.failRead) {
      if (count)
        *count = 0;
      return -1;
    }
    std::memcpy(output, self.bytes.data() + self.cursor, length);
    self.cursor += length;
    ++self.calls;
    if (count)
      *count = length;
    return 0;
  }
  static int32_t write(Stream *stream, void *input, uint32_t length,
                       uint32_t *count) {
    auto &self = *reinterpret_cast<MemoryStream *>(stream);
    if (self.cursor + length > 20) {
      if (count)
        *count = 0;
      return -1;
    }
    std::memcpy(self.bytes.data() + self.cursor, input, length);
    self.cursor += length;
    ++self.calls;
    if (count)
      *count = length;
    return 0;
  }
};
} // namespace
int main(int argc, char **argv) {
  @autoreleasepool {
    try {
      require(argc == 3, "Usage: test_fast_dist_native_editor inspected-engine "
                         "compiled-editor-plugin");
      require(sourceHash(argv[1]) == "22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a0"
                                     "7d441371e3c27704317bd37",
              "Engine identity changed");
      [NSApplication sharedApplication];
      void *engine = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
      require(engine, "Engine load");
      Dl_info image{};
      require(dladdr(dlsym(engine, "CreateFruityInstance"), &image),
              "Engine image");
      auto *base = static_cast<char *>(image.dli_fbase);
      std::array<void *, 96> hostMethods{};
      hostMethods[0xc8 / 8] = reinterpret_cast<void *>(&hostDispatch);
      hostMethods[0xd0 / 8] = reinterpret_cast<void *>(&hostChanged);
      hostMethods[0xd8 / 8] = reinterpret_cast<void *>(&hostHint);
      hostMethods[0x1c8 / 8] = reinterpret_cast<void *>(&hostLock);
      hostMethods[0x1d0 / 8] = reinterpret_cast<void *>(&hostUnlock);
      Host host{};
      host.functions = hostMethods.data();
      using Constructor = void *(*)(void *, intptr_t, void *);
      void *hostWrapper = reinterpret_cast<Constructor>(base + 0xb4cd20)(
          base + 0x1497870, 1, &host);
      require(hostWrapper, "Actual host wrapper");
      void *library = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
      require(library, "Editor module load");
      const auto bind = [&](const char *name) {
        void *p = dlsym(library, name);
        require(p, "Missing module symbol");
        return p;
      };
      auto factory = reinterpret_cast<Plugin *(*)(void *, intptr_t)>(
          bind("CreatePlugInstance"));
      Plugin *plugin = factory(static_cast<char *>(hostWrapper) + 16, 0x564c);
      require(plugin && plugin->info->parameterCount == 5 &&
                  plugin->info->flags == ((1 << 21) | (1 << 27)),
              "Native editor metadata");
      void *wrapper = reinterpret_cast<Constructor>(base + 0xb4c7c0)(
          base + 0x1497618, 1, plugin);
      require(wrapper, "Actual plugin wrapper");
      host.pluginWrapper = wrapper;
      auto dispatch =
          method<intptr_t (*)(void *, intptr_t, intptr_t, intptr_t)>(wrapper,
                                                                     0xd0);
      auto idle = method<void (*)(void *)>(wrapper, 0xd8);
      auto parameter =
          method<int32_t (*)(void *, int32_t, int32_t, int32_t)>(wrapper, 0xf8);
      auto nativeRender =
          method<void (*)(void *, const float *, float *, int32_t)>(wrapper,
                                                                    0x100);
      auto nativeState =
          method<void (*)(void *, Stream *, int32_t)>(wrapper, 0xe0);
      auto create = reinterpret_cast<decltype(&vl_fast_dist_create)>(
          bind("vl_fast_dist_create"));
      auto destroy = reinterpret_cast<decltype(&vl_fast_dist_destroy)>(
          bind("vl_fast_dist_destroy"));
      auto quality = reinterpret_cast<decltype(&vl_fast_dist_quality)>(
          bind("vl_fast_dist_quality"));
      auto render = reinterpret_cast<decltype(&vl_fast_dist_render)>(
          bind("vl_fast_dist_render"));
      auto save = reinterpret_cast<decltype(&vl_fast_dist_save_state)>(
          bind("vl_fast_dist_save_state"));
      auto restore = reinterpret_cast<decltype(&vl_fast_dist_restore_state)>(
          bind("vl_fast_dist_restore_state"));
      auto coefficients =
          reinterpret_cast<decltype(&vl_fast_dist_get_coefficients)>(
              bind("vl_fast_dist_get_coefficients"));
      auto *numerical = get<VLFastDistPlugin *>(plugin, sizeof(Plugin));
      require(numerical, "Own numerical pointer");
      const auto snapshot = [&] {
        std::array<uint8_t, 20> b{};
        require(save(numerical, b.data(), b.size()),
                "Numerical state snapshot");
        return b;
      };
      const auto coefficientSnapshot = [&] {
        std::array<float, 3> c{};
        require(coefficients(numerical, c.data()), "Coefficient snapshot");
        return c;
      };
      const auto beforeDestruction = snapshot();
      std::thread unattachedDestroy(
          [&] { method<void (*)(void *)>(wrapper, 0xc8)(wrapper); });
      unattachedDestroy.join();
      require(snapshot() == beforeDestruction,
              "Off-main unattached destruction freed/mutated state");
      auto *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 400)];
      std::atomic<bool> stopHints = false, hintFailed = false;
      std::atomic<size_t> workerHintCalls = 0;
      std::thread attachmentWorker([&] {
        while (!stopHints.load(std::memory_order_acquire)) {
          std::lock_guard<std::mutex> guard(host.mix);
          if (parameter(wrapper, 0, 0, 6) != 128)
            hintFailed.store(true);
          workerHintCalls.fetch_add(1, std::memory_order_release);
        }
      });
      while (!workerHintCalls.load(std::memory_order_acquire))
        std::this_thread::yield();
      dispatch(wrapper, 0, 0,
               reinterpret_cast<intptr_t>((__bridge void *)parent));
      stopHints.store(true, std::memory_order_release);
      attachmentWorker.join();
      require(!hintFailed.load() && host.hints == 0 &&
                  parent.subviews.count == 1 && get<intptr_t>(wrapper, 24) != 0,
              "First attachment worker hint");
      const auto locksBefore = host.locks;
      std::thread worker([&] {
        method<void (*)(void *)>(wrapper, 0x138)(wrapper);
        method<void (*)(void *)>(wrapper, 0x140)(wrapper);
        idle(wrapper);
        dispatch(wrapper, 0, 0, 0);
      });
      worker.join();
      require(host.resizes == 0 && host.locks == locksBefore &&
                  parent.subviews.count == 1,
              "Worker tick/Idle/detach GUI mutation");
      idle(wrapper);
      require(host.resizes == 1, "Main deferred resize");
      NSView *editor = parent.subviews[0];
      std::array<NSControl *, 5> controls{};
      for (NSView *v in editor.subviews)
        if ([v isKindOfClass:NSSlider.class] ||
            [v isKindOfClass:NSButton.class]) {
          auto *c = (NSControl *)v;
          require(c.tag >= 0 && c.tag < 5 && !controls[c.tag],
                  "Control identity");
          controls[c.tag] = c;
        }
      for (auto *c : controls)
        require(c, "Missing native control");
      constexpr std::array<int32_t, 5> defaults{128, 10, 0, 128, 128},
          minimum{64, 1, 0, 0, 0}, maximum{192, 10, 1, 128, 128};
      const auto displayed = [&](int32_t index, int32_t value) {
        require(index == 2
                    ? (((NSButton *)controls[index]).state ==
                       (value ? NSControlStateValueOn : NSControlStateValueOff))
                    : controls[index].integerValue == value,
                "Native control display");
      };
      for (int32_t i = 0; i < 5; ++i) {
        require(parameter(wrapper, i, 0, 2) == defaults[i],
                "Native factory defaults");
        displayed(i, defaults[i]);
      }
      size_t controlsChanged = 0, automation = 0;
      for (int32_t i = 0; i < 5; ++i)
        for (int32_t raw = minimum[i]; raw <= maximum[i]; ++raw) {
          if (i == 2)
            ((NSButton *)controls[i]).state =
                raw ? NSControlStateValueOn : NSControlStateValueOff;
          else
            controls[i].integerValue = raw;
          [controls[i] sendAction:controls[i].action to:controls[i].target];
          require(host.index == i && host.value == raw &&
                      parameter(wrapper, i, 0, 2) == raw,
                  "Control raw/update host notification");
          ++controlsChanged;
        }
      for (int32_t i = 0; i < 5; ++i) {
        parameter(wrapper, i, defaults[i], 17);
        idle(wrapper);
        displayed(i, defaults[i]);
        ++automation;
      }
      require(host.changes == int(controlsChanged),
              "Automation emitted UI change");
      parameter(wrapper, 0, 0, 6);
      require(host.hint == "Pre Gain: 128", "Main hint flag");
      auto *reference = create(0);
      require(reference, "Independent numerical reference");
      std::array<float, 16> input{.5f,   -.25f,  .333f, -.017f, 0,    -0.0f,
                                  1,     -1,     .2f,   -.7f,   .13f, -.031f,
                                  .003f, -.003f, .8f,   -.8f},
          output{}, expected{};
      std::array<std::array<float, 16>, 2> qualityOutputs{};
      for (int32_t q : {0, 1}) {
        require(quality(numerical, q) && quality(reference, q),
                "Own test quality choice");
        const auto before = snapshot();
        const auto coeff = coefficientSnapshot();
        for (int iteration = 0; iteration < 16; ++iteration) {
          idle(wrapper);
          require(snapshot() == before &&
                      std::memcmp(coefficientSnapshot().data(), coeff.data(),
                                  sizeof(coeff)) == 0,
                  "GUI refresh changed numeric state");
          MemoryStream stream;
          nativeState(wrapper, &stream.interface, 1);
          require(stream.bytes == before && stream.cursor == 20 &&
                      stream.calls == 1,
                  "Optional native state save");
          parameter(wrapper, 0, 64, 17);
          stream.cursor = stream.calls = 0;
          nativeState(wrapper, &stream.interface, 0);
          require(stream.calls == 1 && snapshot() == before &&
                      std::memcmp(coefficientSnapshot().data(), coeff.data(),
                                  sizeof(coeff)) == 0,
                  "Optional native restore changed state/coefficients");
        }
        nativeRender(wrapper, input.data(), output.data(), 8);
        require(render(reference, input.data(), expected.data(), 8) &&
                    std::memcmp(output.data(), expected.data(),
                                sizeof(output)) == 0,
                "UI/state changed selected quality DSP");
        qualityOutputs[q] = output;
      }
      require(std::memcmp(qualityOutputs[0].data(), qualityOutputs[1].data(),
                          sizeof(output)) != 0,
              "Quality probe not discriminating");
      require(quality(numerical, 0) && quality(reference, 0),
              "Return explicit factory quality0");
      const auto hintsBefore = host.hints;
      const auto retained = snapshot();
      std::thread destroyWorker([&] {
        std::lock_guard<std::mutex> guard(host.mix);
        parameter(wrapper, 0, 0, 6);
        method<void (*)(void *)>(wrapper, 0xc8)(wrapper);
      });
      destroyWorker.join();
      require(host.hints == hintsBefore && snapshot() == retained &&
                  parent.subviews.count == 1,
              "Worker attached destruction/hint freed or mutated");
      // Retain enabled distortion during concurrent refresh/reattachment. Each
      // block snapshots all5 controls under the mix lock and compares to a
      // worker-owned independent numerical instance. This avoids a bypass-only
      // concurrency proof.
      parameter(wrapper, 0, 160, 17);
      parameter(wrapper, 1, 4, 17);
      parameter(wrapper, 2, 1, 17);
      parameter(wrapper, 3, 96, 17);
      parameter(wrapper, 4, 100, 17);
      idle(wrapper);
      std::atomic<bool> stopRender = false, renderFailed = false,
                        nonIdentity = false;
      std::atomic<size_t> renderCalls = 0;
      std::thread renderer([&] {
        auto *own = create(0);
        require(own, "Worker reference create");
        std::array<float, 16> got{}, want{};
        while (!stopRender.load(std::memory_order_acquire)) {
          std::lock_guard<std::mutex> guard(host.mix);
          const auto packet = snapshot();
          if (!restore(own, packet.data(), packet.size()))
            renderFailed.store(true);
          nativeRender(wrapper, input.data(), got.data(), 8);
          if (!render(own, input.data(), want.data(), 8) ||
              std::memcmp(got.data(), want.data(), sizeof(got)) != 0)
            renderFailed.store(true);
          if (std::memcmp(got.data(), input.data(), sizeof(got)) != 0)
            nonIdentity.store(true);
          renderCalls.fetch_add(1, std::memory_order_release);
        }
        destroy(own);
      });
      while (!renderCalls.load(std::memory_order_acquire))
        std::this_thread::yield();
      bool hintLocksFailed = false;
      for (size_t iteration = 0; iteration < 128; ++iteration) {
        const auto hintLocks = host.locks, hintUnlocks = host.unlocks;
        require(parameter(wrapper, 1, 1 + int32_t(iteration % 10), 5) ==
                    1 + int32_t(iteration % 10),
                "Main hint/set update");
        if (host.locks != hintLocks + 1 || host.unlocks != hintUnlocks + 1 ||
            held)
          hintLocksFailed = true;
        controls[3].integerValue = 64 + iteration % 65;
        [controls[3] sendAction:controls[3].action to:controls[3].target];
        ++controlsChanged;
        dispatch(wrapper, 0, 0, 0);
        require(!parent.subviews.count && !get<intptr_t>(wrapper, 24),
                "Detach handle");
        dispatch(wrapper, 0, 0,
                 reinterpret_cast<intptr_t>((__bridge void *)parent));
        idle(wrapper);
        require(parent.subviews.count == 1 && get<intptr_t>(wrapper, 24) != 0,
                "Reattach handle");
        displayed(3, 64 + int32_t(iteration % 65));
      }
      stopRender.store(true, std::memory_order_release);
      renderer.join();
      require(!hintLocksFailed, "Main hint numerical work omitted paired lock");
      require(!renderFailed.load() && nonIdentity.load() &&
                  renderCalls.load() > 0,
              "Concurrent enabled DSP/reference mismatch");
      destroy(reference);
      method<void (*)(void *)>(wrapper, 0xc8)(wrapper);
      require(parent.subviews.count == 0,
              "Native destruction retained attached view");
      method<void (*)(void *, intptr_t)>(wrapper, 0x60)(wrapper, 1);
      method<void (*)(void *, intptr_t)>(hostWrapper, 0x60)(hostWrapper, 1);
      require(host.locks == host.unlocks && !held, "Unbalanced host locks");
      dlclose(library);
      dlclose(engine);
      std::cout
          << "{\"status\":\"passed\",\"independently_written_appkit_editor\":"
             "true,\"actual_engine_plugin_and_host_adapters\":true,\"all_raw_"
             "control_action_cases\":399,\"automation_display_cases\":"
          << automation
          << ",\"quality_state_refresh_cases\":32,\"optional_native_state_"
             "saves\":32,\"optional_native_state_restores\":32,\"quality_probe_"
             "discriminating\":true,\"concurrent_first_attachment_worker_hints_"
             "checked\":true,\"concurrent_enabled_render_reattach_cycles\":128,"
             "\"concurrent_main_hint_set_lock_cases\":128,"
             "\"every_worker_block_compared_to_independent_instance\":true,"
             "\"worker_tick_idle_skipped_gui\":true,\"off_main_destroy_"
             "preserves_state\":true,\"control_changes\":"
          << host.changes << ",\"hints\":" << host.hints
          << ",\"resize_notifications\":" << host.resizes
          << ",\"actual_application_created\":false,\"original_host_quality_"
             "production\":false,\"full_plugin_equivalence\":false}\n";
    } catch (const std::exception &e) {
      std::cerr << e.what() << '\n';
      return 1;
    }
  }
}
