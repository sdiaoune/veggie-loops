#include "three_osc_tables.hpp"

#include <memory>
#include <cstdlib>
#include <cstring>
#include <unordered_map>

using namespace veggie_loops::three_osc;
struct alignas(16) NoiseGlobals {
  float* values;
  std::uint32_t seed;
  std::uint32_t reserved;
};
extern "C" {
alignas(16) float p[11] = {0, 0.1f, 0.2f, 0.3f, 0.4f, 0.5f,
                          0.6f, 0.7f, 0.8f, 0.9f, 1.0f};
NoiseGlobals p2{p, 0x1099eu, 0};
WaveTable* globalWaveTable = nullptr;
}

namespace {
using namespace veggie_loops::three_osc;
struct Instance {
  std::unique_ptr<OwnedWaveTable> custom;
};
std::unordered_map<OscState*, std::unique_ptr<Instance>> instances;
std::unique_ptr<OwnedWaveTable> factory;
Runtime runtime{nullptr, 0x1099eu};

void initialize(OscState* state) {
  if (instances.empty()) {
    const auto waves = factoryWaveforms();
    factory = std::make_unique<OwnedWaveTable>(waves.data(), 2048, 4);
    runtime.factory = factory->view();
    globalWaveTable = runtime.factory;
  }
  state->custom.count = 0; state->custom.maps = nullptr;
  state->waveform = 0; setSampleRate(*state, 44100);
  instances.emplace(state, std::make_unique<Instance>());
}
void destroy(OscState* state) {
  if (instances.size() == 1) factory.reset();
  instances.erase(state);
  state->custom.count = 0; state->custom.maps = nullptr;
  if (instances.empty()) {
    runtime.factory = nullptr; globalWaveTable = nullptr;
  }
}
void setCustom(OscState* state, const float* waveform, int length) {
  const auto reduced = downsampleCustom(waveform, length);
  auto replacement = std::make_unique<OwnedWaveTable>(reduced.data(), 2048, 1);
  state->custom = *replacement->view();
  instances.at(state)->custom = std::move(replacement);
}
}

// Compatible with the observed small DSP-engine command boundary. This is
// not the FL Studio Fruity plugin factory, a VST entrypoint or an AU factory.
// Call serially, as required by the observed shared RNG/lifecycle globals.
extern "C" std::uintptr_t dispatch(OscState* state, std::int32_t command,
                                   std::intptr_t parameter) {
  try {
    if (command == 0) {
      auto* result = new OscState;
      try { initialize(result); } catch (...) { delete result; throw; }
      return reinterpret_cast<std::uintptr_t>(result);
    }
    const auto found = instances.find(state);
    if (command == 1) {
      if (found != instances.end()) { destroy(state); delete state; }
      return 0;
    }
    if (found == instances.end()) return 0;
    if (command == 2) {
      setSampleRate(*state, static_cast<double>(parameter));
      return 0;
    }
    if (command == 3) {
      if (parameter != 0) {
        setCustom(state, reinterpret_cast<const float*>(parameter), 16384);
      }
      return 0;
    }
    if (command >= 10 && command <= 12 && parameter != 0) {
      runtime.noiseSeed = p2.seed;
      const auto phase = dispatchRender(*state, runtime, command,
                                         *reinterpret_cast<const RenderArguments*>(parameter));
      p2.seed = runtime.noiseSeed;
      return phase;
    }
    return 0;
  } catch (...) {
    // Defensive failure containment is an intentional difference for invalid
    // input/allocation failure; equivalence claims cover successful valid use.
    return 0;
  }
}

extern "C" const WaveTable* vl_three_osc_factory_tables() {
  return runtime.factory;
}

