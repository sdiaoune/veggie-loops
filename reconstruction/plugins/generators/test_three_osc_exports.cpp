#include "three_osc_tables.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>

using namespace veggie_loops::three_osc;
namespace {
void require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
std::string hash(const char* path) {
  std::ifstream stream(path, std::ios::binary);
  require(stream.good(), "Cannot read installed DSP engine");
  std::vector<char> input{std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
  std::array<unsigned char, 32> digest;
  CC_SHA256(input.data(), static_cast<CC_LONG>(input.size()), digest.data());
  std::ostringstream output;
  for (auto byte : digest) output << std::hex << std::setfill('0') << std::setw(2) << unsigned(byte);
  return output.str();
}
template <typename T> T sym(void* library, const char* name) {
  const auto value = dlsym(library, name); require(value != nullptr, name);
  return reinterpret_cast<T>(value);
}
struct Library {
  void* handle;
  explicit Library(const char* path) : handle(dlopen(path, RTLD_NOW | RTLD_LOCAL)) {
    require(handle != nullptr, "Cannot load library");
  }
  ~Library() { if (handle) dlclose(handle); }
};
struct GeneratorABI { int levels, oversampling; };
struct FilterABI {
  std::array<int, 4> previous;
  int size, reserved;
  FourLaneComplex* temporary;
  FourLaneComplex* spectrum;
  void* forward;
  void* inverse;
};
static_assert(sizeof(FilterABI) == 56);
std::size_t values = 0;
void compareMip(const MipMap& a, const MipMap& b) {
  require(a.count == b.count, "Public mipmap count mismatch");
  for (int level = 0; level < a.count; ++level) {
    require(a.sizes[level] == b.sizes[level], "Public mipmap length mismatch");
    const auto length = static_cast<std::size_t>(a.sizes[level] + 10);
    require(std::memcmp(a.tables[level], b.tables[level], length * sizeof(float)) == 0,
            "Public mipmap payload mismatch");
    values += length;
  }
}
}

int main(int argc, char** argv) {
  try {
    require(argc == 4, "Usage: test_three_osc_exports <installed engine> <recompiled engine> <report.json>");
    require(hash(argv[1]) == "d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f",
            "Installed DSP identity mismatch");
    Library native(argv[1]), model(argv[2]);
    std::mt19937 random(0x334f5343);
    std::size_t constructors = 0, generations = 0, filters = 0, methods = 0;
    using BinaryLog = double (*)(double);
    for (double input : {0.0, -0.0, 1.0, -1.0, 2.0, 8.176, 0.0005,
                         32768.0, std::numeric_limits<double>::infinity()}) {
      const double a = sym<BinaryLog>(native.handle, "log2")(input);
      const double b = sym<BinaryLog>(model.handle, "log2")(input);
      require(std::memcmp(&a, &b, sizeof(double)) == 0, "Exported log2 numeric mismatch");
    }
    using Allocate = void* (*)(std::size_t, std::size_t);
    using Release = void (*)(void*);
    for (std::size_t size : {1, 16, 31, 1024}) for (std::size_t alignment : {16, 32, 64}) {
      auto* a = sym<Allocate>(native.handle, "_Z17d1_aligned_mallocmm")(size, alignment);
      auto* b = sym<Allocate>(model.handle, "_Z17d1_aligned_mallocmm")(size, alignment);
      require(a && b && reinterpret_cast<std::uintptr_t>(a) % 16 == 0 &&
                  reinterpret_cast<std::uintptr_t>(b) % 16 == 0, "Malloc thunk ABI mismatch");
      sym<Release>(native.handle, "_Z15d1_aligned_freePv")(a);
      sym<Release>(model.handle, "_Z15d1_aligned_freePv")(b);
    }
    using GeneratorCtor = void (*)(GeneratorABI*, int, int);
    using GeneratorDtor = void (*)(GeneratorABI*);
    using MipCtor = void (*)(MipMap*);
    using MipDtor = MipMap* (*)(MipMap*);
    using WaveCtor = void (*)(WaveTable*);
    using WaveDtor = WaveTable* (*)(WaveTable*);
    using WaveInit = void (*)(WaveTable*, int);
    using MakeMip = void (*)(GeneratorABI*, MipMap*, const float*, int, bool);
    using MakeWave = void (*)(GeneratorABI*, WaveTable*, const float*, int, int, bool);
    for (int alias : {1, 2}) {
      const std::string gctor = "_ZN15MipMapGeneratorC" + std::to_string(alias) + "Eii";
      const std::string gdtor = "_ZN15MipMapGeneratorD" + std::to_string(alias) + "Ev";
      const std::string mctor = "_ZN6MipMapC" + std::to_string(alias) + "Ev";
      const std::string mdtor = "_ZN6MipMapD" + std::to_string(alias) + "Ev";
      const std::string wctor = "_ZN9WaveTableC" + std::to_string(alias) + "Ev";
      const std::string wdtor = "_ZN9WaveTableD" + std::to_string(alias) + "Ev";
      const auto gcA = sym<GeneratorCtor>(native.handle, gctor.c_str());
      const auto gcB = sym<GeneratorCtor>(model.handle, gctor.c_str());
      const auto gdA = sym<GeneratorDtor>(native.handle, gdtor.c_str());
      const auto gdB = sym<GeneratorDtor>(model.handle, gdtor.c_str());
      const auto mcA = sym<MipCtor>(native.handle, mctor.c_str());
      const auto mcB = sym<MipCtor>(model.handle, mctor.c_str());
      const auto mdA = sym<MipDtor>(native.handle, mdtor.c_str());
      const auto mdB = sym<MipDtor>(model.handle, mdtor.c_str());
      const auto wcA = sym<WaveCtor>(native.handle, wctor.c_str());
      const auto wcB = sym<WaveCtor>(model.handle, wctor.c_str());
      const auto wdA = sym<WaveDtor>(native.handle, wdtor.c_str());
      const auto wdB = sym<WaveDtor>(model.handle, wdtor.c_str());
      const auto initA = sym<WaveInit>(native.handle, "_ZN9WaveTable4initEi");
      const auto initB = sym<WaveInit>(model.handle, "_ZN9WaveTable4initEi");
      const auto makeA = sym<MakeMip>(native.handle, "_ZN15MipMapGenerator23createMipMapForWaveformER6MipMapPKfib");
      const auto makeB = sym<MakeMip>(model.handle, "_ZN15MipMapGenerator23createMipMapForWaveformER6MipMapPKfib");
      const auto bankA = sym<MakeWave>(native.handle, "_ZN15MipMapGenerator27createWaveTableForWaveformsER9WaveTablePfiib");
      const auto bankB = sym<MakeWave>(model.handle, "_ZN15MipMapGenerator27createWaveTableForWaveformsER9WaveTablePfiib");
      for (auto config : {std::array<int, 3>{16, 4, 16}, {32, 8, 4}, {64, 4, 8}}) {
        const auto [length, levels, oversampling] = config;
        std::vector<float> input(length * 4);
        for (auto& value : input) value = float(int(random() % 2048) - 1024) / 1024.0f;
        GeneratorABI ga, gb; gcA(&ga, levels, oversampling); gcB(&gb, levels, oversampling);
        require(ga.levels == gb.levels && ga.oversampling == gb.oversampling, "Generator constructor mismatch");
        MipMap ma, mb; mcA(&ma); mcB(&mb);
        require(ma.count == mb.count && !ma.tables && !mb.tables && !ma.sizes && !mb.sizes,
                "Mipmap constructor mismatch");
        makeA(&ga, &ma, input.data(), length, true); makeB(&gb, &mb, input.data(), length, true);
        compareMip(ma, mb); ++generations;
        mdA(&ma); mdB(&mb);
        require(!ma.count && !mb.count && !ma.tables && !mb.tables && !ma.sizes && !mb.sizes,
                "Mipmap destructor did not clear observed state");
        WaveTable wa, wb; wcA(&wa); wcB(&wb);
        for (int count : {1, 4, 2, 0}) {
          initA(&wa, count); initB(&wb, count);
          require(wa.count == wb.count && bool(wa.maps) == bool(wb.maps), "WaveTable init mismatch");
        }
        bankA(&ga, &wa, input.data(), length, 4, true);
        bankB(&gb, &wb, input.data(), length, 4, true);
        for (int i = 0; i < 4; ++i) compareMip(*wa.maps[i], *wb.maps[i]);
        ++generations; wdA(&wa); wdB(&wb);
        require(!wa.count && !wb.count && !wa.maps && !wb.maps, "WaveTable destructor mismatch");
        gdA(&ga); gdB(&gb); constructors += 3;
      }
    }
    using FilterCtor = FilterABI* (*)(FilterABI*, int);
    using FilterDtor = FilterABI* (*)(FilterABI*);
    using Prepare = void (*)(FilterABI*, const std::array<float, 4>*);
    using Filter = void (*)(FilterABI*, std::array<float, 4>*, const int*);
    for (int alias : {1, 2}) {
      const std::string ctor = "_ZN17KissFFTFilterSIMDC" + std::to_string(alias) + "Ei";
      const std::string dtor = "_ZN17KissFFTFilterSIMDD" + std::to_string(alias) + "Ev";
      for (int size : {16, 32, 64, 128}) {
        FilterABI a, b;
        sym<FilterCtor>(native.handle, ctor.c_str())(&a, size);
        sym<FilterCtor>(model.handle, ctor.c_str())(&b, size);
        std::vector<std::array<float, 4>> input(size), outA(size), outB(size);
        for (auto& sample : input) for (auto& value : sample) value = float(int(random() % 2048) - 1024) / 1024.0f;
        const auto pa = sym<Prepare>(native.handle, "_ZN17KissFFTFilterSIMD7prepareEP19__simd128_float32_t");
        const auto pb = sym<Prepare>(model.handle, "_ZN17KissFFTFilterSIMD7prepareEP19__simd128_float32_t");
        for (int reset = 0; reset < 2; ++reset) {
          pa(&a, input.data()); pb(&b, input.data());
          require(a.previous == b.previous && std::memcmp(a.spectrum, b.spectrum, size * sizeof(FourLaneComplex)) == 0,
                  "Filter prepare state mismatch");
          for (int pass = 0; pass < 4; ++pass) {
            std::array<int, 4> cutoff{size / (2 + pass), size / (3 + pass), size / (4 + pass), size / (5 + pass)};
            sym<Filter>(native.handle, "_ZN17KissFFTFilterSIMD6filterEP19__simd128_float32_tPi")(&a, outA.data(), cutoff.data());
            sym<Filter>(model.handle, "_ZN17KissFFTFilterSIMD6filterEP19__simd128_float32_tPi")(&b, outB.data(), cutoff.data());
            require(a.previous == b.previous && std::memcmp(outA.data(), outB.data(), size * sizeof(outA[0])) == 0 &&
                        std::memcmp(a.spectrum, b.spectrum, size * sizeof(FourLaneComplex)) == 0,
                    "Filter result or retained spectrum mismatch");
            values += size * 4; ++filters;
          }
        }
        sym<FilterDtor>(native.handle, dtor.c_str())(&a);
        sym<FilterDtor>(model.handle, dtor.c_str())(&b); ++constructors;
      }
    }
    using OscCtor = OscState* (*)(OscState*);
    using Rate = void (*)(OscState*, double);
    using Custom = void (*)(OscState*, const float*, int);
    using Pitch = double (*)(OscState*, double);
    using Select = void (*)(OscState*, double, bool);
    using Process = float (*)(OscState*, float);
    using Add = std::uint32_t (*)(OscState*, int, float*, std::uint32_t, float, std::uint32_t, std::uint32_t, bool);
    for (int alias : {1, 2}) {
      const std::string ctor = "_ZN3OscC" + std::to_string(alias) + "Ev";
      const std::string dtor = "_ZN3OscD" + std::to_string(alias) + "Ev";
      OscState a, b;
      sym<OscCtor>(native.handle, ctor.c_str())(&a); sym<OscCtor>(model.handle, ctor.c_str())(&b);
      std::vector<float> custom(16384);
      for (auto& value : custom) value = float(int(random() % 2048) - 1024) / 1024.0f;
      sym<Custom>(native.handle, "_ZN3Osc13setCustomWaveEPfi")(&a, custom.data(), 16384);
      sym<Custom>(model.handle, "_ZN3Osc13setCustomWaveEPfi")(&b, custom.data(), 16384);
      compareMip(*a.custom.maps[0], *b.custom.maps[0]);
      sym<Rate>(native.handle, "_ZN3Osc13setSampleRateEd")(&a, 96000);
      sym<Rate>(model.handle, "_ZN3Osc13setSampleRateEd")(&b, 96000);
      const double pitchA = sym<Pitch>(native.handle, "_ZN3Osc15phaseAddToPitchEd")(&a, 0.017);
      const double pitchB = sym<Pitch>(model.handle, "_ZN3Osc15phaseAddToPitchEd")(&b, 0.017);
      require(pitchA == pitchB, "Public pitch method mismatch");
      for (int waveform = 0; waveform <= 6; ++waveform) for (bool ring : {false, true}) {
        std::vector<float> outA(128, 0.25f), outB = outA;
        const auto ra = sym<Add>(native.handle, "_ZN3Osc6addOscEiPfjfjjb")(&a, waveform, outA.data(), 64, 0.51f, 0xabcd1234, 9937000, ring);
        const auto rb = sym<Add>(model.handle, "_ZN3Osc6addOscEiPfjfjjb")(&b, waveform, outB.data(), 64, 0.51f, 0xabcd1234, 9937000, ring);
        require(ra == rb && std::memcmp(outA.data(), outB.data(), outA.size() * sizeof(float)) == 0,
                "Public addOsc method mismatch");
        values += outA.size(); ++methods;
        if (waveform >= 1 && waveform <= 4) {
          sym<Select>(native.handle, "_ZN3Osc15selectWaveTableEdb")(&a, 4.25, false);
          sym<Select>(model.handle, "_ZN3Osc15selectWaveTableEdb")(&b, 4.25, false);
          require(a.lowerIndex == b.lowerIndex && a.upperIndex == b.upperIndex && a.lowerWeight == b.lowerWeight,
                  "Public table selection method mismatch");
          require(sym<Process>(native.handle, "_ZN3Osc20processWaveInternal2Ef")(&a, 0.49f) ==
                      sym<Process>(model.handle, "_ZN3Osc20processWaveInternal2Ef")(&b, 0.49f),
                  "Public waveform method mismatch");
        }
      }
      sym<OscCtor>(native.handle, dtor.c_str())(&a); sym<OscCtor>(model.handle, dtor.c_str())(&b);
      require(a.custom.count == b.custom.count && !a.custom.maps && !b.custom.maps,
              "Public oscillator destructor state mismatch"); ++constructors;
    }
    std::ostringstream report;
    report << "{\n  \"status\": \"passed\",\n  \"scope\": \"public small-engine class ABI with synthetic inputs\",\n"
           << "  \"constructor_destructor_fixtures\": " << constructors << ",\n"
           << "  \"generation_fixtures\": " << generations << ",\n"
           << "  \"filter_fixtures\": " << filters << ",\n"
           << "  \"oscillator_method_fixtures\": " << methods << ",\n"
           << "  \"bitwise_compared_float_values\": " << values << ",\n"
           << "  \"full_plugin_equivalence\": false,\n"
           << "  \"limitations\": [\"Valid successful inputs only; allocation failure, C++ exception personality and original allocation tracing are not reproduced. FL Studio wrapper, VST/AU/UI/presets/host integration are outside scope.\"]\n}\n";
    std::ofstream output(argv[3]); require(output.good(), "Cannot save ABI report");
    output << report.str(); std::cout << report.str(); return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
