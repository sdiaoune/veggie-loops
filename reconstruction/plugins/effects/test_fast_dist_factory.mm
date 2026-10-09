#include "fast_dist_dsp.hpp"
#include "fast_dist_plugin.h"
#import <Cocoa/Cocoa.h>
#include <bit>
#include <memory>
#include <random>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This measured layout probe requires macOS arm64.
#endif
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
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
using ActualDistortion = void (*)(void *, int32_t, int32_t, float *, int32_t,
                                  float, float, float);
ActualDistortion actualDistortion = nullptr;
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
extern "C" void hostDistortion(void *host, int32_t type, int32_t threshold,
                               float *buffer, int32_t count, float dry,
                               float wet, float multiplier) {
  (void)host;
  (void)buffer;
  require(actualDistortion, "actual distortion unbound");
  actualDistortion(host, type, threshold, buffer, count, dry, wet, multiplier);
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
  std::cerr << "write=" << length << " completion=" << done << '\n';
  return 0;
}
extern "C" int32_t readStream(Stream *s, void *out, uint32_t length,
                              uint32_t *done) {
  require(s->cursor + length <= s->bytes.size(), "Oversize native read");
  std::memcpy(out, s->bytes.data() + s->cursor, length);
  s->cursor += length;
  if (done)
    *done = length;
  return 0;
}
int main(int argc, char **argv) {
  @autoreleasepool {
    try {
      require(argc == 4, "Usage source private_path/ inspected_engine");
      std::ifstream f(argv[1], std::ios::binary);
      require(f.good(), "source absent");
      std::vector<uint8_t> b{std::istreambuf_iterator<char>(f), {}};
      std::array<uint8_t, 32> d{};
      CC_SHA256(b.data(), CC_LONG(b.size()), d.data());
      std::ostringstream h;
      for (auto v : d)
        h << std::hex << std::setfill('0') << std::setw(2) << unsigned(v);
      require(h.str() == "22b0fc6fa9f3cc065587f5e142ec047d8877432454ca7c25aba9e"
                         "4eb195c5b82",
              "source changed");
      std::ifstream engineFile(argv[3], std::ios::binary);
      require(engineFile.good(), "engine source absent");
      std::vector<uint8_t> engineBytes{
          std::istreambuf_iterator<char>(engineFile), {}};
      std::array<uint8_t, 32> engineDigest{};
      CC_SHA256(engineBytes.data(), CC_LONG(engineBytes.size()),
                engineDigest.data());
      std::ostringstream engineHex;
      for (auto v : engineDigest)
        engineHex << std::hex << std::setfill('0') << std::setw(2)
                  << unsigned(v);
      require(engineHex.str() == "22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d44"
                                 "1371e3c27704317bd37",
              "engine changed");
      void *engine = dlopen(argv[3], RTLD_NOW | RTLD_LOCAL);
      require(engine, "engine dlopen failed");
      Dl_info engineImage{};
      require(dladdr(dlsym(engine, "CreateFruityInstance"), &engineImage),
              "engine base absent");
      auto *engineBase = static_cast<char *>(engineImage.dli_fbase);
      require(load<void *>(engineBase, 0x109e180 + 0x188) ==
                  engineBase + 0x3d5ff0,
              "host vmt distortion target changed");
      actualDistortion =
          reinterpret_cast<ActualDistortion>(engineBase + 0x3d5ff0);
      reinterpret_cast<void (*)()>(engineBase + 0x3e5980)();
      std::cout << "actual_table_initializer_called=true\n";
      using namespace veggie_loops::fast_dist;
      auto tables = std::make_unique<Tables>();
      size_t comparedTableEntries = 0;
      for (int32_t type = 0; type < 2; ++type)
        for (int32_t threshold = 1; threshold <= 10; ++threshold) {
          const auto *native = reinterpret_cast<const int16_t *>(
              engineBase + 0x18d9768 + type * 0x28028 +
              (threshold - 1) * 0x4004);
          const auto &row = tables->values[size_t(type)][size_t(threshold - 1)];
          for (size_t i = 0; i < row.size(); ++i) {
            if (native[i] != row[i]) {
              std::cerr << "table mismatch type=" << type
                        << " threshold=" << threshold << " index=" << i
                        << " native=" << native[i] << " model=" << row[i]
                        << '\n';
              require(false, "table reconstruction mismatch");
            }
            ++comparedTableEntries;
          }
        }
      std::cout << "independently_generated_table_entries_compared=" << std::dec
                << comparedTableEntries << '\n';

      for (int32_t type = 0; type < 2; ++type)
        for (int32_t threshold = 1; threshold <= 10; ++threshold) {
          auto *row = reinterpret_cast<const int16_t *>(
              engineBase + 0x18d9768 + type * 0x28028 +
              (threshold - 1) * 0x4004 + 2);
          std::cout << "table_type=" << type << " threshold=" << threshold
                    << " first=" << row[0] << " middle=" << row[4096]
                    << " last=" << row[8191] << '\n';
        }
      std::cout << "actual_host_global_selector="
                << int(load<uint8_t>(engineBase, 0x19b4a28)) << '\n';
      for (size_t off : {size_t(0x18d8678), size_t(0x18d8680)}) {
        auto *fn = load<void *>(engineBase, off);
        Dl_info dep{};
        require(dladdr(fn, &dep), "host distortion dependency absent");
        std::cout << "host_dependency=" << dep.dli_fname << " slot=" << std::hex
                  << off << " function="
                  << (static_cast<char *>(fn) -
                      static_cast<char *>(dep.dli_fbase))
                  << " symbol=" << (dep.dli_sname ? dep.dli_sname : "unknown")
                  << '\n';
      }
      [NSApplication sharedApplication];
      privatePath = argv[2];
      hostTable.fill(reinterpret_cast<void *>(&noop));
      pathTable.fill(reinterpret_cast<void *>(&noop));
      hostTable[0xc8 / 8] = reinterpret_cast<void *>(&hostDispatch);
      hostTable[0x188 / 8] = reinterpret_cast<void *>(&hostDistortion);
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
      void *copy = load<void *>(base, 0x22fef8);
      Dl_info copyImage{};
      require(dladdr(copy, &copyImage) && copyImage.dli_fname,
              "copy dependency absent");
      require(std::string(copyImage.dli_fname) ==
                  "/Applications/FL Studio "
                  "2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib",
              "unexpected copy dependency image");
      std::ifstream copyFile(copyImage.dli_fname, std::ios::binary);
      require(copyFile.good(), "copy dependency unreadable");
      std::vector<uint8_t> copyBytes{std::istreambuf_iterator<char>(copyFile),
                                     {}};
      std::array<uint8_t, 32> copyDigest{};
      CC_SHA256(copyBytes.data(), CC_LONG(copyBytes.size()), copyDigest.data());
      std::ostringstream copyHex;
      for (auto v : copyDigest)
        copyHex << std::hex << std::setfill('0') << std::setw(2) << unsigned(v);
      require(copyHex.str() == "f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc9"
                               "5ff0aaf3df8a76cd1",
              "copy dependency changed");
      require(static_cast<char *>(copy) -
                      static_cast<char *>(copyImage.dli_fbase) ==
                  0x1c70c,
              "copy implementation changed");
      void *p = factory(host.data(), 42);
      require(p, "create");
      std::cout << "vmt=" << std::hex
                << (reinterpret_cast<char *>(load<void *>(p, 0)) - base)
                << '\n';
      for (size_t off = 0xc8; off <= 0x160; off += 8)
        std::cout << "slot=" << std::hex << off << " fn="
                  << (reinterpret_cast<char *>(load<void **>(p, 0)[off / 8]) -
                      base)
                  << '\n';
      void *info = load<void *>(p, 0x10);
      std::cout << "flags=" << load<uint32_t>(info, 20)
                << " params=" << std::dec << load<int32_t>(info, 24) << '\n';
      void *form = load<void *>(p, 0xc0);
      for (int i = 0; i < 5; ++i) {
        void *k = load<void *>(form, 0xaa0 + 8 * i);
        std::cout << "control=" << i << " min=" << load<int32_t>(k, 0x408)
                  << " max=" << load<int32_t>(k, 0x40c)
                  << " default=" << load<int32_t>(k, 0x410)
                  << " scale=" << std::hexfloat << load<double>(k, 0x430)
                  << '\n';
      }
      for (size_t off = 0x128; off < 0x14c; off += 4)
        std::cout << "field=" << std::hex << off
                  << " word=" << load<uint32_t>(p, off)
                  << " float=" << std::hexfloat << load<float>(p, off) << '\n';
      void *dsp = load<void *>(p, 0xb8);
      void *fn = load<void **>(dsp, 0)[0x188 / 8];
      Dl_info dep{};
      require(dladdr(fn, &dep), "dsp mapping");
      std::cout << "dsp_image=" << dep.dli_fname << " slot188=" << std::hex
                << (static_cast<char *>(fn) -
                    static_cast<char *>(dep.dli_fbase))
                << '\n';
      for (size_t off : {size_t(0x20bd60), size_t(0x228dcc), size_t(0x20bd54)})
        std::cout << "constant=" << std::hex << off
                  << " value=" << std::hexfloat << load<float>(base, off)
                  << '\n';
      std::array<void *, 5> streamVmt{};
      streamVmt[4] = reinterpret_cast<void *>(&writeStream);
      Stream stream{streamVmt.data()};
      method<void (*)(void *, Stream *, int32_t)>(p, 0xe0)(p, &stream, 1);
      std::cout << "state_bytes=" << stream.cursor << " bytes=";
      for (size_t i = 0; i < stream.cursor; ++i)
        std::cout << std::hex << std::setfill('0') << std::setw(2)
                  << unsigned(stream.bytes[i]);
      std::cout << '\n';
      Processor model;
      auto *compiled = vl_fast_dist_create(0);
      require(compiled, "Compiled numerical allocation");
      using Parameter = int32_t (*)(void *, int32_t, int32_t, int32_t);
      const auto parameter = method<Parameter>(p, 0xf8);
      const auto compareCoefficients = [&] {
        std::array<float, 3> api{};
        require(vl_fast_dist_get_coefficients(compiled, api.data()),
                "Compiled coefficient inspection");
        require(std::bit_cast<uint32_t>(api[0]) ==
                        std::bit_cast<uint32_t>(model.dry) &&
                    std::bit_cast<uint32_t>(api[1]) ==
                        std::bit_cast<uint32_t>(model.wet) &&
                    std::bit_cast<uint32_t>(api[2]) ==
                        std::bit_cast<uint32_t>(model.multiplier),
                "Compiled coefficients differ from native-bound model");
        for (const auto pair : {std::pair{size_t(0x13c), model.dry},
                                std::pair{size_t(0x140), model.wet},
                                std::pair{size_t(0x144), model.multiplier}}) {
          const float native = load<float>(p, pair.first);
          if (std::bit_cast<uint32_t>(native) !=
              std::bit_cast<uint32_t>(pair.second)) {
            std::cerr << "coefficient mismatch field=" << std::hex << pair.first
                      << " native=" << std::hexfloat << native
                      << " model=" << pair.second << '\n';
            require(false, "coefficient parity");
          }
        }
      };
      compareCoefficients();
      size_t parameterCases = 0, renderCalls = 0, stereoFrames = 0;
      const std::array<int32_t, 5> minimum{64, 1, 0, 0, 0},
          maximum{192, 10, 1, 128, 128};
      for (int32_t index = 0; index < 5; ++index)
        for (int32_t raw = minimum[size_t(index)];
             raw <= maximum[size_t(index)]; ++raw) {
          require(parameter(p, index, raw, 1) == raw, "native raw result");
          int32_t result = -1;
          require(vl_fast_dist_parameter(compiled, index, raw, 1, &result) &&
                      result == raw,
                  "Compiled raw parameter");
          model.set(index, raw);
          compareCoefficients();
          ++parameterCases;
        }
      std::mt19937 controlRandom(0x50415241);
      for (int32_t index = 0; index < 5; ++index)
        for (uint32_t flags : {0u, 1u, 2u, 3u, 32u, 33u, 34u, 35u})
          for (size_t n = 0; n < 512; ++n) {
            int32_t value;
            if (flags & 32u) {
              constexpr std::array<int32_t, 7> edges{0,
                                                     1,
                                                     (1 << 29) - 1,
                                                     1 << 29,
                                                     (1 << 29) + 1,
                                                     (1 << 30) - 1,
                                                     1 << 30};
              value = n < edges.size() ? edges[n]
                                       : int32_t(controlRandom() % 0x40000001u);
            } else if ((flags & 2u) && !(flags & 1u)) {
              value = 0;
            } else {
              value = minimum[size_t(index)] +
                      int32_t(controlRandom() %
                              uint32_t(maximum[size_t(index)] -
                                       minimum[size_t(index)] + 1));
            }
            const int32_t native = parameter(p, index, value, int32_t(flags));
            int32_t own = -1;
            require(
                vl_fast_dist_parameter(compiled, index, value, flags, &own) &&
                    own == native,
                "Compiled normalized/flag result");
            if (flags & 1u)
              model.set(index, native);
            compareCoefficients();
            ++parameterCases;
          }
      size_t stateSaves = 0, stateRestores = 0;
      std::array<uint8_t, 20> packet{};
      streamVmt[3] = reinterpret_cast<void *>(&readStream);
      for (size_t i = 0; i < 256; ++i) {
        stream.cursor = 0;
        method<void (*)(void *, Stream *, int32_t)>(p, 0xe0)(p, &stream, 1);
        require(stream.cursor == 20 &&
                    vl_fast_dist_save_state(compiled, packet.data(),
                                            packet.size()) &&
                    std::memcmp(packet.data(), stream.bytes.data(), 20) == 0,
                "Compiled/native valid state save");
        ++stateSaves;
        for (int32_t index = 0; index < 5; ++index) {
          const int32_t raw =
              minimum[size_t(index)] +
              int32_t(controlRandom() % uint32_t(maximum[size_t(index)] -
                                                 minimum[size_t(index)] + 1));
          for (size_t byte = 0; byte < 4; ++byte)
            stream.bytes[size_t(index) * 4 + byte] =
                uint8_t(uint32_t(raw) >> (8 * byte));
          model.raw[size_t(index)] = raw;
        }
        model.set(0, model.raw[0]);
        stream.cursor = 0;
        method<void (*)(void *, Stream *, int32_t)>(p, 0xe0)(p, &stream, 0);
        require(stream.cursor == 20 && vl_fast_dist_restore_state(
                                           compiled, stream.bytes.data(), 20),
                "Compiled/native valid state restore");
        compareCoefficients();
        ++stateRestores;
      }
      std::mt19937 random(0x46415354);
      constexpr std::array<int32_t, 12> lengths{0, 1,  2,  3,  7,   8,
                                                9, 16, 17, 63, 257, 1024};
      const auto nativeRender =
          method<void (*)(void *, const float *, float *, int32_t)>(p, 0x100);
      const auto selector = load<uint8_t>(engineBase, 0x19b4a28);
      for (int quality = 0; quality < 2; ++quality) {
        // Synthetic quality-state fixture within this process only; the source
        // library/application files are never modified. Original value
        // restored.
        *(engineBase + 0x19b4a28) = char(quality);
        require(vl_fast_dist_quality(compiled, quality), "Compiled quality");
        for (size_t iteration = 0; iteration < 2400; ++iteration) {
          for (int32_t index = 0; index < 5; ++index) {
            const int32_t raw =
                minimum[size_t(index)] +
                int32_t(random() % uint32_t(maximum[size_t(index)] -
                                            minimum[size_t(index)] + 1));
            require(parameter(p, index, raw, 1) == raw, "native random raw");
            int32_t result = -1;
            require(vl_fast_dist_parameter(compiled, index, raw, 1, &result) &&
                        result == raw,
                    "Compiled random parameter");
            model.set(index, raw);
            ++parameterCases;
          }
          compareCoefficients();
          const int32_t count = lengths[iteration % lengths.size()];
          const size_t samples = size_t(count) * 2;
          std::vector<float> input(samples + 8), native(samples + 8, 1234.0f),
              rebuilt(samples + 8, 1234.0f);
          for (size_t i = 0; i < input.size(); ++i)
            input[i] = float(int32_t(random() % 1048577u) - 524288) * 0x1p-15f;
          if (samples > 1) {
            input[0] = -0.0f;
            input[1] = 0.0f;
          }
          if (samples > 3) {
            input[2] = -0x1p-15f;
            input[3] = 0x1p-15f;
          }
          const auto before = input;
          const bool alias = iteration % 3 == 0;
          if (alias) {
            native = input;
            rebuilt = input;
          }
          nativeRender(p, alias ? native.data() : input.data(), native.data(),
                       count);
          model.render(*tables, alias ? rebuilt.data() : input.data(),
                       rebuilt.data(), count, quality != 0);
          std::vector<float> apiOutput(samples + 8, 1234.0f);
          if (alias)
            apiOutput = before;
          require(vl_fast_dist_render(compiled,
                                      alias ? apiOutput.data() : input.data(),
                                      apiOutput.data(), count),
                  "Compiled rendering");
          for (size_t i = 0; i < samples; ++i) {
            if (std::bit_cast<uint32_t>(native[i]) !=
                    std::bit_cast<uint32_t>(rebuilt[i]) ||
                std::bit_cast<uint32_t>(native[i]) !=
                    std::bit_cast<uint32_t>(apiOutput[i])) {
              std::cerr << "render mismatch quality=" << quality
                        << " iteration=" << iteration << " sample=" << i
                        << " input=" << std::hexfloat << input[i]
                        << " native=" << native[i] << " model=" << rebuilt[i]
                        << '\n';
              require(false, "DSP sample parity");
            }
          }
          for (size_t i = samples; i < samples + 8; ++i) {
            const float guard = alias ? before[i] : 1234.0f;
            require(std::bit_cast<uint32_t>(native[i]) ==
                            std::bit_cast<uint32_t>(guard) &&
                        std::bit_cast<uint32_t>(rebuilt[i]) ==
                            std::bit_cast<uint32_t>(guard) &&
                        std::bit_cast<uint32_t>(apiOutput[i]) ==
                            std::bit_cast<uint32_t>(guard),
                    "independent sample guards");
          }
          require(std::memcmp(input.data(), before.data(),
                              input.size() * sizeof(float)) == 0,
                  "source immutability");
          ++renderCalls;
          stereoFrames += size_t(count);
        }
      }
      *(engineBase + 0x19b4a28) = char(selector);
      std::cout << "parameters_compared=" << std::dec << parameterCases
                << " callbacks_compared=" << renderCalls
                << " stereo_frames=" << stereoFrames << '\n';
      std::cout << "state_saves=" << stateSaves
                << " state_restores=" << stateRestores << '\n';
      using Dispatch = intptr_t (*)(void *, intptr_t, intptr_t, intptr_t);
      const auto dispatch = method<Dispatch>(p, 0xd0);
      for (intptr_t index = 0; index < 5; ++index)
        std::cout << "class=" << index << " value=" << dispatch(p, 52, index, 0)
                  << '\n';
      vl_fast_dist_destroy(compiled);
      method<void (*)(void *)>(p, 0xc8)(p);
      dlclose(lib);
      dlclose(engine);
      std::cout
          << "{\"status\":\"passed_private_compiled_api\",\"factory_created_"
             "and_destroyed\":true,\"actual_engine_table_initializer_and_"
             "distortion_used\":true,\"independently_generated_table_entries\":"
          << std::dec << comparedTableEntries
          << ",\"parameter_cases\":" << parameterCases
          << ",\"render_callbacks\":" << renderCalls
          << ",\"stereo_frames\":" << stereoFrames
          << ",\"state_saves\":" << stateSaves
          << ",\"state_restores\":" << stateRestores
          << ",\"synthetic_host_quality_states\":2,\"source_input_and_"
             "independent_guards_checked\":true,\"full_plugin_equivalence\":"
             "false}\n";
    } catch (const std::exception &e) {
      std::cerr << e.what() << '\n';
      return 1;
    }
  }
}
