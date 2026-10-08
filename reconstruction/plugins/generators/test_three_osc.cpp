#include "three_osc.hpp"

#if !defined(__APPLE__) || !defined(__aarch64__)
#error This isolated native comparison requires macOS on Apple Silicon.
#endif

#include <CommonCrypto/CommonDigest.h>
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <array>
#include <bit>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>

using namespace veggie_loops::three_osc;

namespace {
void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}
std::vector<std::uint8_t> readFile(const char* path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), std::string("Cannot read ") + path);
  return {(std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>()};
}
std::string digest(const std::uint8_t* data, std::size_t length) {
  std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> bytes{};
  require(length <= UINT32_MAX, "Digest input too large");
  CC_SHA256(data, static_cast<CC_LONG>(length), bytes.data());
  std::ostringstream output;
  for (auto byte : bytes)
    output << std::hex << std::setfill('0') << std::setw(2) << unsigned(byte);
  return output.str();
}

struct Body {
  std::size_t offset;
  std::size_t size;
  const char* sha256;
};
constexpr std::array<Body, 7> bodies = {{
    {0x3454, 16, "62ac84980a5e6ec252a3179727b15e3f1c2854a62ed169244ce5b84c370a7118"},
    {0x3880, 24, "55b76f804d0e3171345fe591666a8c15a4d6940de43ebd4df51f76d92519d2a1"},
    {0x3898, 380, "000e2aa25607688bbfd7cd9bb61bf051cf3db0e90fccbf1019feec0a8459d4d7"},
    {0x35c4, 156, "3a2e1988e4ffa8367915519f003d08fe7303a15f606f74488b0209ab53b7a191"},
    {0x3660, 544, "2622f6b6d130302159258a6cf89b92da92ac07063652a553f175ccb0482186bd"},
    {0x3a14, 228, "03bb1f3970ee3e34aa17185f0283496bb45310ae872e4083ea6b45ea359dda25"},
    {0x20f8, 32, "9bf7d0ed5cd18f3b58aabb07e3a73c07d5333483e3b77a77075585196fdbde2e"}
}};
constexpr char sourceDigest[] =
    "d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f";
constexpr char sliceDigest[] =
    "c90d11fe12c86d620aabd135078c7cca49cc2b007b0c750e0db63a1e7508db48";

// Only seven reviewed native routines and their numeric/jump constants are
// copied into an anonymous mapping. Original constructors, FFT/mipmap code,
// the FL Studio host, plugin initialization and commercial assets are absent.
// Calls to imported pow/log10/sinf use the same local platform math library.
class Replay {
 public:
  explicit Replay(const std::vector<std::uint8_t>& slice) {
    page_ = static_cast<std::size_t>(sysconf(_SC_PAGESIZE));
    require(page_ == 16384, "Replay requires the reviewed 16K arm64 page layout");
    base_ = static_cast<std::uint8_t*>(
        mmap(nullptr, 0xc000, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0));
    require(base_ != MAP_FAILED, "Cannot reserve native replay pages");
    try {
      protect(0, PROT_READ | PROT_WRITE);
      for (auto body : bodies) {
        require(digest(slice.data() + body.offset, body.size) == body.sha256,
                "Reviewed routine hash mismatch");
        std::memcpy(base_ + body.offset, slice.data() + body.offset, body.size);
      }
      std::memcpy(base_ + 0x3dd0, slice.data() + 0x3dd0, 0x89);
      import(0x3bb0, 0x1000, reinterpret_cast<void*>(static_cast<double (*)(double)>(&::log10)));
      import(0x3be0, 0x1020, reinterpret_cast<void*>(static_cast<double (*)(double, double)>(&::pow)));
      import(0x3bec, 0x1040, reinterpret_cast<void*>(&::sinf));
      protect(0, PROT_READ | PROT_EXEC);
      sys_icache_invalidate(base_, page_);
      protect(0x8000, PROT_READ | PROT_WRITE);
      std::memset(base_ + 0x8000, 0, page_);
      *reinterpret_cast<double*>(base_ + 0x80e0) = 0x1p-32;
      base_[0x80e8] = 1;  // Synthetic initialized guard; no constructor called.
    } catch (...) {
      munmap(base_, 0xc000);
      base_ = nullptr;
      throw;
    }
  }
  ~Replay() { if (base_) munmap(base_, 0xc000); }
  Replay(const Replay&) = delete;
  Replay& operator=(const Replay&) = delete;
  template <typename Function> Function routine(std::size_t offset) {
    return reinterpret_cast<Function>(base_ + offset);
  }
  void factory(WaveTable* value) {
    *reinterpret_cast<WaveTable**>(base_ + 0x80d0) = value;
  }
  void seed(std::uint32_t value) {
    *reinterpret_cast<std::uint32_t*>(base_ + 0x80c8) = value;
  }
  std::uint32_t seed() const {
    return *reinterpret_cast<std::uint32_t*>(base_ + 0x80c8);
  }
 private:
  void protect(std::size_t offset, int flags) {
    require(mprotect(base_ + offset, page_, flags) == 0, "Replay protection failed");
  }
  void import(std::size_t stub, std::size_t thunk, void* address) {
    // Native imported stubs are only twelve bytes apart. Branch to our own
    // 16-byte thunk rather than overwriting an adjacent import.
    const auto delta = static_cast<std::int32_t>(thunk) - static_cast<std::int32_t>(stub);
    const std::uint32_t branch = 0x14000000u | ((delta / 4) & 0x03ffffffu);
    std::memcpy(base_ + stub, &branch, 4);
    const std::array<std::uint32_t, 2> instructions = {0x58000050, 0xd61f0200};
    std::memcpy(base_ + thunk, instructions.data(), 8);
    const auto pointer = reinterpret_cast<std::uintptr_t>(address);
    std::memcpy(base_ + thunk + 8, &pointer, 8);
  }
  std::uint8_t* base_ = nullptr;
  std::size_t page_ = 0;
};

