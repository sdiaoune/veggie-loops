#include "three_osc_tables.hpp"

#if !defined(__APPLE__) || !defined(__aarch64__)
#error This identity-bound comparison requires macOS on Apple Silicon.
#endif
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>

#include <bit>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>

using namespace veggie_loops::three_osc;

namespace {
void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}
std::string digestFile(const char* path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "Cannot read native engine");
  std::vector<char> bytes{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
  std::array<unsigned char, 32> result{};
  CC_SHA256(bytes.data(), static_cast<CC_LONG>(bytes.size()), result.data());
  std::ostringstream output;
  for (auto byte : result) output << std::hex << std::setfill('0') << std::setw(2) << unsigned(byte);
  return output.str();
}
template <typename T> T symbol(void* library, const char* name) {
  void* address = dlsym(library, name);
  require(address != nullptr, std::string("Missing native symbol ") + name);
  return reinterpret_cast<T>(address);
}
struct Library {
  void* handle;
  explicit Library(const char* path) : handle(dlopen(path, RTLD_NOW | RTLD_LOCAL)) {
    const char* failure = handle ? nullptr : dlerror();
    require(handle != nullptr, failure ? failure : "Cannot load reviewed DSP engine");
  }
  ~Library() { if (handle) dlclose(handle); }
};
struct Comparison {
  std::size_t values = 0;
  std::size_t unequal = 0;
  double maximumError = 0;
  void check(float a, float b, bool exact, const char* context) {
    ++values;
    if (std::bit_cast<std::uint32_t>(a) == std::bit_cast<std::uint32_t>(b)) return;
    ++unequal;
    const double error = std::fabs(static_cast<double>(a) - b);
    maximumError = std::max(maximumError, error);
    if (exact || !std::isfinite(error) || error > 0.00015 * (1.0 + std::fabs(a))) {
      std::ostringstream message;
      message << context << " mismatch, native=" << std::setprecision(10) << a
              << ", model=" << b << ", error=" << error;
      throw std::runtime_error(message.str());
    }
  }
};
}  // namespace

