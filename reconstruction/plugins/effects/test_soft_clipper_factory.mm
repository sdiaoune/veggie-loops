#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This measured layout probe requires macOS arm64.
#endif
#include "soft_clipper_dsp.hpp"
#include "soft_clipper_plugin.h"
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <bit>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>
void require(bool v, const char *s) {
  if (!v)
    throw std::runtime_error(s);
}
template <class T> T load(void *p, size_t off) {
  T v;
  std::memcpy(&v, static_cast<char *>(p) + off, sizeof(T));
  return v;
}
template <class T> T method(void *p, size_t off) {
  return reinterpret_cast<T>(load<void **>(p, 0)[off / 8]);
}
std::array<void *, 96> hostTable{};
std::array<void *, 32> pathTable{};
struct Object {
  void **vmt;
};
Object paths{pathTable.data()};
const char *privatePath;
extern "C" intptr_t noop() { return 0; }
extern "C" intptr_t hostDispatch(void *, intptr_t, intptr_t id, intptr_t index,
                                 intptr_t value) {
  (void)index;
  (void)value;
  if (id == 71)
    return reinterpret_cast<intptr_t>(&paths);
  if (id == 29)
    return reinterpret_cast<intptr_t>(privatePath);
  return 0;
}
struct Stream {
  void **vmt;
  std::array<uint8_t, 128> bytes{};
  size_t cursor = 0;
};
extern "C" int32_t writeStream(Stream *s, const void *in, uint32_t length,
                               uint32_t *done) {
  require(s->cursor + length <= s->bytes.size(), "Oversize native state");
  std::memcpy(s->bytes.data() + s->cursor, in, length);
  s->cursor += length;
  if (done)
    *done = length;
  return 0;
}
extern "C" int32_t readStream(Stream *s, void *out, uint32_t length,
                              uint32_t *done) {
  require(s->cursor + length <= s->bytes.size(), "Oversize native state");
  std::memcpy(out, s->bytes.data() + s->cursor, length);
  s->cursor += length;
  if (done)
    *done = length;
  return 0;
}
std::string hashFile(const char *path) {
  std::ifstream f(path, std::ios::binary);
  require(f.good(), "Missing dependency");
  std::vector<uint8_t> b{std::istreambuf_iterator<char>(f), {}};
  std::array<uint8_t, 32> d{};
  CC_SHA256(b.data(), CC_LONG(b.size()), d.data());
  std::ostringstream h;
  for (auto v : d)
    h << std::hex << std::setfill('0') << std::setw(2) << unsigned(v);
  return h.str();
}
int main(int argc, char **argv) {
  @autoreleasepool {
    try {
      require(argc == 4, "Usage source private_path/ rebuilt_C_library");
      std::ifstream f(argv[1], std::ios::binary);
      require(f.good(), "source absent");
      std::vector<uint8_t> b{std::istreambuf_iterator<char>(f), {}};
      std::array<uint8_t, 32> d{};
      CC_SHA256(b.data(), CC_LONG(b.size()), d.data());
      std::ostringstream h;
      for (auto v : d)
        h << std::hex << std::setfill('0') << std::setw(2) << unsigned(v);
      require(h.str() == "fe22c1b186c907333210f511f0aced4147d7842d72bd38df1d566"
                         "61ff337aa8d",
              "source changed");
      require(
          hashFile(
              "/Applications/FL Studio "
              "2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib") ==
              "f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd"
              "1",
          "DSP dependency changed");
      [NSApplication sharedApplication];
      privatePath = argv[2];
      hostTable.fill(reinterpret_cast<void *>(&noop));
      pathTable.fill(reinterpret_cast<void *>(&noop));
      hostTable[0xc8 / 8] = reinterpret_cast<void *>(&hostDispatch);
      alignas(16) std::array<std::byte, 512> host{};
      auto *t = hostTable.data();
      std::memcpy(host.data(), &t, 8);
      void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
      require(lib, "dlopen");
      auto factory = reinterpret_cast<void *(*)(void *, intptr_t)>(
          dlsym(lib, "CreatePlugInstance"));
      require(factory, "factory");
      Dl_info image{};
      require(dladdr(reinterpret_cast<void *>(factory), &image), "base");
      auto *base = static_cast<char *>(image.dli_fbase);
      void *p = factory(host.data(), 42);
      require(p, "create");
      require(load<void *>(p, 0) == base + 0x1c1548, "Unexpected original VMT");
      void *info = load<void *>(p, 0x10);
      require(load<uint32_t>(info, 20) == 0x400000 &&
                  load<int32_t>(info, 24) == 2,
              "Unexpected source info");
      void *form = load<void *>(p, 0xc0);
      for (int i = 0; i < 2; ++i) {
        void *k = load<void *>(form, 0xab8 + 8 * i);
        require(load<int32_t>(k, 0x408) == (i == 0 ? 1 : 0) &&
                    load<int32_t>(k, 0x40c) == (i == 0 ? 127 : 160) &&
                    load<int32_t>(k, 0x410) == (i == 0 ? 100 : 128),
                "Source control range/default mismatch");
        require(load<double>(k, 0x430) == (i == 0 ? 1.0 / 126.0 : 1.0 / 160.0),
                "Source normalized scale mismatch");
      }
      std::array<void *, 5> streamVmt{};
      streamVmt[3] = reinterpret_cast<void *>(&readStream);
      streamVmt[4] = reinterpret_cast<void *>(&writeStream);
      Stream stream{streamVmt.data()};
      method<void (*)(void *, Stream *, int32_t)>(p, 0xe0)(p, &stream, 1);
      using Parameter = int32_t (*)(void *, int32_t, int32_t, uint32_t);
      const auto param = method<Parameter>(p, 0xf8);
      const auto nativeRender =
          method<void (*)(void *, const float *, float *, int32_t)>(p, 0x100);
      vl::soft_clipper::Processor model;
      void *rebuilt = dlopen(argv[3], RTLD_NOW | RTLD_LOCAL);
      require(rebuilt, "Compiled library load failed");
      const auto bind = [&](const char *n) {
        void *f = dlsym(rebuilt, n);
        require(f, "Missing own C API export");
        return f;
      };
      auto create = reinterpret_cast<decltype(&vl_soft_clipper_create)>(
          bind("vl_soft_clipper_create"));
      auto destroy = reinterpret_cast<decltype(&vl_soft_clipper_destroy)>(
          bind("vl_soft_clipper_destroy"));
      auto parameter = reinterpret_cast<decltype(&vl_soft_clipper_parameter)>(
          bind("vl_soft_clipper_parameter"));
      auto render = reinterpret_cast<decltype(&vl_soft_clipper_render)>(
          bind("vl_soft_clipper_render"));
      auto metering = reinterpret_cast<decltype(&vl_soft_clipper_metering)>(
          bind("vl_soft_clipper_metering"));
      auto clearMeters =
          reinterpret_cast<decltype(&vl_soft_clipper_clear_meters)>(
              bind("vl_soft_clipper_clear_meters"));
      auto getMeters = reinterpret_cast<decltype(&vl_soft_clipper_get_meters)>(
          bind("vl_soft_clipper_get_meters"));
      auto save = reinterpret_cast<decltype(&vl_soft_clipper_save_state)>(
          bind("vl_soft_clipper_save_state"));
      auto restore = reinterpret_cast<decltype(&vl_soft_clipper_restore_state)>(
          bind("vl_soft_clipper_restore_state"));
      auto *clone = create();
      require(clone, "Own instance allocation failed");
      size_t params = 0, callbacks = 0, frames = 0, restores = 0, saves = 0,
             invalid = 0;
      const auto compareSave = [&] {
        stream.cursor = 0;
        method<void (*)(void *, Stream *, int32_t)>(p, 0xe0)(p, &stream, 1);
        std::array<uint8_t, 8> own{};
        require(save(clone, own.data(), own.size()) && stream.cursor == 8 &&
                    std::memcmp(own.data(), stream.bytes.data(), 8) == 0,
                "Own/native state save mismatch");
        ++saves;
      };
      std::mt19937 random(0x564c5343);
      const auto compareCoefficients = [&] {
        for (size_t i = 0; i < 3; ++i)
          require(std::bit_cast<uint32_t>(load<float>(p, 0x134 + 4 * i)) ==
                      std::bit_cast<uint32_t>(model.knee[i]),
                  "knee coefficient mismatch");
        require(std::bit_cast<uint32_t>(load<float>(p, 0x130)) ==
                    std::bit_cast<uint32_t>(model.gain),
                "gain coefficient mismatch");
      };
      const auto change = [&](int32_t i, int32_t v, uint32_t flags) {
        const auto expected = model.parameter(i, v, flags & 35u);
        int32_t own = 0;
        require(parameter(clone, i, v, flags & 35u, &own) && own == expected,
                "Compiled own parameter mismatch");
        require(param(p, i, v, flags) == expected, "parameter result mismatch");
        require(param(p, i, 0, 2) == model.raw[size_t(i)] &&
                    load<int32_t>(load<void *>(form, 0xab8 + 8 * i), 0x410) ==
                        model.raw[size_t(i)],
                "control/getter mismatch");
        compareCoefficients();
        compareSave();
        ++params;
      };
      const std::array<int32_t, 20> sizes{0,  1,  2,  3,   4,   7,   8,
                                          9,  15, 16, 17,  31,  32,  33,
                                          63, 64, 65, 257, 512, 1024};
      const auto compare = [&](int32_t count, bool alias, bool offset) {
        const size_t start = offset ? 1 : 0;
        std::vector<float> in(size_t(count) * 2 + 16);
        for (auto &v : in)
          v = float(int32_t(random() % 65536) - 32768) / 2048.0f;
        for (size_t i = 0; i < in.size(); i += 11)
          in[i] = i & 1 ? -0.0f : 0.0f;
        std::vector<float> a(in.size(), 1234), b(a), c(a);
        if (alias) {
          a = in;
          b = in;
          c = in;
        }
        const auto before = alias ? in : a, beforeInput = in;
        nativeRender(p, alias ? a.data() + start : in.data() + start,
                     a.data() + start, count);
        model.render(alias ? b.data() + start : in.data() + start,
                     b.data() + start, count);
        require(render(clone, alias ? c.data() + start : in.data() + start,
                       c.data() + start, count),
                "Own C render rejected");
        require(std::memcmp(a.data(), c.data(), a.size() * 4) == 0,
                "Compiled C render or guard mismatch");
        for (size_t i = 0; i < a.size(); ++i) {
          if (std::bit_cast<uint32_t>(a[i]) != std::bit_cast<uint32_t>(b[i])) {
            std::cerr << "audio case=" << callbacks << " index=" << i
                      << " raw=" << model.raw[0] << ',' << model.raw[1]
                      << " native=" << std::hexfloat << a[i]
                      << " model=" << b[i] << '\n';
            throw std::runtime_error("audio mismatch");
          }
          if (i < start || i >= start + size_t(count) * 2)
            require(std::bit_cast<uint32_t>(a[i]) ==
                            std::bit_cast<uint32_t>(before[i]) &&
                        std::bit_cast<uint32_t>(b[i]) ==
                            std::bit_cast<uint32_t>(before[i]),
                    "guard mismatch");
        }
        require(std::memcmp(in.data(), beforeInput.data(), in.size() * 4) == 0,
                "input mutation");
        for (size_t c = 0; c < 2; ++c)
          require(std::bit_cast<uint32_t>(load<float>(p, 0x140 + c * 4)) ==
                      std::bit_cast<uint32_t>(model.meters[c]),
                  "meter mismatch");
        std::array<float, 2> ownMeters{};
        require(getMeters(clone, ownMeters.data()) &&
                    std::memcmp(ownMeters.data(), model.meters.data(), 8) == 0,
                "Compiled C meter mismatch");
        ++callbacks;
        frames += size_t(count);
      };
      compareCoefficients();
      compareSave();
      for (int32_t i = 0; i < 2; ++i)
        for (int32_t value = i == 0 ? 1 : 0; value <= (i == 0 ? 127 : 160);
             ++value) {
          change(i, value, 17);
          compare(sizes[size_t(value) % sizes.size()], value & 1, value & 2);
        }
      for (int32_t threshold = 1; threshold <= 127; ++threshold) {
        change(0, threshold, 17);
        for (int32_t gain = 0; gain <= 160; ++gain) {
          change(1, gain, 17);
          compare(sizes[size_t(threshold + gain) % sizes.size()],
                  (threshold + gain) & 1, (threshold + gain) & 2);
        }
      }
      for (int32_t i = 0; i < 2; ++i)
        for (size_t n = 0; n < 5000; ++n) {
          change(i, int32_t(random() & 0x3fffffffu), 49);
          compare(sizes[n % sizes.size()], n & 1, n & 2);
        }
      change(0, 0, 49);
      change(0, 1073741824, 49);
      change(1, 0, 49);
      change(1, 1073741824, 49);
      for (size_t n = 0; n < 512; ++n) {
        const std::array<int32_t, 2> values{int32_t(random() % 127) + 1,
                                            int32_t(random() % 161)};
        for (size_t i = 0; i < 2; ++i)
          for (size_t j = 0; j < 4; ++j)
            stream.bytes[i * 4 + j] = uint8_t(uint32_t(values[i]) >> (8 * j));
        stream.cursor = 0;
        method<void (*)(void *, Stream *, int32_t)>(p, 0xe0)(p, &stream, 0);
        require(stream.cursor == 8 && restore(clone, stream.bytes.data(), 8),
                "Valid state restore failed");
        for (int i = 0; i < 2; ++i) {
          model.parameter(i, values[size_t(i)], 1);
          require(param(p, i, 0, 2) == values[size_t(i)],
                  "Restored parameter mismatch");
        }
        compareCoefficients();
        compareSave();
        compare(sizes[n % sizes.size()], n & 1, n & 2);
        ++restores;
      }
      // Flag combinations and exact normalized ties, without asking the source
      // UI
      // to update a control for a flags0 numerical no-op.
      for (int32_t index = 0; index < 2; ++index)
        for (uint32_t flags : {0u, 1u, 2u, 3u, 32u, 33u, 34u, 35u})
          for (size_t n = 0; n < 32; ++n) {
            const int32_t value =
                (flags & 32) ? int32_t(random() & 0x3fffffffu)
                             : int32_t(random() % (index == 0 ? 127 : 161)) +
                                   (index == 0 ? 1 : 0);
            int32_t own = 0;
            const auto expected = model.parameter(index, value, flags);
            require(parameter(clone, index, value, flags, &own) &&
                        own == expected &&
                        param(p, index, value, flags) == expected,
                    "Flag-combination result mismatch");
            require(load<int32_t>(p, 0x128 + index * 4) ==
                        model.raw[size_t(index)],
                    "Flag-combination raw state mismatch");
            compareCoefficients();
            compareSave();
            compare(sizes[n % sizes.size()], n & 1, n & 2);
            ++params;
          }
      for (int32_t index = 0; index < 2; ++index) {
        const int64_t range = index == 0 ? 126 : 160;
        for (int64_t step = 0; step < range; ++step) {
          const int64_t numerator = (2 * step + 1) * int64_t(0x20000000);
          if (numerator % range)
            continue;
          const int32_t half = int32_t(numerator / range);
          for (int32_t delta = -1; delta <= 1; ++delta)
            change(index, half + delta, 49);
          compare(17, true, true);
        }
      }
      // Synthetic meter-state fixtures isolate signed tails and consecutive
      // blocks.
      for (bool enabled : {false, true})
        for (int32_t count : sizes) {
          model.metering = enabled;
          require(metering(clone, enabled), "Own meter toggle rejected");
          uint8_t disabled = enabled ? 0 : 1;
          std::memcpy(static_cast<char *>(p) + 0x149, &disabled, 1);
          model.meters.fill(0);
          require(clearMeters(clone), "Own meter clear rejected");
          std::memcpy(static_cast<char *>(p) + 0x140, model.meters.data(), 8);
          compare(count, true, true);
          compare(count, false, false);
        } // Source-only invalid calls: original malformed input behavior is not
          // invoked.
      std::array<uint8_t, sizeof(vl::soft_clipper::Processor)> stableObject{};
      std::memcpy(stableObject.data(), clone, stableObject.size());
      std::array<uint8_t, 8> stableState{};
      std::array<float, 2> stableMeters{};
      require(save(clone, stableState.data(), 8) &&
                  getMeters(clone, stableMeters.data()),
              "Boundary snapshot failed");
      const auto unchanged = [&] {
        std::array<uint8_t, 8> bytes{};
        std::array<float, 2> peaks{};
        require(save(clone, bytes.data(), 8) &&
                    getMeters(clone, peaks.data()) && bytes == stableState &&
                    std::memcmp(peaks.data(), stableMeters.data(), 8) == 0,
                "Rejected call changed state/meters");
        std::array<uint8_t, sizeof(vl::soft_clipper::Processor)> objectBytes{};
        std::memcpy(objectBytes.data(), clone, objectBytes.size());
        require(objectBytes == stableObject,
                "Rejected call changed own object bytes");
        ++invalid;
      };
      for (const auto args :
           std::array<std::array<int32_t, 3>, 10>{{{-1, 0, 1},
                                                   {2, 0, 1},
                                                   {0, 0, 1},
                                                   {0, 128, 1},
                                                   {1, -1, 1},
                                                   {1, 161, 1},
                                                   {0, -1, 33},
                                                   {1, 1073741825, 33},
                                                   {0, 1, 4},
                                                   {1, 1, 64}}}) {
        int32_t result = 0x12345678;
        require(
            !parameter(clone, args[0], args[1], uint32_t(args[2]), &result) &&
                result == 0x12345678,
            "Invalid parameter not atomic");
        unchanged();
      }
      int32_t result = 0x12345678;
      require(!parameter(nullptr, 0, 1, 1, &result) && result == 0x12345678,
              "Null instance parameter accepted");
      unchanged();
      require(!parameter(clone, 0, 1, 1, nullptr), "Null result accepted");
      unchanged();
      std::array<float, 64> audio{}, output{};
      audio.fill(-.5f);
      output.fill(1234);
      const auto originalOutput = output;
      for (int32_t count : {-1, 1025}) {
        require(!render(clone, audio.data(), output.data(), count) &&
                    output == originalOutput,
                "Invalid frame render not atomic");
        unchanged();
      }
      require(!render(nullptr, audio.data(), output.data(), 16) &&
                  output == originalOutput,
              "Null render instance accepted");
      unchanged();
      require(!render(clone, nullptr, output.data(), 16) &&
                  output == originalOutput,
              "Null input accepted");
      unchanged();
      require(!render(clone, audio.data(), nullptr, 16),
              "Null output accepted");
      unchanged();
      for (bool forward : {false, true}) {
        const auto before = audio;
        require(!render(clone, audio.data() + (forward ? 0 : 1),
                        audio.data() + (forward ? 1 : 0), 16) &&
                    audio == before,
                "Partial overlap not atomic");
        unchanged();
      }
      for (uint32_t bits : {0x7f800000u, 0xff800000u, 0x7fc12345u, 0x7f812345u,
                            0x41800001u, 0xc1800001u})
        for (size_t index : {size_t(0), size_t(31)}) {
          audio.fill(-.5f);
          audio[index] = std::bit_cast<float>(bits);
          const auto before = audio;
          require(!render(clone, audio.data(), output.data(), 16) &&
                      output == originalOutput &&
                      std::memcmp(audio.data(), before.data(), sizeof(audio)) ==
                          0,
                  "Invalid sample not atomic");
          unchanged();
        }
      for (size_t size : {size_t(0), size_t(7), size_t(9)}) {
        std::array<uint8_t, 16> bytes{};
        bytes.fill(123);
        const auto before = bytes;
        require(!save(clone, bytes.data(), size) && bytes == before &&
                    !restore(clone, bytes.data(), size),
                "Invalid state size accepted or wrote data");
        unchanged();
      }
      for (const auto raw : std::array<std::array<int32_t, 2>, 4>{
               {{0, 128}, {128, 128}, {100, -1}, {100, 161}}}) {
        std::array<uint8_t, 8> bytes{};
        for (size_t i = 0; i < 2; ++i)
          for (size_t j = 0; j < 4; ++j)
            bytes[4 * i + j] = uint8_t(uint32_t(raw[i]) >> (8 * j));
        require(!restore(clone, bytes.data(), 8),
                "Malformed raw state accepted");
        unchanged();
      }
      require(!restore(clone, nullptr, 8) && !save(clone, nullptr, 8),
              "Null state bytes accepted");
      unchanged();
      require(!restore(nullptr, stableState.data(), 8),
              "Null restore instance accepted");
      unchanged();
      for (int enabled : {-1, 2}) {
        require(!metering(clone, enabled), "Invalid meter toggle accepted");
        unchanged();
      }
      require(!clearMeters(nullptr) && !metering(nullptr, 1) &&
                  !getMeters(clone, nullptr),
              "Invalid meter pointer accepted");
      unchanged();
      // Live-instance overlap regressions: these invalid ranges are rejected
      // before the API dereferences caller storage. Full object bytes are
      // pinned.
      const auto objectAddress = reinterpret_cast<uintptr_t>(clone);
      const auto address = [&](intptr_t offset) {
        return reinterpret_cast<void *>(objectAddress + offset);
      };
      for (intptr_t offset :
           {intptr_t(-3), intptr_t(0), intptr_t(4), intptr_t(12),
            intptr_t(sizeof(vl::soft_clipper::Processor) - 1)}) {
        require(
            !parameter(clone, 1, 0, 2, static_cast<int32_t *>(address(offset))),
            "Result/object overlap accepted");
        unchanged();
      }
      for (intptr_t offset :
           {intptr_t(-7), intptr_t(0), intptr_t(4), intptr_t(16),
            intptr_t(sizeof(vl::soft_clipper::Processor) - 1)}) {
        require(!save(clone, address(offset), 8),
                "Save/object overlap accepted");
        unchanged();
        require(!restore(clone, address(offset), 8),
                "Restore/object overlap accepted");
        unchanged();
        require(!getMeters(clone, static_cast<float *>(address(offset))),
                "Meter/object overlap accepted");
        unchanged();
      }
      for (intptr_t offset :
           {intptr_t(-31), intptr_t(0), intptr_t(4), intptr_t(16),
            intptr_t(sizeof(vl::soft_clipper::Processor) - 1)}) {
        require(!render(clone, static_cast<const float *>(address(offset)),
                        output.data(), 4) &&
                    output == originalOutput,
                "Input/object overlap accepted or wrote output");
        unchanged();
        const auto beforeAudio = audio;
        require(!render(clone, audio.data(),
                        static_cast<float *>(address(offset)), 4) &&
                    std::memcmp(audio.data(), beforeAudio.data(),
                                sizeof(audio)) == 0,
                "Output/object overlap accepted or changed input");
        unchanged();
      }
      require(!render(clone, static_cast<const float *>(address(0)),
                      output.data(), 0) &&
                  output == originalOutput,
              "Zero-frame input starts inside instance accepted");
      unchanged();
      require(!render(clone, audio.data(), static_cast<float *>(address(0)), 0),
              "Zero-frame output starts inside instance accepted");
      unchanged();
      compare(17, true, true);
      compareSave();
      destroy(clone);
      dlclose(rebuilt);
      method<void (*)(void *)>(p, 0xc8)(p);
      dlclose(lib);
      std::cout
          << std::dec
          << "{\"status\":\"passed\",\"actual_original_factory_created_and_"
             "destroyed\":true,\"compiled_numerical_c_abi_compared\":true,"
             "\"parameter_cases\":"
          << params << ",\"render_callbacks\":" << callbacks
          << ",\"stereo_frames\":" << frames << ",\"state_saves\":" << saves
          << ",\"state_restores\":" << restores
          << ",\"synthetic_meter_state_cases\":40,\"atomic_rejection_cases\":"
          << invalid << ",\"full_plugin_equivalence\":false}\n";
    } catch (const std::exception &e) {
      std::cerr << e.what() << '\n';
      return 1;
    }
  }
}