namespace {
struct RawFFTPlan {
  std::int32_t size;
  std::int32_t inverse;
  std::array<std::int32_t, 64> factors;
  alignas(16) FourLaneComplex twiddles[1];
};
static_assert(offsetof(RawFFTPlan, twiddles) == 0x110);
struct FilterABI {
  std::array<std::int32_t, 4> previous;
  std::int32_t size;
  std::int32_t reserved;
  FourLaneComplex* temporary;
  FourLaneComplex* spectrum;
  RawFFTPlan* forward;
  RawFFTPlan* inverse;
};
static_assert(sizeof(FilterABI) == 56);
struct GeneratorABI { std::int32_t levelsPerOctave, oversampling; };

void* alignedAllocate(std::size_t bytes, std::size_t alignment) {
  void* result = nullptr;
  return posix_memalign(&result, alignment, bytes) == 0 ? result : nullptr;
}
void clearMip(MipMap* map) {
  for (int i = 0; i < map->count; ++i) std::free(map->tables[i]);
  std::free(map->tables); std::free(map->sizes);
  map->count = 0; map->tables = nullptr; map->sizes = nullptr;
}
void initializeWave(WaveTable* wave, int count) {
  if (wave->maps) {
    for (int i = 0; i < wave->count; ++i) {
      if (wave->maps[i]) { clearMip(wave->maps[i]); delete wave->maps[i]; }
    }
    std::free(wave->maps);
  }
  wave->count = count; wave->maps = nullptr;
  if (count > 0) {
    if (count > 4) throw std::invalid_argument("Unverified wave table count");
    wave->maps = static_cast<MipMap**>(std::malloc(static_cast<std::size_t>(count + 2) * 8));
    if (!wave->maps) throw std::bad_alloc();
    for (int i = 0; i < count; ++i) wave->maps[i] = new MipMap;
    wave->maps[count] = wave->maps[count + 1] = wave->maps[count - 1];
  }
}
void copyMip(MipMap* destination, const MipMap* source) {
  destination->count = source->count;
  destination->tables = static_cast<float**>(std::calloc(source->count, sizeof(float*)));
  destination->sizes = static_cast<std::int32_t*>(std::calloc(source->count, sizeof(std::int32_t)));
  if (!destination->tables || !destination->sizes) throw std::bad_alloc();
  for (int level = 0; level < source->count; ++level) {
    destination->sizes[level] = source->sizes[level];
    const auto bytes = static_cast<std::size_t>(source->sizes[level] + 10) * sizeof(float);
    destination->tables[level] = static_cast<float*>(alignedAllocate(bytes, 16));
    if (!destination->tables[level]) throw std::bad_alloc();
    std::memcpy(destination->tables[level], source->tables[level], bytes);
  }
}
}