int main(int argc, char** argv) {
  try {
    require(argc == 4, "Usage: test_three_osc_tables <installed engine> <recompiled library> <report.json>");
    require(digestFile(argv[1]) == "d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f",
            "Installed DSP engine identity mismatch");
    Library native(argv[1]), model(argv[2]);
    using Allocate = void* (*)(int, int, void*, std::size_t*);
    using Transform = void (*)(void*, const FourLaneComplex*, FourLaneComplex*, int);
    using NextSize = int (*)(int);
    using Dispatch = std::uintptr_t (*)(OscState*, std::int32_t, std::intptr_t);
    const auto nativeAllocate = symbol<Allocate>(native.handle, "kiss_fft_alloc");
    const auto modelAllocate = symbol<Allocate>(model.handle, "kiss_fft_alloc");
    const auto nativeTransform = symbol<Transform>(native.handle, "kiss_fft_stride");
    const auto modelTransform = symbol<Transform>(model.handle, "kiss_fft_stride");
    const auto nativeNextSize = symbol<NextSize>(native.handle, "kiss_fft_next_fast_size");
    symbol<void (*)()>(native.handle, "kiss_fft_cleanup")();
    symbol<void (*)()>(model.handle, "kiss_fft_cleanup")();
    const auto nativeDispatch = symbol<Dispatch>(native.handle, "dispatch");
    const auto modelDispatch = symbol<Dispatch>(model.handle, "dispatch");
    const auto modelFactory = symbol<const WaveTable* (*)()>(model.handle, "vl_three_osc_factory_tables");
    auto** nativeFactory = symbol<WaveTable**>(native.handle, "globalWaveTable");
    Comparison fftPowerTwo, fftOther, factoryTables, customTables, audio;
    std::mt19937_64 random(0x334f53435441424cULL);
    std::size_t fftCases = 0, sizeCases = 0, dispatchCases = 0;
    for (int invalid : {-1, 0, (1 << 20) + 1, INT32_MAX}) {
      bool planRejected = false, fastSizeRejected = false;
      try { FFTPlan rejected(invalid, false); } catch (const std::invalid_argument&) { planRejected = true; }
      try { (void)nextFastSize(invalid); } catch (const std::invalid_argument&) { fastSizeRejected = true; }
      require(planRejected && fastSizeRejected, "FFT invalid-input containment failed");
    }
    for (int size : {1, 2, 3, 4, 5, 7, 8, 9, 10, 12, 15, 16, 17, 20, 25, 32,
                     49, 121, 143, 64, 128, 256, 512, 1024, 2048, 32768}) {
      for (bool inverse : {false, true}) {
        FFTPlan plan(size, inverse);
        std::size_t nativeBytes = 0, modelBytes = 0;
        require(nativeAllocate(size, inverse, nullptr, &nativeBytes) == nullptr &&
                    modelAllocate(size, inverse, nullptr, &modelBytes) == nullptr &&
                    nativeBytes == modelBytes, "FFT memory query ABI mismatch");
        void* nativePlan = nativeAllocate(size, inverse, nullptr, nullptr);
        void* modelPlan = modelAllocate(size, inverse, nullptr, nullptr);
        require(nativePlan != nullptr, "Native FFT plan allocation failed");
        require(modelPlan != nullptr, "Recompiled FFT plan allocation failed");
        for (int stride : {1, 2}) {
          std::vector<FourLaneComplex> input(size * stride), a(size), b(size);
          for (auto& sample : input) for (std::size_t lane = 0; lane < 4; ++lane) {
            sample.real[lane] = float(int(random() % 2048) - 1024) / 1024.0f;
            sample.imaginary[lane] = float(int(random() % 2048) - 1024) / 1024.0f;
          }
          nativeTransform(nativePlan, input.data(), a.data(), stride);
          modelTransform(modelPlan, input.data(), b.data(), stride);
          const bool powerTwo = (size & (size - 1)) == 0;
          auto& comparison = powerTwo ? fftPowerTwo : fftOther;
          const std::string context = "FFT n=" + std::to_string(size) +
              " inverse=" + std::to_string(inverse) + " stride=" + std::to_string(stride);
          for (int i = 0; i < size; ++i) for (std::size_t lane = 0; lane < 4; ++lane) {
            comparison.check(a[i].real[lane], b[i].real[lane], true, context.c_str());
            comparison.check(a[i].imaginary[lane], b[i].imaginary[lane], true, context.c_str());
          }
          ++fftCases;
          auto inplaceA = input, inplaceB = input;
          nativeTransform(nativePlan, inplaceA.data(), inplaceA.data(), stride);
          modelTransform(modelPlan, inplaceB.data(), inplaceB.data(), stride);
          require(std::memcmp(inplaceA.data(), inplaceB.data(), inplaceA.size() * sizeof(FourLaneComplex)) == 0,
                  "In-place FFT output or untouched trailing storage mismatch");
          ++fftCases;
        }
        std::free(nativePlan);
        std::free(modelPlan);
      }
    }
    for (int size = 1; size <= 10000; ++size) {
      require(nativeNextSize(size) == nextFastSize(size), "FFT next fast size mismatch"); ++sizeCases;
    }
    std::cout << "FFT checks passed: " << fftCases << " transforms; building factory mipmaps\n";
    auto* original = reinterpret_cast<OscState*>(nativeDispatch(nullptr, 0, 0));
    auto* recreated = reinterpret_cast<OscState*>(modelDispatch(nullptr, 0, 0));
    require(original && recreated, "Engine lifecycle allocation failed");
    require(original->custom.count == recreated->custom.count &&
                !original->custom.maps && !recreated->custom.maps &&
                original->waveform == recreated->waveform &&
                original->sampleRate == recreated->sampleRate &&
                original->inverseSampleRate == recreated->inverseSampleRate,
            "Defined constructor-visible state mismatch");
    const auto compareBank = [&](const WaveTable* a, const WaveTable* b, Comparison& count) {
      require(a && b && a->count == b->count, "Wave table count mismatch");
      for (int waveform = 0; waveform < a->count; ++waveform) {
        const auto* ma = a->maps[waveform]; const auto* mb = b->maps[waveform];
        require(ma->count == mb->count, "Mipmap level count mismatch");
        for (int level = 0; level < ma->count; ++level) {
          require(ma->sizes[level] == mb->sizes[level], "Mipmap sample count mismatch");
          for (int sample = 0; sample < ma->sizes[level] + 10; ++sample)
            count.check(ma->tables[level][sample], mb->tables[level][sample], true, "Generated mipmap");
        }
      }
      require(a->maps[a->count] == a->maps[a->count - 1] &&
                  a->maps[a->count + 1] == a->maps[a->count - 1] &&
                  b->maps[b->count] == b->maps[b->count - 1] &&
                  b->maps[b->count + 1] == b->maps[b->count - 1], "Wave table trailing aliases mismatch");
    };
    compareBank(*nativeFactory, modelFactory(), factoryTables);
    auto* original2 = reinterpret_cast<OscState*>(nativeDispatch(nullptr, 0, 0));
    auto* recreated2 = reinterpret_cast<OscState*>(modelDispatch(nullptr, 0, 0));
    require(original2 && recreated2, "Second concurrent engine instance failed");
    std::cout << "Factory mipmap checks passed; building custom mipmaps\n";
    std::vector<float> custom(16384);
    for (auto& value : custom) value = float(int(random() % 2048) - 1024) / 1024.0f;
    nativeDispatch(original, 3, reinterpret_cast<std::intptr_t>(custom.data()));
    modelDispatch(recreated, 3, reinterpret_cast<std::intptr_t>(custom.data()));
    compareBank(&original->custom, &recreated->custom, customTables);
    for (int replacement = 0; replacement < 2; ++replacement) {
      for (auto& value : custom) value = float(int(random() % 2048) - 1024) / 1024.0f;
      nativeDispatch(original, 3, reinterpret_cast<std::intptr_t>(custom.data()));
      modelDispatch(recreated, 3, reinterpret_cast<std::intptr_t>(custom.data()));
      compareBank(&original->custom, &recreated->custom, customTables);
    }
    for (int rate : {8000, 44100, 48000, 96000, 192000}) {
      nativeDispatch(original, 2, rate); modelDispatch(recreated, 2, rate);
      require(original->sampleRate == recreated->sampleRate &&
                  original->inverseSampleRate == recreated->inverseSampleRate, "Engine rate dispatch mismatch");
      for (int opcode : {10, 11, 12}) for (int waveform = 0; waveform <= 6; ++waveform) {
        for (int pass = 0; pass < 12; ++pass) {
          const std::uint32_t frames = 257;
          std::vector<float> a(frames * 2 + 2), b;
          for (auto& value : a) value = float(int(random() % 1024) - 512) / 512.0f;
          b = a;
          RenderArguments ra{waveform, a.data(), frames, static_cast<std::uint32_t>(random()),
                             pass % 2 ? static_cast<std::uint32_t>(random())
                                      : static_cast<std::uint32_t>(1 + random() % 2000000), 0.7f};
          RenderArguments rb = ra; rb.interleaved = b.data();
          const auto pa = nativeDispatch(original, opcode, reinterpret_cast<std::intptr_t>(&ra));
          const auto pb = modelDispatch(recreated, opcode, reinterpret_cast<std::intptr_t>(&rb));
          require(pa == pb, "Engine render phase mismatch");
          for (std::size_t i = 0; i < a.size(); ++i) audio.check(a[i], b[i], true, "Engine output");
          ++dispatchCases;
        }
      }
    }
    // Two live instances share the global RNG. Calls must affect that shared
    // sequence in the same order, while each oscillator keeps its own state.
    const auto interleavedRender = [&](OscState* na, OscState* nb, OscState* ma, OscState* mb) {
      for (int pass = 0; pass < 20; ++pass) {
        OscState* aState = pass % 2 ? na : nb;
        OscState* bState = pass % 2 ? ma : mb;
        std::vector<float> a(194, 0.25f), b = a;
        RenderArguments ra{pass % 3 == 0 ? 5 : 1, a.data(), 96,
                           static_cast<std::uint32_t>(random()), 7600000, 0.37f};
        RenderArguments rb = ra; rb.interleaved = b.data();
        require(nativeDispatch(aState, 10, reinterpret_cast<std::intptr_t>(&ra)) ==
                    modelDispatch(bState, 10, reinterpret_cast<std::intptr_t>(&rb)),
                "Shared-lifetime render phase mismatch");
        for (std::size_t i = 0; i < a.size(); ++i) audio.check(a[i], b[i], true, "Shared-instance output");
        ++dispatchCases;
      }
    };
    interleavedRender(original, original2, recreated, recreated2);
    nativeDispatch(original, 1, 0); modelDispatch(recreated, 1, 0);
    require(modelFactory() != nullptr, "Factory released while another instance remains live");
    interleavedRender(original2, original2, recreated2, recreated2);
    nativeDispatch(original2, 1, 0); modelDispatch(recreated2, 1, 0);
    require(modelFactory() == nullptr, "Recompiled engine did not release factory maps");
    original = reinterpret_cast<OscState*>(nativeDispatch(nullptr, 0, 0));
    recreated = reinterpret_cast<OscState*>(modelDispatch(nullptr, 0, 0));
    require(original && recreated, "Engine recreation after final teardown failed");
    compareBank(*nativeFactory, modelFactory(), factoryTables);
    interleavedRender(original, original, recreated, recreated);
    for (int opcode : {-1, 4, 5, 6, 7, 8, 9, 13, INT32_MAX})
      require(nativeDispatch(original, opcode, 0) == modelDispatch(recreated, opcode, 0),
              "Unsupported opcode return mismatch");
    nativeDispatch(original, 3, 0); modelDispatch(recreated, 3, 0);
    nativeDispatch(original, 1, 0); modelDispatch(recreated, 1, 0);
    std::ostringstream report;
    report << "{\n  \"status\": \"passed\",\n  \"architecture\": \"arm64\",\n"
           << "  \"source_sha256\": \"d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f\",\n"
           << "  \"fft_transform_cases\": " << fftCases << ",\n"
           << "  \"fft_fast_size_cases\": " << sizeCases << ",\n"
           << "  \"power_two_fft_values\": " << fftPowerTwo.values << ",\n"
           << "  \"power_two_fft_bit_differences\": " << fftPowerTwo.unequal << ",\n"
           << "  \"other_fft_values\": " << fftOther.values << ",\n"
           << "  \"other_fft_bit_differences\": " << fftOther.unequal << ",\n"
           << "  \"other_fft_maximum_error\": " << fftOther.maximumError << ",\n"
           << "  \"factory_mipmap_values\": " << factoryTables.values << ",\n"
           << "  \"custom_mipmap_values\": " << customTables.values << ",\n"
           << "  \"render_dispatch_cases\": " << dispatchCases << ",\n"
           << "  \"render_output_values\": " << audio.values << ",\n"
           << "  \"full_plugin_equivalence\": false,\n"
           << "  \"native_small_dsp_engine_loaded\": true,\n"
           << "  \"fl_studio_host_or_ui_loaded\": false,\n"
           << "  \"limitations\": [\"Small engine only; Fruity plugin wrapper, UI, presets, automation, host integration and VST/AU formats remain unreconstructed. Defensive invalid-input handling and lifecycle allocation layouts differ. Valid serialized command usage only; per-export ABI tests are recorded separately.\"]\n}\n";
    std::ofstream output(argv[3]); require(output.good(), "Cannot save report");
    output << report.str(); std::cout << report.str();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; return 1;
  }
}