bool same(float a, float b) {
  return std::bit_cast<std::uint32_t>(a) == std::bit_cast<std::uint32_t>(b);
}
bool same(double a, double b) {
  return std::bit_cast<std::uint64_t>(a) == std::bit_cast<std::uint64_t>(b);
}

struct SyntheticTables {
  std::array<std::vector<float>, 14> data;
  std::array<float*, 14> pointers{};
  std::array<MipMap, 5> maps{};
  std::array<MipMap*, 5> mapPointers{};
  WaveTable factory;
  WaveTable custom;
  SyntheticTables() {
    for (std::size_t level = 0; level < data.size(); ++level) {
      data[level].resize(32770);
      for (std::size_t sample = 0; sample < data[level].size(); ++sample) {
        // Independently generated, exactly representable test data. This does
        // not substitute captured or proprietary waveforms into the model.
        data[level][sample] = float(int((sample * 17 + level * 31) % 2048) - 1024) / 1024.0f;
      }
      pointers[level] = data[level].data();
    }
    for (std::size_t i = 0; i < maps.size(); ++i) {
      maps[i] = {14, 0, pointers.data(), nullptr};
      mapPointers[i] = &maps[i];
    }
    factory = {4, 0, mapPointers.data()};
    custom = {1, 0, mapPointers.data() + 4};
  }
};
}  // namespace

