#include "soft_clipper_native_abi.h"
#include "soft_clipper_plugin.h"
#import <Cocoa/Cocoa.h>
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>

#if !defined(__APPLE__) || !defined(__aarch64__)
#error This loader test requires macOS arm64.
#endif

namespace {
using namespace veggie_loops::soft_clipper::native;
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
std::string sourceHash(const char *path) {
  std::ifstream in(path, std::ios::binary);
  require(in.good(), "Cannot read engine");
  std::vector<unsigned char> bytes{std::istreambuf_iterator<char>(in),
                                   std::istreambuf_iterator<char>()};
  std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> result{};
  CC_SHA256(bytes.data(), static_cast<CC_LONG>(bytes.size()), result.data());
  std::ostringstream out;
  for (auto b : result)
    out << std::hex << std::setfill('0') << std::setw(2) << unsigned(b);
  return out.str();
}
template <class T> T get(void *object, std::size_t offset) {
  T value;
  std::memcpy(&value, static_cast<char *>(object) + offset, sizeof(value));
  return value;
}
template <class T> T method(void *object, std::size_t offset) {
  return get<T>(get<void *>(object, 0), offset);
}
// FPC's immutable UTF-16 string header is three 64-bit fields before the data:
// codepage/element size, reference count=-1, character count. The input remains
// alive through the loader call and is never passed to a source allocator.
struct ImmutablePath {
  std::vector<std::uint64_t> storage;
  explicit ImmutablePath(const char *path) {
    NSString *text = [NSString stringWithUTF8String:path];
    require(text != nil, "Invalid UTF-8 path");
    const auto length = [text length];
    storage.resize((24 + (length + 1) * 2 + 7) / 8);
    storage[0] = 0x204b0;
    storage[1] = ~std::uint64_t{};
    storage[2] = length;
    [text getCharacters:reinterpret_cast<unichar *>(storage.data() + 3)
                  range:NSMakeRange(0, length)];
  }
  const char16_t *data() const {
    return reinterpret_cast<const char16_t *>(storage.data() + 3);
  }
};
struct MemoryStream {
  Stream interface{};
  std::array<void *, 5> functions{};
  std::array<uint8_t, 8> bytes{};
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
    if (self.cursor + length > 8 || self.failRead) {
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
    if (self.cursor + length > 8) {
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
      require(argc == 3, "Usage: test_soft_clipper_engine_loader "
                         "inspected-engine rebuilt-plugin-logical-path");
      require(sourceHash(argv[1]) == "22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a0"
                                     "7d441371e3c27704317bd37",
              "Inspected engine identity changed");
      [NSApplication sharedApplication];
      void *engine = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
      require(engine, "Cannot load inspected original engine");
      auto exported = dlsym(engine, "CreateFruityInstance");
      Dl_info image{};
      require(exported && dladdr(exported, &image),
              "Cannot locate inspected engine image");
      auto *base = static_cast<char *>(image.dli_fbase);
      ImmutablePath path(argv[2]);
      void *library = nullptr;
      // Calls the intact engine DLL loader, without replay hooks or a created
      // FL application. Our factory makes no callbacks through the supplied
      // host.
      using Loader = void *(*)(const char16_t *, void **, std::intptr_t);
      auto loader = reinterpret_cast<Loader>(base + 0x3e1450);
      void *wrapper = loader(path.data(), &library, 0x564c);
      require(wrapper && library, "Actual native engine loader failed");
      require(get<void *>(wrapper, 0) == base + 0x1497618,
              "Unexpected engine wrapper class");
      require(get<std::intptr_t>(wrapper, 8) == 0x564c,
              "Engine host tag bridge failed");
      const auto *info = get<const Info *>(wrapper, 16);
      require(info && info->version == 1 && info->parameterCount == 2 &&
                  info->flags == (1 << 21),
              "Incorrect native metadata");
      require(std::strcmp(info->longName, "VL Soft Clipper") == 0 &&
                  !dlsym(library, "SetExternalAppHandle"),
              "Incorrect rebuilt plugin identity/selector");
      const auto bind = [&](const char *name) {
        auto p = dlsym(library, name);
        require(p, "Missing rebuilt C API symbol");
        return p;
      };
      auto create = reinterpret_cast<decltype(&vl_soft_clipper_create)>(
          bind("vl_soft_clipper_create"));
      auto destroy = reinterpret_cast<decltype(&vl_soft_clipper_destroy)>(
          bind("vl_soft_clipper_destroy"));
      auto set = reinterpret_cast<decltype(&vl_soft_clipper_parameter)>(
          bind("vl_soft_clipper_parameter"));
      auto render = reinterpret_cast<decltype(&vl_soft_clipper_render)>(
          bind("vl_soft_clipper_render"));
      auto save = reinterpret_cast<decltype(&vl_soft_clipper_save_state)>(
          bind("vl_soft_clipper_save_state"));
      auto restore = reinterpret_cast<decltype(&vl_soft_clipper_restore_state)>(
          bind("vl_soft_clipper_restore_state"));
      auto *direct = create();
      require(direct, "Independent numerical factory failed");
      auto nativeParameter = method<std::int32_t (*)(
          void *, std::int32_t, std::int32_t, std::int32_t)>(wrapper, 0xf8);
      auto nativeDispatcher = method<std::intptr_t (*)(
          void *, std::intptr_t, std::intptr_t, std::intptr_t)>(wrapper, 0xd0);
      auto nativeRender =
          method<void (*)(void *, const float *, float *, std::int32_t)>(
              wrapper, 0x100);
      auto nativeState =
          method<void (*)(void *, Stream *, int32_t)>(wrapper, 0xe0);
      require(nativeParameter(wrapper, 0, 0, 2) == 100 &&
                  nativeParameter(wrapper, 1, 0, 2) == 128,
              "Native factory defaults differ");
      std::mt19937 random(0x454e474e);
      std::size_t frames = 0, parameters = 0;
      constexpr std::array<std::int32_t, 12> lengths{0, 1,  2,  3,  7,   8,
                                                     9, 16, 17, 63, 257, 1024};
      for (std::int32_t caseIndex = 0; caseIndex < 1200; ++caseIndex) {
        for (std::int32_t index = 0; index < 2; ++index) {
          const auto normalized = caseIndex % 3 == 0;
          const auto flags = normalized ? 49 : 17;
          const auto value =
              normalized ? static_cast<std::int32_t>(random() % 0x40000001u)
                         : static_cast<std::int32_t>(random() %
                                                     (index == 0 ? 127 : 161)) +
                               (index == 0 ? 1 : 0);
          std::int32_t result = 0;
          require(set(direct, index, value, flags & 35, &result),
                  "C API parameter rejected");
          require(nativeParameter(wrapper, index, value, flags) == result,
                  "Live engine parameter differs");
          ++parameters;
        }
        if (caseIndex % 7 == 0) {
          const auto hz = static_cast<std::int32_t>(8000 + random() % 184001);
          nativeDispatcher(wrapper, 4, 0, hz);
        }
        if (caseIndex % 11 == 0) {
          nativeDispatcher(wrapper, 2, 0, 0);
        }
        MemoryStream stream;
        nativeState(wrapper, &stream.interface, 1);
        std::array<uint8_t, 8> directState{};
        require(save(direct, directState.data(), 8) &&
                    directState == stream.bytes && stream.cursor == 8 &&
                    stream.calls == 1,
                "Live engine state save differs");
        if (caseIndex % 5 == 0) {
          nativeParameter(wrapper, 0, 1, 17);
          int32_t ignored = 0;
          set(direct, 0, 1, 1, &ignored);
          stream.cursor = stream.calls = 0;
          nativeState(wrapper, &stream.interface, 0);
          require(restore(direct, stream.bytes.data(), 8),
                  "Direct restore rejected");
          for (int32_t index = 0; index < 2; ++index) {
            int32_t value = 0;
            require(set(direct, index, 0, 2, &value) &&
                        nativeParameter(wrapper, index, 0, 2) == value,
                    "Live engine state restore differs");
          }
        }
        const auto length = lengths[caseIndex % lengths.size()];
        const size_t start = caseIndex & 1;
        const bool alias = caseIndex % 3 == 0;
        std::vector<float> input(size_t(length) * 2 + 16),
            a(input.size(), 1234), b(a);
        for (auto &sample : input)
          sample = float(int32_t(random() % 65536) - 32768) / 2048.0f;
        for (size_t i = 0; i < input.size(); i += 11)
          input[i] = i & 1 ? -0.0f : 0.0f;
        const auto beforeInput = input, initial = alias ? input : a;
        if (alias) {
          a = input;
          b = input;
        }
        nativeRender(wrapper, alias ? a.data() + start : input.data() + start,
                     a.data() + start, length);
        require(render(direct, alias ? b.data() + start : input.data() + start,
                       b.data() + start, length),
                "C API render rejected");
        require(std::memcmp(a.data(), b.data(), a.size() * 4) == 0,
                "Live engine audio/guard differs");
        for (size_t i = 0; i < a.size(); ++i)
          if (i < start || i >= start + size_t(length) * 2)
            require(std::memcmp(a.data() + i, initial.data() + i, 4) == 0 &&
                        std::memcmp(b.data() + i, initial.data() + i, 4) == 0,
                    "Main guard changed");
        require(std::memcmp(input.data(), beforeInput.data(),
                            input.size() * 4) == 0,
                "Source input changed");
        frames += length;
      }
      // Exercise every callback slot on the real engine wrapper. Unused effect
      // generator/voice/MIDI implementations are explicit independent no-ops.
      auto at = [&](size_t offset) { return base + offset; };
      reinterpret_cast<void (*)(void *)>(at(0xb4ca10))(wrapper);
      require(reinterpret_cast<int32_t (*)(void *, int32_t, int32_t, int32_t)>(
                  at(0xb4cb60))(wrapper, 0, 0, 0) == 0,
              "Event slot differs");
      std::array<float, 8> guard{1, 2, 3, 4, 5, 6, 7, 8};
      int32_t length = 4;
      reinterpret_cast<void (*)(void *, float *, int32_t &)>(at(0xb4c9b0))(
          wrapper, guard.data(), length);
      require(length == 0 &&
                  guard == std::array<float, 8>{1, 2, 3, 4, 5, 6, 7, 8},
              "Generator slot differs");
      require(reinterpret_cast<intptr_t (*)(void *, void *, intptr_t)>(
                  at(0xb4cbf0))(wrapper, nullptr, 0x1234) == -1,
              "Voice slot differs");
      for (size_t offset : {0xb4cc20, 0xb4cc80, 0xb4cb00})
        reinterpret_cast<void (*)(void *, intptr_t)>(at(offset))(wrapper,
                                                                 0x1234);
      for (size_t offset : {0xb4cc50, 0xb4cb30})
        require(reinterpret_cast<int32_t (*)(void *, intptr_t, intptr_t,
                                             intptr_t, intptr_t)>(at(offset))(
                    wrapper, 0x1234, 1, 2, 3) == 0,
                "Voice event slot differs");
      length = 4;
      require(
          reinterpret_cast<int32_t (*)(void *, intptr_t, float *, int32_t &)>(
              at(0xb4ccb0))(wrapper, 0x1234, guard.data(), length) == 0 &&
              length == 0,
          "Voice render slot differs");
      for (size_t offset : {0xb4ca70, 0xb4cad0})
        reinterpret_cast<void (*)(void *)>(at(offset))(wrapper);
      int32_t midi = 0x1234;
      reinterpret_cast<void (*)(void *, int32_t &)>(at(0xb4ca40))(wrapper,
                                                                  midi);
      require(midi == 0x1234, "MIDI slot differs");
      reinterpret_cast<void (*)(void *, intptr_t)>(at(0xb4caa0))(wrapper,
                                                                 0x1234);
      const auto nativeName =
          method<void (*)(void *, int32_t, int32_t, int32_t, char *)>(wrapper,
                                                                      0xe8);
      for (int32_t index = 0; index < 2; ++index) {
        std::array<char, 256> text{};
        nativeName(wrapper, 0, index, 0, text.data());
        require(std::strcmp(text.data(),
                            index == 0 ? "Threshold" : "Post Gain") == 0,
                "Name slot differs");
      }
      MemoryStream shortRead;
      require(save(direct, shortRead.bytes.data(), 8), "State snapshot failed");
      shortRead.failRead = true;
      const std::array<int32_t, 2> previous{nativeParameter(wrapper, 0, 0, 2),
                                            nativeParameter(wrapper, 1, 0, 2)};
      nativeState(wrapper, &shortRead.interface, 0);
      require(nativeParameter(wrapper, 0, 0, 2) == previous[0] &&
                  nativeParameter(wrapper, 1, 0, 2) == previous[1],
              "Failed read changed parameter state");
      require(nativeDispatcher(wrapper, 52, 0, 0) == 1 &&
                  nativeDispatcher(wrapper, 52, 1, 0) == 5,
              "Classification contract differs");
      method<void (*)(void *)>(wrapper, 0xc8)(
          wrapper); // native wrapper destroys our C++ object
      method<void (*)(void *, std::intptr_t)>(wrapper, 0x60)(
          wrapper, 1); // free the Pascal wrapper instance
      destroy(direct);
      dlclose(library);
      dlclose(engine);
      std::cout
          << "{\"status\":\"passed\",\"intact_original_engine_loaded\":true,"
             "\"actual_engine_dll_loader_accepted_rebuilt_plugin\":true,"
             "\"actual_engine_wrapper_allocated_and_freed\":true,\"callback_"
             "slots_exercised\":20,\"state_saves\":1200,\"state_restores\":240,"
             "\"failed_read_preserves_state\":true,\"parameter_calls\":"
          << parameters << ",\"stereo_frames\":" << frames
          << ",\"fl_application_host_created\":false,\"full_plugin_"
             "equivalence\":false}\n";
    } catch (const std::exception &error) {
      std::cerr << error.what() << '\n';
      return 1;
    }
  }
}
