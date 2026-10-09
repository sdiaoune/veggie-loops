#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This identity-bound engine stream test requires macOS arm64.
#endif
#include "center_native_abi.h"
#include "center_plugin.h"
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <bit>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace {
using namespace veggie_loops::center::native;
void require(bool value, const char *text) {
  if (!value)
    throw std::runtime_error(text);
}
template <class T> T field(void *object, size_t offset) {
  T value;
  std::memcpy(&value, static_cast<char *>(object) + offset, sizeof(T));
  return value;
}
template <class T> T method(void *object, size_t offset) {
  return field<T>(field<void *>(object, 0), offset);
}
std::string hash(const char *path) {
  std::ifstream file(path, std::ios::binary);
  require(file.good(), "Missing inspected engine");
  std::vector<uint8_t> bytes{std::istreambuf_iterator<char>(file), {}};
  require(bytes.size() <= UINT32_MAX, "Oversized identity input");
  std::array<uint8_t, 32> digest{};
  CC_SHA256(bytes.data(), static_cast<CC_LONG>(bytes.size()), digest.data());
  std::ostringstream out;
  for (auto value : digest)
    out << std::hex << std::setfill('0') << std::setw(2) << unsigned(value);
  return out.str();
}
void word(uint8_t *bytes, uint32_t value) {
  for (size_t i = 0; i < 4; ++i)
    bytes[i] = static_cast<uint8_t>(value >> (8 * i));
}
class EngineStream {
public:
  using Transfer = int32_t (*)(Stream *, void *, uint32_t, uint32_t *);
  using Seek = int32_t (*)(Stream *, int64_t, uint32_t, uint64_t *);
  explicit EngineStream(char *base) {
    // TMemoryStream inherits TObject.Create. Both allocation and subsequent
    // stream adapter initialization execute the intact engine's real methods.
    auto createMemory =
        reinterpret_cast<void *(*)(void *, intptr_t)>(base + 0x1f2f0);
    memory_ = createMemory(base + 0x1248910, 1);
    require(memory_, "Original memory stream constructor failed");
    auto createAdapter =
        reinterpret_cast<void *(*)(void *, intptr_t, void *, int32_t)>(
            base + 0x853600);
    adapter_ = createAdapter(base + 0x1248f38, 1, memory_, 0);
    require(adapter_, "Original stream adapter constructor failed");
    interface_ = reinterpret_cast<Stream *>(static_cast<char *>(adapter_) + 40);
    require(interface_->functions ==
                reinterpret_cast<void **>(base + 0x124bc30),
            "Unexpected original IStream table");
  }
  ~EngineStream() {
    if (adapter_)
      method<void (*)(void *, intptr_t)>(adapter_, 0x60)(adapter_, 1);
    if (memory_)
      method<void (*)(void *, intptr_t)>(memory_, 0x60)(memory_, 1);
  }
  Stream *interface() { return interface_; }
  void rewind() {
    uint64_t position = 99;
    require(reinterpret_cast<Seek>(interface_->functions[5])(interface_, 0, 0,
                                                             &position) == 0 &&
                position == 0,
            "Original IStream seek failed");
  }
  void read(void *bytes, uint32_t size) {
    std::array<uint32_t, 2> count{0, 0xfeedface};
    require(reinterpret_cast<Transfer>(interface_->functions[3])(
                interface_, bytes, size, count.data()) == 0 &&
                count[0] == size && count[1] == 0xfeedface,
            "Original read count width/data failed");
  }
  void write(void *bytes, uint32_t size) {
    std::array<uint32_t, 2> count{0, 0xdeadbeef};
    require(reinterpret_cast<Transfer>(interface_->functions[4])(
                interface_, bytes, size, count.data()) == 0 &&
                count[0] == size && count[1] == 0xdeadbeef,
            "Original write count width/data failed");
  }
  void verifyError() {
    std::array<uint32_t, 2> count{123, 0xfeedface};
    const auto status = reinterpret_cast<Transfer>(interface_->functions[3])(
        interface_, nullptr, 4, count.data());
    require(status < 0 && std::bit_cast<uint32_t>(status) == 0x80030009u &&
                count == std::array<uint32_t, 2>{123, 0xfeedface},
            "Original HRESULT32 error path differs");
  }
  int64_t size() { return field<int64_t>(memory_, 16); }

private:
  void *memory_ = nullptr;
  void *adapter_ = nullptr;
  Stream *interface_ = nullptr;
};
struct FailedRead {
  Stream interface{};
  std::array<void *, 5> functions{};
  std::array<uint8_t, 8> bytes{};
  uint32_t cursor = 0, calls = 0;
  bool shortCount = false;
  uint32_t failAt = 1;
  FailedRead() {
    functions[3] = reinterpret_cast<void *>(&read);
    interface.functions = functions.data();
  }
  static int32_t read(Stream *stream, void *destination, uint32_t length,
                      uint32_t *count) {
    auto &self = *reinterpret_cast<FailedRead *>(stream);
    require(self.cursor + length <= 8, "Unexpected failure fixture request");
    std::memcpy(destination, self.bytes.data() + self.cursor, length);
    self.cursor += length;
    ++self.calls;
    const bool failing = self.calls == self.failAt;
    if (count)
      *count = failing && self.shortCount ? length - 1 : length;
    if (!failing || self.shortCount)
      return 0;
    // A provider may return a failed HRESULT after reporting a full count.
    // W0's failure value must be interpreted as signed32, rather than intptr_t.
    return std::bit_cast<int32_t>(0x80004005u);
  }
};
struct CountedStream {
  Stream interface{};
  std::array<void *, 5> functions{};
  Stream *underlying;
  std::array<uint32_t, 2> reads{}, writes{};
  size_t readCount = 0, writeCount = 0;
  explicit CountedStream(Stream *s) : underlying(s) {
    functions[3] = reinterpret_cast<void *>(&read);
    functions[4] = reinterpret_cast<void *>(&write);
    interface.functions = functions.data();
  }
  static int32_t read(Stream *s, void *out, uint32_t length, void *done) {
    auto &c = *reinterpret_cast<CountedStream *>(s);
    require(c.readCount < 2, "Too many native state reads");
    c.reads[c.readCount++] = length;
    using Transfer = int32_t (*)(Stream *, void *, uint32_t, void *);
    return reinterpret_cast<Transfer>(c.underlying->functions[3])(
        c.underlying, out, length, done);
  }
  static int32_t write(Stream *s, void *in, uint32_t length, void *done) {
    auto &c = *reinterpret_cast<CountedStream *>(s);
    require(c.writeCount < 2, "Too many native state writes");
    c.writes[c.writeCount++] = length;
    using Transfer = int32_t (*)(Stream *, void *, uint32_t, void *);
    return reinterpret_cast<Transfer>(c.underlying->functions[4])(
        c.underlying, in, length, done);
  }
  void reset() {
    reads = {};
    writes = {};
    readCount = writeCount = 0;
  }
};
} // namespace
int main(int argc, char **argv) {
  @autoreleasepool {
    try {
      require(argc == 3, "Usage: test_center_engine_stream "
                         "inspected-engine Center-native-dylib");
      require(hash(argv[1]) == "22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d4413"
                               "71e3c27704317bd37",
              "Inspected engine identity changed");
      [NSApplication sharedApplication];
      void *engine = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
      require(engine, "Original engine load failed");
      Dl_info image{};
      require(dladdr(dlsym(engine, "CreateFruityInstance"), &image),
              "Original engine image unavailable");
      auto *base = static_cast<char *>(image.dli_fbase);
      void *library = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
      require(library, "Compiled native plugin load failed");
      auto create = reinterpret_cast<Plugin *(*)(void *, intptr_t)>(
          dlsym(library, "CreatePlugInstance"));
      require(create, "Compiled factory missing");
      Plugin *plugin = create(nullptr, 0x564c);
      require(plugin, "Compiled factory failed");
      require(plugin->info->flags == (1 << 21) &&
                  plugin->info->parameterCount == 1,
              "Unexpected Center native metadata");
      auto createWrapper =
          reinterpret_cast<void *(*)(void *, intptr_t, void *)>(base +
                                                                0xb4c7c0);
      void *wrapper = createWrapper(base + 0x1497618, 1, plugin);
      require(wrapper, "Original plugin wrapper constructor failed");
      auto parameter =
          method<int32_t (*)(void *, int32_t, int32_t, int32_t)>(wrapper, 0xf8);
      auto state = method<void (*)(void *, Stream *, int32_t)>(wrapper, 0xe0);

      auto filter = reinterpret_cast<decltype(&vl_center_get_filter_state)>(
          dlsym(library, "vl_center_get_filter_state"));
      require(filter, "Numerical filter inspection export absent");
      // Own factory layout is asserted in center_native_abi.cpp; numerical is
      // the sole pointer immediately after the protocol header.
      auto *numerical = field<VLCenterPlugin *>(plugin, sizeof(Plugin));
      require(numerical, "Own numerical pointer absent");
      auto nativeRender =
          method<void (*)(void *, const float *, float *, int32_t)>(wrapper,
                                                                    0x100);
      parameter(wrapper, 0, 1, 1);
      std::array<float, 16> input{}, output{};
      for (size_t i = 0; i < 8; ++i) {
        input[2 * i] = .5f;
        input[2 * i + 1] = -.25f;
      }
      nativeRender(wrapper, input.data(), output.data(), 8);
      std::array<double, 4> baseline{};
      require(filter(numerical, baseline.data()) && baseline[0] != 0,
              "Filter history not primed");
      const auto unchangedFilter = [&] {
        std::array<double, 4> now{};
        require(filter(numerical, now.data()) &&
                    std::memcmp(now.data(), baseline.data(), sizeof(now)) == 0,
                "State transfer changed filter history");
      };
      size_t saves = 0, restores = 0, failedHRESULT = 0, shortSuccess = 0;
      {
        EngineStream stream(base);
        stream.verifyError();
        CountedStream counted(stream.interface());
        for (int32_t i = 0; i < 128; ++i) {
          const int32_t value = i & 1;
          parameter(wrapper, 0, value, 1);
          std::array<uint8_t, 8> expected{}, actual{};
          word(expected.data(), 1);
          word(expected.data() + 4, uint32_t(value));
          stream.rewind();
          counted.reset();
          state(wrapper, &counted.interface, 1);
          require(stream.size() == 8 && counted.writeCount == 2 &&
                      counted.writes == std::array<uint32_t, 2>{4, 4},
                  "Original stream native write framing differs");
          stream.rewind();
          stream.read(actual.data(), 8);
          require(actual == expected, "Original stream saved bytes differ");
          ++saves;
          unchangedFilter();
          const int32_t next = (i + 1) & 1;
          word(expected.data(), uint32_t(i & 1));
          word(expected.data() + 4, uint32_t(next));
          stream.rewind();
          stream.write(expected.data(), 8);
          stream.rewind();
          counted.reset();
          state(wrapper, &counted.interface, 0);
          require(parameter(wrapper, 0, 0, 2) == next &&
                      counted.readCount == 2 &&
                      counted.reads == std::array<uint32_t, 2>{4, 4},
                  "Original stream native restore framing differs");
          ++restores;
          unchangedFilter();
        }
      }
      const int32_t before = parameter(wrapper, 0, 0, 2);
      for (uint32_t failAt : {1u, 2u})
        for (bool shortCount : {false, true}) {
          FailedRead failure;
          failure.shortCount = shortCount;
          failure.failAt = failAt;
          word(failure.bytes.data(), 1);
          word(failure.bytes.data() + 4, uint32_t(before ^ 1));
          state(wrapper, &failure.interface, 0);
          require(failure.calls == failAt &&
                      parameter(wrapper, 0, 0, 2) == before,
                  "Failed status/short count changed parameter state");
          unchangedFilter();
          if (shortCount)
            ++shortSuccess;
          else
            ++failedHRESULT;
        }
      method<void (*)(void *)>(wrapper, 0xc8)(wrapper);
      method<void (*)(void *, intptr_t)>(wrapper, 0x60)(wrapper, 1);
      dlclose(library);
      dlclose(engine);
      std::cout
          << "{\"status\":\"passed\",\"actual_engine_memory_and_stream_"
             "classes\":true,\"actual_engine_plugin_wrapper\":true,"
             "\"completion_store_bits\":32,\"adjacent_count_sentinel_"
             "preserved\":true,\"hresult_return_bits\":32,\"actual_provider_"
             "invalid_pointer_error_checked\":true,\"state_saves\":"
          << saves << ",\"state_restores\":" << restores
          << ",\"failed_hresult_full_count_rejections\":" << failedHRESULT
          << ",\"short_count_success_rejections\":" << shortSuccess
          << ",\"two_four_byte_transfers_checked\":true,\"filter_history_"
             "preserved\":true,"
             "\"application_host_created\":false,\"full_plugin_"
             "equivalence\":false}\n";
    } catch (const std::exception &error) {
      std::cerr << error.what() << '\n';
      return 1;
    }
  }
}