int main(int argc, char** argv) {
  try {
    require(argc == 4, "Usage: test_three_osc <installed engine> <private arm64 slice> <stats.json>");
    const auto source = readFile(argv[1]);
    const auto slice = readFile(argv[2]);
    require(source.size() == 154112 && digest(source.data(), source.size()) == sourceDigest,
            "Installed source identity mismatch");
    require(slice.size() == 72192 && digest(slice.data(), slice.size()) == sliceDigest,
            "Arm64 slice identity mismatch");
    require(std::memcmp(source.data() + 81920, slice.data(), slice.size()) == 0,
            "Slice is not the reviewed source range");
    Replay native(slice);
    SyntheticTables tables;
    native.factory(&tables.factory);
    std::mt19937_64 random(0x334f534344535031ULL);
    std::size_t rateCases = 0, pitchCases = 0, waveformCases = 0,
                tableCases = 0, renderCases = 0, dispatchCases = 0, renderedSamples = 0;

    using RateRoutine = void (*)(OscState*, double);
    using PitchRoutine = double (*)(const OscState*, double);
    using WaveRoutine = float (*)(const OscState*, float);
    using SelectRoutine = void (*)(OscState*, double, bool);
    using AddRoutine = std::uint32_t (*)(OscState*, std::int32_t, float*, std::uint32_t,
                                       float, std::uint32_t, std::uint32_t, bool);
    using DispatchRoutine = std::uintptr_t (*)(OscState*, std::int32_t, const RenderArguments*);
    const auto nativeRate = native.routine<RateRoutine>(0x3454);
    const auto nativePitch = native.routine<PitchRoutine>(0x3880);
    const auto nativeWave = native.routine<WaveRoutine>(0x3898);
    const auto nativeSelect = native.routine<SelectRoutine>(0x35c4);
    const auto nativeAdd = native.routine<AddRoutine>(0x3660);
    const auto nativeDispatch = native.routine<DispatchRoutine>(0x3a14);

    for (double rate : {0.0, -0.0, 1.0, -1.0, 8000.0, 44100.0, 48000.0,
                        96000.0, 192000.0, std::numeric_limits<double>::infinity()}) {
      OscState a, b;
      nativeRate(&a, rate); setSampleRate(b, rate);
      require(same(a.sampleRate, b.sampleRate) && same(a.inverseSampleRate, b.inverseSampleRate),
              "Sample rate mismatch");
      ++rateCases;
    }
    for (std::size_t i = 0; i < 4000; ++i) {
      OscState state;
      setSampleRate(state, 8000.0 + double(random() % 184000));
      const double increment = double(1 + random() % UINT32_MAX) * 0x1p-32;
      require(same(nativePitch(&state, increment), phaseAddToPitch(state, increment)),
              "Pitch conversion mismatch");
      ++pitchCases;
    }
    for (int waveform = 0; waveform <= 7; ++waveform) {
      for (double increment : {0.0, 0.0001, std::nextafter(0.0005, 0.0), 0.0005,
                               std::nextafter(0.0005, 1.0), 0.4}) {
        OscState state;
        state.waveform = waveform; state.phaseIncrement = increment;
        state.lowerTable = tables.pointers[0];
        for (std::size_t i = 0; i < 2500; ++i) {
          float phase = static_cast<float>(double(random() & UINT32_MAX) * 0x1p-32);
          if (i < 9) phase = std::array<float, 9>{0.0f, -0.0f, 0.25f, 0.5f, 0.75f,
                                0.4638671875f, 5.0f / 6.0f, 1.0f,
                                std::nextafter(1.0f, 0.0f)}[i];
          const float a = nativeWave(&state, phase), b = processWave(state, phase);
          if (!same(a, b)) {
            std::ostringstream message;
            message << "Wave mismatch, waveform=" << waveform << ", phase=" << phase
                    << ", increment=" << increment << ", native=" << a << ", model=" << b;
            throw std::runtime_error(message.str());
          }
          ++waveformCases;
        }
      }
    }
    for (int waveform = 1; waveform <= 6; ++waveform) {
      if (waveform == 5) continue;
      for (int count = 2; count <= 14; ++count) {
        for (auto& map : tables.maps) map.count = count;
        for (std::size_t i = 0; i < 200; ++i) {
          OscState a, b; a.custom = b.custom = tables.custom;
          a.waveform = b.waveform = waveform;
          const double pitch = double(int(random() % 30000) - 10000) / 1000.0;
          nativeSelect(&a, pitch, waveform == 6);
          selectWaveTable(b, pitch, waveform == 6, tables.factory);
          require(a.lowerIndex == b.lowerIndex && a.upperIndex == b.upperIndex &&
                      same(a.lowerWeight, b.lowerWeight) && a.lowerTable == b.lowerTable &&
                      a.upperTable == b.upperTable, "Mipmap selection mismatch");
          ++tableCases;
        }
      }
    }
    for (auto& map : tables.maps) map.count = 14;
    for (int waveform = 0; waveform <= 6; ++waveform) {
      for (bool ring : {false, true}) {
        for (std::size_t i = 0; i < 150; ++i) {
          const std::uint32_t frames = static_cast<std::uint32_t>(i % 130);
          const std::uint32_t increment = i % 11 == 0 ? 0 :
              i % 2 ? static_cast<std::uint32_t>(random())
                    : static_cast<std::uint32_t>(1 + random() % 2000000);
          const std::uint32_t phase = static_cast<std::uint32_t>(random());
          const float gain = float(int(random() % 2048) - 512) / 512.0f;
          const std::uint32_t initialSeed = static_cast<std::uint32_t>(random());
          std::vector<float> a(frames * 2 + 2), b;
          for (auto& value : a) value = float(int(random() % 2048) - 1024) / 1024.0f;
          b = a;
          OscState sa, sb; sa.custom = sb.custom = tables.custom;
          setSampleRate(sa, 48000); setSampleRate(sb, 48000);
          Runtime runtime{waveform == 6 ? nullptr : &tables.factory, initialSeed};
          native.factory(runtime.factory); native.seed(initialSeed);
          const auto pa = nativeAdd(&sa, waveform, a.data(), frames, gain, phase, increment, ring);
          const auto pb = addOsc(sb, runtime, waveform, b.data(), frames, gain, phase, increment, ring);
          require(pa == pb && native.seed() == runtime.noiseSeed, "Render phase/seed mismatch");
          require(std::memcmp(a.data(), b.data(), a.size() * sizeof(float)) == 0,
                  "Render samples or untouched lane mismatch");
          require(same(sa.phaseIncrement, sb.phaseIncrement) && sa.waveform == sb.waveform &&
                      sa.lowerIndex == sb.lowerIndex && sa.upperIndex == sb.upperIndex &&
                      same(sa.lowerWeight, sb.lowerWeight) && sa.lowerTable == sb.lowerTable &&
                      sa.upperTable == sb.upperTable, "Render state mismatch");
          ++renderCases; renderedSamples += frames;
        }
      }
    }
    for (int opcode = 10; opcode <= 12; ++opcode) {
      for (int waveform = 0; waveform <= 6; ++waveform) {
        for (std::size_t i = 0; i < 70; ++i) {
          const auto frames = static_cast<std::uint32_t>(i);
          std::vector<float> a(frames * 2 + 2), b;
          for (auto& value : a) value = float(int(random() % 1024) - 512) / 512.0f;
          b = a;
          OscState sa, sb; sa.custom = sb.custom = tables.custom;
          Runtime runtime{waveform == 6 ? nullptr : &tables.factory,
                          static_cast<std::uint32_t>(random())};
          native.factory(runtime.factory);
          native.seed(runtime.noiseSeed);
          RenderArguments ra{waveform, a.data(), frames, static_cast<std::uint32_t>(random()),
                             static_cast<std::uint32_t>(1 + random() % 10000000), 0.71f};
          RenderArguments rb = ra; rb.interleaved = b.data();
          const auto pa = nativeDispatch(&sa, opcode, &ra);
          const auto pb = dispatchRender(sb, runtime, opcode, rb);
          require(pa == pb && native.seed() == runtime.noiseSeed &&
                      std::memcmp(a.data(), b.data(), a.size() * sizeof(float)) == 0,
                  "Render dispatch mismatch");
          ++dispatchCases; renderedSamples += frames;
        }
      }
    }
    const auto total = rateCases + pitchCases + waveformCases + tableCases + renderCases + dispatchCases;
    std::ostringstream report;
    report << "{\n  \"status\": \"passed\",\n  \"architecture\": \"arm64\",\n"
           << "  \"source_sha256\": \"" << sourceDigest << "\",\n"
           << "  \"slice_sha256\": \"" << sliceDigest << "\",\n"
           << "  \"total_cases\": " << total << ",\n"
           << "  \"sample_rate_cases\": " << rateCases << ",\n"
           << "  \"pitch_cases\": " << pitchCases << ",\n"
           << "  \"waveform_cases\": " << waveformCases << ",\n"
           << "  \"mipmap_selection_cases\": " << tableCases << ",\n"
           << "  \"render_cases\": " << renderCases << ",\n"
           << "  \"render_dispatch_cases\": " << dispatchCases << ",\n"
           << "  \"rendered_lane_samples\": " << renderedSamples << ",\n"
           << "  \"comparison\": \"bitwise output, phase, noise seed, observed state and untouched lane\",\n"
           << "  \"original_routines_replayed\": 7,\n"
           << "  \"native_constructor_or_plugin_loaded\": false,\n"
           << "  \"synthetic_tables\": true,\n"
           << "  \"full_plugin_equivalence\": false,\n"
           << "  \"limitations\": [\"Only the reviewed DSP routines and render opcodes 10/11/12; original wavetable/FFT construction, lifecycle, custom-wave import, UI, presets, automation, polyphony and complete plugin/host ABI are unverified.\"]\n}\n";
    std::ofstream output(argv[3]); require(output.good(), "Cannot save report");
    output << report.str(); require(output.good(), "Cannot write report");
    std::cout << report.str();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
