#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This measured layout probe requires macOS arm64.
#endif
#include "center_dsp.hpp"
#include "center_plugin.h"
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <bit>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
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
  std::cerr << "host id=" << id << " index=" << index << " value=" << value
            << '\n';
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
  std::vector<uint32_t> lengths;
  bool nonNullCount = false;
};
extern "C" int32_t writeStream(Stream *s, const void *in, uint32_t length,
                               uint32_t *done) {
  require(s->cursor + length <= s->bytes.size(), "Oversize native state");
  std::memcpy(s->bytes.data() + s->cursor, in, length);
  s->cursor += length;
  s->lengths.push_back(length);
  s->nonNullCount |= done != nullptr;
  if (done)
    *done = length;
  return 0;
}

template <class T> void same(T a, T b, const char *field) {
  if (std::memcmp(&a, &b, sizeof(T))) {
    std::cerr << field << " actual=" << std::hexfloat << a << " expected=" << b
              << '\n';
    throw std::runtime_error(field);
  }
}
extern "C" int32_t readStream(Stream *s, void *out, uint32_t length,
                              uint32_t *done) {
  require(s->cursor + length <= s->bytes.size(), "Read outside valid framing");
  std::memcpy(out, s->bytes.data() + s->cursor, length);
  s->cursor += length;
  s->lengths.push_back(length);
  s->nonNullCount |= done != nullptr;
  if (done)
    *done = length;
  return 0;
}
std::string binaryHash(const char *path) {
  std::ifstream f(path, std::ios::binary);
  require(f.good(), "mapped dependency absent");
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
      require(argc == 4, "Usage source private_path/ rebuilt_library");
      std::ifstream f(argv[1], std::ios::binary);
      require(f.good(), "source absent");
      std::vector<uint8_t> b{std::istreambuf_iterator<char>(f), {}};
      std::array<uint8_t, 32> d{};
      CC_SHA256(b.data(), CC_LONG(b.size()), d.data());
      std::ostringstream h;
      for (auto v : d)
        h << std::hex << std::setfill('0') << std::setw(2) << unsigned(v);
      require(h.str() == "ab2bf0e97ba0e7a2be06a4711ee29039f32998ef5fd33272c7ded"
                         "5328e4f5da7",
              "source changed");
      require(
          binaryHash(
              "/Applications/FL Studio "
              "2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib") ==
              "f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd"
              "1",
          "mapped DSP identity changed");
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
      Dl_info own{};
      require(dladdr(reinterpret_cast<void *>(factory), &own), "factory base");
      auto *base = static_cast<char *>(own.dli_fbase);
      void *p = factory(host.data(), 42);
      require(p, "create");
      Dl_info kernel{}, copy{};
      void *k = load<void *>(base, 0x21c4f0), *c = load<void *>(base, 0x21b290);
      require(dladdr(k, &kernel) && kernel.dli_fbase == own.dli_fbase &&
                  static_cast<char *>(k) - base == 0x133d80,
              "centering kernel binding changed");
      require(
          dladdr(c, &copy) &&
              std::string(copy.dli_fname) ==
                  "/Applications/FL Studio "
                  "2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib" &&
              static_cast<char *>(c) - static_cast<char *>(copy.dli_fbase) ==
                  0x1c70c,
          "copy kernel binding changed");
      void *form = load<void *>(p, 0xc0);
      void *control = load<void *>(form, 0x910);
      require(load<int32_t>(control, 0x408) == 0 &&
                  load<int32_t>(control, 0x40c) == 1 &&
                  load<int32_t>(control, 0x410) == 1,
              "Original enable control range/default changed");
      using Parameter = int32_t (*)(void *, int32_t, int32_t, uint32_t);
      using Render = void (*)(void *, const float *, float *, int32_t);
      using Dispatch = intptr_t (*)(void *, intptr_t, intptr_t, intptr_t);
      auto parameter = method<Parameter>(p, 0xf8);
      auto render = method<Render>(p, 0x100);
      auto dispatch = method<Dispatch>(p, 0xd0);
      vl::center::Processor model;
      void *rebuilt = dlopen(argv[3], RTLD_NOW | RTLD_LOCAL);
      require(rebuilt, "compiled API load");
      const auto bind = [&](const char *name) {
        void *s = dlsym(rebuilt, name);
        require(s, "compiled API export absent");
        return s;
      };
      auto create = reinterpret_cast<decltype(&vl_center_create)>(
          bind("vl_center_create"));
      auto destroy = reinterpret_cast<decltype(&vl_center_destroy)>(
          bind("vl_center_destroy"));
      auto apiParam = reinterpret_cast<decltype(&vl_center_parameter)>(
          bind("vl_center_parameter"));
      auto apiRate = reinterpret_cast<decltype(&vl_center_sample_rate)>(
          bind("vl_center_sample_rate"));
      auto apiResume = reinterpret_cast<decltype(&vl_center_resume)>(
          bind("vl_center_resume"));
      auto apiRender = reinterpret_cast<decltype(&vl_center_render)>(
          bind("vl_center_render"));
      auto apiSave = reinterpret_cast<decltype(&vl_center_save_state)>(
          bind("vl_center_save_state"));
      auto apiRestore = reinterpret_cast<decltype(&vl_center_restore_state)>(
          bind("vl_center_restore_state"));
      auto apiFilter = reinterpret_cast<decltype(&vl_center_get_filter_state)>(
          bind("vl_center_get_filter_state"));
      auto *clone = create();
      require(clone, "compiled API instance");
      size_t frames = 0, calls = 0, params = 0, saves = 0, restores = 0,
             resumes = 0, rates = 0, synthetic = 0, rejections = 0;
      const auto check = [&] {
        int32_t got = -1;
        require(apiParam(clone, 0, 0, 2, &got), "API getter");
        same(got, model.enabled, "API enabled");
        std::array<double, 4> filter{};
        require(apiFilter(clone, filter.data()), "API filter state");
        for (size_t c = 0; c < 2; ++c) {
          same(filter[c], model.position[c], "API position");
          same(filter[c + 2], model.velocity[c], "API velocity");
        }
        same(load<int32_t>(p, 0x190), model.enabled, "enabled");
        same(load<float>(p, 0x12c), model.step, "rateCoefficient");
        for (size_t c = 0; c < 2; ++c) {
          same(load<double>(p, 0x150 + 8 * c), model.position[c], "position");
          same(load<double>(p, 0x160 + 8 * c), model.velocity[c], "velocity");
        }
        for (size_t off = 0x170; off < 0x190; off += 8)
          same(load<double>(p, off), 0.0, "unusedRuntime");
      };
      check();
      std::mt19937 random(0x564c434e);
      const std::array<int, 20> lengths{0,  1,  2,  3,   4,   7,   8,
                                        9,  15, 16, 17,  31,  32,  33,
                                        63, 64, 65, 257, 512, 1024};
      const auto change = [&](int value, uint32_t flags) {
        int32_t result = -7;
        require(apiParam(clone, 0, value, flags & 35, &result),
                "API parameter");
        const auto expected = model.parameter(value, flags);
        same(parameter(p, 0, value, flags), expected, "parameterReturn");
        same(result, expected, "API return");
        ++params;
        check();
      };
      const auto compare = [&](int count, bool alias, bool offset, int style) {
        size_t start = offset ? 1 : 0;
        std::vector<float> input(size_t(count) * 2 + 16),
            actual(input.size(), 1234), expected(actual);
        for (size_t i = 0; i < input.size(); ++i) {
          input[i] = style == 1 ? (i & 1 ? -.25f : .5f)
                     : style == 2
                         ? 0
                         : float(int32_t(random() % 65537) - 32768) / 2048;
          if (style == 0 && i % 13 == 0)
            input[i] = (i & 1) ? -0.0f : 0.0f;
        }
        std::vector<float> compiled(actual);
        auto beforeInput = input;
        auto beforeA = alias ? input : actual,
             beforeB = alias ? input : expected,
             beforeC = alias ? input : compiled;
        if (alias) {
          actual = input;
          expected = input;
          compiled = input;
          require(apiRender(clone, compiled.data() + start,
                            compiled.data() + start, count),
                  "API alias render");
          render(p, actual.data() + start, actual.data() + start, count);
          model.render(expected.data() + start, expected.data() + start, count);
        } else {
          require(apiRender(clone, input.data() + start,
                            compiled.data() + start, count),
                  "API disjoint render");
          render(p, input.data() + start, actual.data() + start, count);
          model.render(input.data() + start, expected.data() + start, count);
        }
        for (size_t i = 0; i < actual.size(); ++i) {
          same(std::bit_cast<uint32_t>(actual[i]),
               std::bit_cast<uint32_t>(expected[i]), "sampleBits");
          same(std::bit_cast<uint32_t>(actual[i]),
               std::bit_cast<uint32_t>(compiled[i]), "compiledSampleBits");
          if (i < start || i >= start + 2 * size_t(count)) {
            same(actual[i], beforeA[i], "nativeGuard");
            same(expected[i], beforeB[i], "modelGuard");
            same(compiled[i], beforeC[i], "compiledGuard");
          }
        }
        require(std::memcmp(input.data(), beforeInput.data(),
                            input.size() * 4) == 0,
                "source input changed");
        frames += count;
        ++calls;
        check();
      };
      for (uint32_t flag : {0u, 1u, 2u, 3u, 32u, 33u, 34u, 35u})
        for (int value : {0, 1}) {
          change(flag & 32 ? value << 30 : value, flag);
          compare(9, false, true, 0);
        }
      for (int value : {0, 1, (1 << 29) - 1, 1 << 29, (1 << 29) + 1,
                        (1 << 30) - 1, 1 << 30})
        for (uint32_t flag : {32u, 33u, 34u, 35u})
          change(value, flag);
      const std::array<int32_t, 8> sampleRates{8000,  11025, 22050,  44100,
                                               48000, 96000, 192000, 384000};
      for (size_t seq = 0; seq < 1024; ++seq) {
        if (seq % 17 == 0) {
          const auto rate = (seq / 17) % 2
                                ? 8000 + int(random() % 376001)
                                : sampleRates[(seq / 17) % sampleRates.size()];
          dispatch(p, 4, 0, rate);
          model.sampleRate(rate);
          require(apiRate(clone, rate), "API rate");
          ++rates;
          check();
        }
        change(int(seq & 1), 17);
        for (size_t j = 0; j < 4; ++j)
          compare(lengths[(seq + j) % lengths.size()], (j & 1) != 0,
                  (seq & 1) != 0, int(seq % 3));
        if (seq % 23 == 0) {
          dispatch(p, 2, 0, 0);
          model.resume();
          require(apiResume(clone), "API resume");
          ++resumes;
          check();
        }
      }
      // Long uninterrupted constant and silence sequences exercise settling
      // history over repeated block-end flushes without toggles or resets.
      dispatch(p, 4, 0, 44100);
      model.sampleRate(44100);
      require(apiRate(clone, 44100), "API long-sequence rate");
      ++rates;
      change(1, 17);
      dispatch(p, 2, 0, 0);
      model.resume();
      require(apiResume(clone), "API long-sequence resume");
      ++resumes;
      for (size_t i = 0; i < 1024; ++i)
        compare(1024, bool(i & 1), bool((i / 2) & 1), i < 512 ? 1 : 2);
      // Inject only known four-double runtime fields to verify native block-end
      // flushing, including zero frames, strict threshold and disabled
      // preservation.
      for (int enabled : {0, 1})
        for (double value : {0.0, -0.0, 0x1p-25, -0x1p-25, 0x1p-24, -0x1p-24,
                             std::nextafter(0x1p-24, 0.0),
                             std::nextafter(0x1p-24, 1.0), 0x1p-100, -0x1p-100})
          for (int count : {0, 1, 3, 8, 9}) {
            change(enabled, 17);
            model.position = {value, -value};
            model.velocity = {-value, value};
            for (size_t c = 0; c < 2; ++c) {
              std::memcpy(static_cast<char *>(p) + 0x150 + 8 * c,
                          &model.position[c], 8);
              std::memcpy(static_cast<char *>(p) + 0x160 + 8 * c,
                          &model.velocity[c], 8);
            } // This test alone installs the known own sole-Processor object
              // representation
            // to match the four synthetic original filter-state doubles.
            std::memcpy(clone, &model, sizeof(model));
            compare(count, (count & 1) != 0, false, 2);
            ++synthetic;
          }

      std::array<void *, 5> streamTable{};
      streamTable[3] = reinterpret_cast<void *>(&readStream);
      streamTable[4] = reinterpret_cast<void *>(&writeStream);
      Stream stream{};
      stream.vmt = streamTable.data();
      auto state = method<void (*)(void *, Stream *, int32_t)>(p, 0xe0);
      const auto compareSave = [&] {
        stream.cursor = 0;
        stream.lengths.clear();
        stream.nonNullCount = false;
        state(p, &stream, 1);
        require(stream.cursor == 8 &&
                    stream.lengths == std::vector<uint32_t>{4, 4} &&
                    !stream.nonNullCount &&
                    load<uint32_t>(stream.bytes.data(), 0) == 1 &&
                    load<int32_t>(stream.bytes.data(), 4) == model.enabled,
                "save framing");
        std::array<uint8_t, 8> saved{};
        require(apiSave(clone, saved.data(), saved.size()), "API save");
        require(std::memcmp(saved.data(), stream.bytes.data(), 8) == 0,
                "compiled saved framing");
        ++saves;
      };
      compareSave();
      for (size_t seq = 0; seq < 256; ++seq) {
        const uint32_t version = uint32_t(seq & 1),
                       enabled = uint32_t((seq / 2) & 1);
        std::memcpy(stream.bytes.data(), &version, 4);
        std::memcpy(stream.bytes.data() + 4, &enabled, 4);
        stream.cursor = 0;
        stream.lengths.clear();
        stream.nonNullCount = false;
        state(p, &stream, 0);
        require(stream.cursor == 8 &&
                    stream.lengths == std::vector<uint32_t>{4, 4} &&
                    !stream.nonNullCount,
                "restore framing");
        require(apiRestore(clone, stream.bytes.data(), 8), "API valid restore");
        model.enabled = int32_t(enabled);
        ++restores;
        check();
        compareSave();
        compare(lengths[seq % lengths.size()], bool(seq & 1),
                bool((seq / 2) & 1), int(seq % 3));
      }
      // Independent ABI rejection corpus never sends malformed data to source.
      const auto reject = [&](auto action) {
        std::array<uint8_t, sizeof(vl::center::Processor)> before{}, after{};
        std::memcpy(before.data(), clone, before.size());
        require(action() == 0, "invalid API call accepted");
        std::memcpy(after.data(), clone, after.size());
        require(before == after, "rejected API call changed complete object");
        ++rejections;
        check();
      };
      int32_t result = -123;
      for (int32_t index : {-1, 1, INT32_MAX})
        reject([&] { return apiParam(clone, index, 0, 2, &result); });
      for (int32_t value : {-1, 2, INT32_MAX})
        reject([&] { return apiParam(clone, 0, value, 1, &result); });
      for (int32_t value : {-1, (1 << 30) + 1, INT32_MAX})
        reject([&] { return apiParam(clone, 0, value, 33, &result); });
      for (uint32_t flag : {4u, 8u, 16u, 64u, 0xffffffffu})
        reject([&] { return apiParam(clone, 0, 0, flag, &result); });
      reject([&] { return apiParam(clone, 0, 0, 2, nullptr); });
      require(result == -123, "invalid parameter wrote result");
      for (int32_t rate : {0, 7999, 384001, INT32_MAX})
        reject([&] { return apiRate(clone, rate); });
      std::array<float, 32> badInput{}, badOutput{};
      badOutput.fill(42);
      const auto beforeOutput = badOutput;
      for (int32_t count : {-1, 1025, INT32_MAX})
        reject([&] {
          return apiRender(clone, badInput.data(), badOutput.data(), count);
        });
      reject([&] { return apiRender(clone, nullptr, badOutput.data(), 1); });
      reject([&] { return apiRender(clone, badInput.data(), nullptr, 1); });
      reject([&] {
        return apiRender(clone, badInput.data(), badInput.data() + 1, 8);
      });
      for (float value : {std::numeric_limits<float>::quiet_NaN(), INFINITY,
                          -INFINITY, 16.01f, -16.01f}) {
        badInput[0] = value;
        reject([&] {
          return apiRender(clone, badInput.data(), badOutput.data(), 8);
        });
      }
      require(badOutput == beforeOutput,
              "rejected render changed caller output");
      badInput[0] = 0;
      std::array<uint8_t, 8> bytes{};
      bytes[0] = 1;
      bytes[4] = 1;
      auto beforeBytes = bytes;
      for (size_t len : {size_t(0), size_t(7), size_t(9), SIZE_MAX}) {
        reject([&] { return apiSave(clone, bytes.data(), len); });
        reject([&] { return apiRestore(clone, bytes.data(), len); });
      }
      require(bytes == beforeBytes, "rejected save changed bytes");
      bytes[0] = 2;
      reject([&] { return apiRestore(clone, bytes.data(), 8); });
      bytes[0] = 1;
      bytes[4] = 2;
      reject([&] { return apiRestore(clone, bytes.data(), 8); });
      reject([&] { return apiSave(clone, nullptr, 8); });
      reject([&] { return apiRestore(clone, nullptr, 8); });
      reject([&] { return apiFilter(clone, nullptr); });
      const auto insideAddress = [&](ptrdiff_t off) {
        const auto baseAddress = reinterpret_cast<uintptr_t>(clone);
        return off < 0 ? baseAddress - size_t(-off) : baseAddress + size_t(off);
      };
      for (ptrdiff_t off : {ptrdiff_t(-3), ptrdiff_t(0), ptrdiff_t(4),
                            ptrdiff_t(sizeof(vl::center::Processor) - 1)})
        reject([&] {
          return apiParam(clone, 0, 0, 2,
                          reinterpret_cast<int32_t *>(insideAddress(off)));
        });
      for (ptrdiff_t off : {ptrdiff_t(-7), ptrdiff_t(0), ptrdiff_t(8),
                            ptrdiff_t(sizeof(vl::center::Processor) - 1)}) {
        auto *pbytes = reinterpret_cast<uint8_t *>(insideAddress(off));
        reject([&] { return apiSave(clone, pbytes, 8); });
        reject([&] { return apiRestore(clone, pbytes, 8); });
      }
      for (ptrdiff_t off : {ptrdiff_t(-31), ptrdiff_t(0), ptrdiff_t(8),
                            ptrdiff_t(sizeof(vl::center::Processor) - 1)})
        reject([&] {
          return apiFilter(clone,
                           reinterpret_cast<double *>(insideAddress(off)));
        });
      for (ptrdiff_t off : {ptrdiff_t(-7), ptrdiff_t(0), ptrdiff_t(8),
                            ptrdiff_t(sizeof(vl::center::Processor) - 1)}) {
        auto *samples = reinterpret_cast<float *>(insideAddress(off));
        reject([&] { return apiRender(clone, samples, badOutput.data(), 1); });
        reject([&] { return apiRender(clone, badInput.data(), samples, 1); });
        if (off >= 0) {
          reject([&] { return apiRender(clone, samples, samples, 0); });
        }
      }
      // Zero-frame nullable buffers are valid; flush semantics remain active.
      render(p, nullptr, nullptr, 0);
      model.render(nullptr, nullptr, 0);
      require(apiRender(clone, nullptr, nullptr, 0),
              "null zero-frame call rejected");
      ++calls;
      check();
      require(apiParam(nullptr, 0, 0, 2, &result) == 0 &&
                  apiRate(nullptr, 44100) == 0 && apiResume(nullptr) == 0 &&
                  apiRender(nullptr, nullptr, nullptr, 0) == 0 &&
                  apiSave(nullptr, bytes.data(), 8) == 0 &&
                  apiRestore(nullptr, bytes.data(), 8) == 0 &&
                  apiFilter(nullptr, nullptr) == 0,
              "null instance accepted");
      rejections += 7;
      destroy(nullptr);
      destroy(clone);
      dlclose(rebuilt);
      method<void (*)(void *)>(p, 0xc8)(p);
      dlclose(lib);
      std::cout << "{\"status\":\"passed_private_compiled_api\",\"actual_"
                   "factory_created_and_destroyed\":true,\"compiled_numerical_"
                   "c_api_compared\":true,\"parameter_cases\":"
                << params << ",\"render_callbacks\":" << calls
                << ",\"stereo_frames\":" << frames
                << ",\"sample_rate_changes\":" << rates
                << ",\"resume_resets\":" << resumes
                << ",\"synthetic_runtime_flush_cases\":" << synthetic
                << ",\"state_saves\":" << saves
                << ",\"state_restores\":" << restores
                << ",\"atomic_rejection_cases\":" << rejections
                << ",\"full_plugin_equivalence\":false}\n";
    } catch (const std::exception &e) {
      std::cerr << e.what() << '\n';
      return 1;
    }
  }
}