// The names below reproduce the installed engine's exported C/Itanium ABI
// boundary. They are forwarding wrappers around independently written source.
// Error/invalid-input behavior and original allocator implementation details
// are not claimed equivalent. Native exception personality thunks are replaced
// by the compiler's own generated exception machinery.
extern "C" {
double log2(double value) { return binaryLog(value); }
void* _Z17d1_aligned_mallocmm(std::size_t bytes, std::size_t) {
  // The reviewed export is a direct malloc thunk; its name does not imply
  // that the second argument is honored on this macOS build.
  return std::malloc(bytes);
}
void _Z15d1_aligned_freePv(void* value) { std::free(value); }

void* kiss_fft_alloc(int size, int inverse, void* memory, std::size_t* available) {
  if (size < 1 || size > (1 << 20)) return nullptr;
  const auto needed = std::size_t(0x110) + static_cast<std::size_t>(size) * sizeof(FourLaneComplex);
  RawFFTPlan* result;
  if (available) {
    result = memory && *available >= needed ? static_cast<RawFFTPlan*>(memory) : nullptr;
    *available = needed;
  } else result = static_cast<RawFFTPlan*>(alignedAllocate(needed, 16));
  if (!result) return nullptr;
  FFTPlan plan(size, inverse != 0);
  result->size = size; result->inverse = inverse;
  std::size_t i = 0;
  for (const auto& factor : plan.factors()) {
    result->factors[i++] = factor[0]; result->factors[i++] = factor[1];
  }
  std::memcpy(result->twiddles, plan.twiddles().data(), static_cast<std::size_t>(size) * sizeof(FourLaneComplex));
  return result;
}
void kiss_fft_stride(RawFFTPlan* raw, const FourLaneComplex* input,
                     FourLaneComplex* output, int stride) {
  FFTPlan(raw->size, raw->inverse != 0).transform(input, output, stride);
}
void kiss_fft(RawFFTPlan* raw, const FourLaneComplex* input, FourLaneComplex* output) {
  kiss_fft_stride(raw, input, output, 1);
}
void kiss_fft_cleanup() {}
int kiss_fft_next_fast_size(int size) { return nextFastSize(size); }

void _ZN9WaveTableC1Ev(WaveTable* value) { value->count = 0; value->maps = nullptr; }
void _ZN9WaveTableC2Ev(WaveTable* value) { _ZN9WaveTableC1Ev(value); }
void _ZN9WaveTable4initEi(WaveTable* value, int count) { initializeWave(value, count); }
WaveTable* _ZN9WaveTableD1Ev(WaveTable* value) { initializeWave(value, 0); return value; }
WaveTable* _ZN9WaveTableD2Ev(WaveTable* value) { return _ZN9WaveTableD1Ev(value); }
void _ZN6MipMapC1Ev(MipMap* value) {
  value->count = 0; value->tables = nullptr; value->sizes = nullptr;
}
void _ZN6MipMapC2Ev(MipMap* value) { _ZN6MipMapC1Ev(value); }
void _ZN6MipMap5clearEv(MipMap* value) { clearMip(value); }
MipMap* _ZN6MipMapD1Ev(MipMap* value) { clearMip(value); return value; }
MipMap* _ZN6MipMapD2Ev(MipMap* value) { return _ZN6MipMapD1Ev(value); }
void _ZN15MipMapGeneratorC1Eii(GeneratorABI* value, int levels, int oversampling) {
  value->levelsPerOctave = levels; value->oversampling = oversampling;
}
void _ZN15MipMapGeneratorC2Eii(GeneratorABI* value, int levels, int oversampling) {
  _ZN15MipMapGeneratorC1Eii(value, levels, oversampling);
}
void _ZN15MipMapGeneratorD1Ev(GeneratorABI*) {}
void _ZN15MipMapGeneratorD2Ev(GeneratorABI*) {}
void _ZN15MipMapGenerator23createMipMapForWaveformER6MipMapPKfib(
    GeneratorABI* generator, MipMap* map, const float* input, int size, bool) {
  // The native creator overwrites allocation pointers. Its destination must
  // be freshly constructed or cleared; rebuilding a WaveTable clears first.
  OwnedMipMap temporary(input, size, generator->levelsPerOctave, generator->oversampling);
  copyMip(map, temporary.view());
}
void _ZN15MipMapGenerator27createWaveTableForWaveformsER9WaveTablePfiib(
    GeneratorABI* generator, WaveTable* table, const float* input, int size, int count, bool flag) {
  initializeWave(table, count);
  for (int i = 0; i < count; ++i)
    _ZN15MipMapGenerator23createMipMapForWaveformER6MipMapPKfib(
        generator, table->maps[i], input + i * size, size, flag);
}

FilterABI* _ZN17KissFFTFilterSIMDC1Ei(FilterABI* value, int size) {
  if (size < 1 || size > (1 << 20)) throw std::invalid_argument("FFT filter size out of bounds");
  value->previous.fill(size / 2); value->size = size;
  value->forward = static_cast<RawFFTPlan*>(kiss_fft_alloc(size, 0, nullptr, nullptr));
  value->inverse = static_cast<RawFFTPlan*>(kiss_fft_alloc(size, 1, nullptr, nullptr));
  const auto bytes = static_cast<std::size_t>(size + 6) * sizeof(FourLaneComplex);
  value->temporary = static_cast<FourLaneComplex*>(alignedAllocate(bytes, 16));
  value->spectrum = static_cast<FourLaneComplex*>(alignedAllocate(bytes, 16));
  if (!value->forward || !value->inverse || !value->temporary || !value->spectrum) throw std::bad_alloc();
  return value;
}
FilterABI* _ZN17KissFFTFilterSIMDC2Ei(FilterABI* value, int size) {
  return _ZN17KissFFTFilterSIMDC1Ei(value, size);
}
FilterABI* _ZN17KissFFTFilterSIMDD1Ev(FilterABI* value) {
  std::free(value->forward); std::free(value->inverse);
  std::free(value->temporary); std::free(value->spectrum); return value;
}
FilterABI* _ZN17KissFFTFilterSIMDD2Ev(FilterABI* value) { return _ZN17KissFFTFilterSIMDD1Ev(value); }
void _ZN17KissFFTFilterSIMD7prepareEP19__simd128_float32_t(
    FilterABI* value, const std::array<float, 4>* input) {
  value->previous.fill(value->size / 2);
  for (int i = 0; i < value->size; ++i) {
    value->temporary[i].real = input[i]; value->temporary[i].imaginary.fill(0);
  }
  kiss_fft(value->forward, value->temporary, value->spectrum);
}
void _ZN17KissFFTFilterSIMD6filterEP19__simd128_float32_tPi(
    FilterABI* value, std::array<float, 4>* output, const int* cutoffs) {
  for (std::size_t lane = 0; lane < 4; ++lane) {
    for (int j = cutoffs[lane]; j < value->previous[lane]; ++j) {
      value->spectrum[j + 1].real[lane] = value->spectrum[j + 1].imaginary[lane] = 0;
      value->spectrum[value->size - j - 1].real[lane] = value->spectrum[value->size - j - 1].imaginary[lane] = 0;
    }
    value->previous[lane] = cutoffs[lane];
  }
  kiss_fft(value->inverse, value->spectrum, value->temporary);
  const float scale = 1.0f / static_cast<float>(value->size);
  for (int i = 0; i < value->size; ++i)
    for (std::size_t lane = 0; lane < 4; ++lane) output[i][lane] = value->temporary[i].real[lane] * scale;
}

OscState* _ZN3OscC1Ev(OscState* value) { initialize(value); return value; }
OscState* _ZN3OscC2Ev(OscState* value) { return _ZN3OscC1Ev(value); }
OscState* _ZN3OscD1Ev(OscState* value) { destroy(value); return value; }
OscState* _ZN3OscD2Ev(OscState* value) { return _ZN3OscD1Ev(value); }
void _ZN3Osc13setSampleRateEd(OscState* value, double rate) { setSampleRate(*value, rate); }
void _ZN3Osc13setCustomWaveEPfi(OscState* value, const float* input, int size) { setCustom(value, input, size); }
double _ZN3Osc15phaseAddToPitchEd(OscState* value, double increment) { return phaseAddToPitch(*value, increment); }
void _ZN3Osc15selectWaveTableEdb(OscState* value, double pitch, bool custom) {
  selectWaveTable(*value, pitch, custom, custom ? value->custom : *globalWaveTable);
}
float _ZN3Osc20processWaveInternal2Ef(OscState* value, float phase) { return processWave(*value, phase); }
std::uint32_t _ZN3Osc6addOscEiPfjfjjb(OscState* value, int waveform, float* buffer,
                                   std::uint32_t frames, float gain,
                                   std::uint32_t phase, std::uint32_t increment, bool ring) {
  runtime.noiseSeed = p2.seed;
  const auto result = addOsc(*value, runtime, waveform, buffer, frames, gain, phase, increment, ring);
  p2.seed = runtime.noiseSeed; return result;
}
void _Z16destroyWaveTablev() {
  factory.reset(); runtime.factory = nullptr; globalWaveTable = nullptr;
}
}
