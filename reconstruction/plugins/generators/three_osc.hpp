#pragma once

// Original source reconstructed from the reviewed arm64 3x Osc engine routines.
// This header defines the bounded inline DSP routines. three_osc_tables.hpp
// and three_osc_engine.cpp add FFT/mipmap generation and the small-engine ABI.
// The separate Fruity wrapper, GUI, presets and VST/AU/host integration are absent.

#include <cmath>
#include <bit>
#include <cstddef>
#include <cstdint>

namespace veggie_loops::three_osc {

struct MipMap {
  std::int32_t count = 0;
  std::int32_t reserved = 0;
  float** tables = nullptr;
  std::int32_t* sizes = nullptr;
};

struct WaveTable {
  std::int32_t count = 0;
  std::int32_t reserved = 0;
  MipMap** maps = nullptr;
};

struct OscState {
  WaveTable custom;
  double phaseIncrement = 0;
  std::int32_t waveform = 0;
  float lowerWeight = 1;
  std::int32_t lowerIndex = 0;
  std::int32_t upperIndex = 1;
  float* lowerTable = nullptr;
  float* upperTable = nullptr;
  double sampleRate = 44100;
  double inverseSampleRate = 1.0 / 44100.0;
};

static_assert(sizeof(MipMap) == 24 && sizeof(WaveTable) == 16);
static_assert(sizeof(OscState) == 72);
static_assert(offsetof(OscState, phaseIncrement) == 0x10);
static_assert(offsetof(OscState, waveform) == 0x18);
static_assert(offsetof(OscState, lowerTable) == 0x28);
static_assert(offsetof(OscState, sampleRate) == 0x38);

struct Runtime {
  WaveTable* factory = nullptr;
  std::uint32_t noiseSeed = 0;
};

inline void setSampleRate(OscState& state, double rate) {
  state.sampleRate = rate;
  state.inverseSampleRate = 1.0 / rate;
}

// The observed implementation calls log10 and divides by log10(2), rather
// than calling the platform log2 implementation. Preserve that rounding.
inline double binaryLog(double value) {
  return std::log10(value) / 0.3010299956639812;
}

inline double phaseAddToPitch(const OscState& state, double increment) {
  return binaryLog(increment / (state.inverseSampleRate * 8.176));
}

// Preconditions match the native routine: the selected map has >=2 tables;
// pitch is finite or +/-infinity, excluding NaN; waveform is 1..4 unless using
// the custom map. Zero increment yields -infinite pitch and selects level 0.
// Tables and
// pointers are caller-owned. No shipped waveform data is embedded here.
inline void selectWaveTable(OscState& state, double pitch, bool custom,
                            const WaveTable& factory) {
  const MipMap& map = *(custom ? state.custom.maps[0]
                              : factory.maps[state.waveform - 1]);
  const float requested = static_cast<float>(std::fma(pitch, 4.0, -5.0));
  const float maximum = static_cast<float>(map.count) - 2.0f;
  const float limited = maximum < requested ? maximum : requested;
  const float selected = requested < 0.0f ? 0.0f : limited;
  state.lowerIndex = static_cast<std::int32_t>(selected);
  state.upperIndex = state.lowerIndex + 1;
  state.lowerWeight = (static_cast<float>(state.lowerIndex) - selected) + 1.0f;
  state.lowerTable = map.tables[state.lowerIndex];
  state.upperTable = map.tables[state.upperIndex];
}

// Phase normally lies in [0,1). In the lookup branch the caller must provide
// 32770 readable floats (32768 samples and two wrap samples) in lowerTable.
// Converting a UInt32 phase to float can round its maximum value to 1.0.
// The observed routine does not blend upperTable or lowerWeight.
inline float processWave(const OscState& state, float phase) {
  if (!(state.phaseIncrement < 0.0005)) {
    const float scaled = phase * 2048.0f;
    const float position = scaled * 16.0f;
    const auto index = static_cast<std::int32_t>(position);
    const float fraction = static_cast<float>(
        static_cast<double>(position) - static_cast<double>(index));
    return std::fma(state.lowerTable[index], 1.0f - fraction,
                    state.lowerTable[index + 1] * fraction);
  }
  switch (state.waveform) {
    case 1:
      if (phase < 0.25f) return phase * 4.0f;
      if (phase < 0.75f) return std::fma(phase - 0.25f, -4.0f, 1.0f);
      return std::fma(phase - 0.75f, 4.0f, -1.0f);
    case 2:
      return phase < 0.5f ? 1.0f : -1.0f;
    case 3:
      return -std::fma(phase, -2.0f, 1.0f);
    case 4:
      if (static_cast<double>(phase) >= 0.8333333333333334) return -1.0f;
      if (phase >= 0.4638671875f) return 1.0f;
      return static_cast<float>(std::fma(
          1.0 - std::pow(0.997, (static_cast<double>(phase) / 0.4638671875) * 7600.0),
          2.0, -1.0));
    default:
      return 0.0f;
  }
}

inline float accumulate(float previous, float wave, float gain, bool ring) {
  const float multiplier = ring ? -previous : 1.0f;
  const float modulation = wave * multiplier;
  return std::fma(modulation, gain, previous);
}

// Low-level preconditions: waveform is 0..6, gain is finite, sampleRate is
// positive/finite for table-based waveforms, and frames <= 2^20. A nonzero
// frames value requires 2*frames writable floats. The integer increment may
// be zero. The component intentionally preserves native low-level arithmetic;
// validation belongs at the caller/engine-command boundary.
// Updates a single lane of an interleaved buffer at 0,2,4,...; untouched lane
// samples remain unchanged. Unsigned phase arithmetic wraps at 2^32. For
// waveforms 1..4, runtime.factory must point to valid generated factory maps;
// waveform 6 requires state.custom maps and does not require a factory bank.
inline std::uint32_t addOsc(OscState& state, Runtime& runtime,
                            std::int32_t waveform, float* interleaved,
                            std::uint32_t frames, float gain,
                            std::uint32_t phase, std::uint32_t increment,
                            bool ring) {
  constexpr double phaseScale = 0x1p-32;
  if (waveform != 0 && waveform != 5) {
    state.phaseIncrement = phaseScale * static_cast<double>(increment);
    const double pitch = phaseAddToPitch(state, state.phaseIncrement);
    state.waveform = waveform;
    if (waveform == 6) selectWaveTable(state, pitch, true, state.custom);
    else selectWaveTable(state, pitch, false, *runtime.factory);
  }
  for (std::uint32_t frame = 0; frame < frames; ++frame) {
    float wave;
    if (waveform == 5) {
      runtime.noiseSeed = runtime.noiseSeed * 0x0bb38435u + 0x3619636bu;
      const std::int32_t signedSeed = std::bit_cast<std::int32_t>(runtime.noiseSeed);
      wave = static_cast<float>(signedSeed) * 0x1p-31f;
    } else {
      const float position = static_cast<float>(phaseScale * static_cast<double>(phase));
      wave = waveform == 0 ? std::sin(position * 6.283185482025146484375f)
                           : processWave(state, position);
    }
    interleaved[static_cast<std::size_t>(frame) * 2] = accumulate(
        interleaved[static_cast<std::size_t>(frame) * 2], wave, gain, ring);
    phase += increment;
  }
  return phase;
}

#pragma pack(push, 1)
struct RenderArguments {
  std::int32_t waveform;
  float* interleaved;
  std::uint32_t frames;
  std::uint32_t phase;
  std::uint32_t increment;
  float gain;
};
#pragma pack(pop)
static_assert(sizeof(RenderArguments) == 28);
static_assert(offsetof(RenderArguments, interleaved) == 4);

// Only the observed render command family is reconstructed here. Lifecycle,
// custom-wave construction and plugin/host entrypoints are not implemented.
inline std::uintptr_t dispatchRender(OscState& state, Runtime& runtime,
                                      std::int32_t opcode,
                                      const RenderArguments& arguments) {
  if (opcode < 10 || opcode > 12) return 0;
  if (opcode == 11) {
    for (std::uint32_t i = 0; i < arguments.frames; ++i)
      arguments.interleaved[static_cast<std::size_t>(i) * 2] = 0.0f;
  }
  return addOsc(state, runtime, arguments.waveform, arguments.interleaved,
                arguments.frames, arguments.gain, arguments.phase,
                arguments.increment, opcode == 12);
}

}  // namespace veggie_loops::three_osc
