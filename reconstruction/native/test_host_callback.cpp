#include "host_callback.hpp"

#if !defined(__APPLE__) || !defined(__aarch64__)
#error This differential test requires macOS on Apple Silicon.
#endif

#include <CommonCrypto/CommonDigest.h>
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr std::size_t kArm64Offset = 4'292'608;
constexpr std::size_t kArm64Size = 4'388'048;
constexpr std::size_t kWideOffset = 0x3c80;
constexpr std::size_t kWideSize = 60;
constexpr std::size_t kLegacyOffset = 0x3c40;
constexpr std::size_t kLegacySize = 52;
constexpr char kSourceDigest[] =
    "1a5e8e157a7fccbe031814172fb49eb939f6397d05841afb051a96cc31acae02";
constexpr char kSliceDigest[] =
    "35f35041c388a013751f96bd321fc8b2a5098472fdd9544a348e38851f90efa2";
constexpr char kWideDigest[] =
    "03ea1e164005a82409dd63cdc926348c6f5eae01e421ab59d0f7e6d881e6cdb1";
constexpr char kLegacyDigest[] =
    "3f49a0e3bb346f38ed5ab0d3eaf97a69ea5f8c42c8538339bc9711d65ab010e3";

std::string sha256(const std::uint8_t* bytes, std::size_t size) {
  if (size > std::numeric_limits<CC_LONG>::max()) {
    throw std::runtime_error("Input exceeds the digest function's size limit");
  }
  std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest{};
  CC_SHA256(bytes, static_cast<CC_LONG>(size), digest.data());
  std::ostringstream output;
  for (unsigned char byte : digest) {
    output << std::hex << std::setw(2) << std::setfill('0')
           << static_cast<unsigned>(byte);
  }
  return output.str();
}

void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Only these two short, reviewed launcher callbacks are mapped. The original
// application and engine are never loaded or launched. No original code bytes
// are embedded in this source or written as a redistributable binary.
class CallbackMapping final {
 public:
  CallbackMapping(const std::uint8_t* bytes, std::size_t size) {
    const long pageSize = sysconf(_SC_PAGESIZE);
    require(pageSize > 0, "Cannot determine the memory page size");
    size_ = static_cast<std::size_t>(pageSize);
    require(size <= size_, "Callback does not fit in one page");
    memory_ = mmap(nullptr, size_, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
    if (memory_ == MAP_FAILED) {
      throw std::runtime_error(std::string("mmap failed: ") + std::strerror(errno));
    }
    std::memcpy(memory_, bytes, size);
    if (mprotect(memory_, size_, PROT_READ | PROT_EXEC) != 0) {
      const std::string error = std::strerror(errno);
      munmap(memory_, size_);
      memory_ = MAP_FAILED;
      throw std::runtime_error("mprotect failed: " + error);
    }
    sys_icache_invalidate(memory_, size);
  }

  ~CallbackMapping() {
    if (memory_ != MAP_FAILED) munmap(memory_, size_);
  }

  CallbackMapping(const CallbackMapping&) = delete;
  CallbackMapping& operator=(const CallbackMapping&) = delete;

  template <typename Function>
  Function function() const {
    return reinterpret_cast<Function>(memory_);
  }

 private:
  void* memory_ = MAP_FAILED;
  std::size_t size_ = 0;
};

struct StubSelf {
  void** vmt;
};

struct CapturedCall {
  void* self = nullptr;
  std::int64_t command = 0;
  std::int64_t index = 0;
  std::int64_t value = 0;
  std::uint64_t returnValue = 0;
  std::size_t calls = 0;
} captured;

extern "C" std::uint64_t stubDispatch(void* self, std::int64_t command,
                                     std::int64_t index, std::int64_t value) {
  captured.self = self;
  captured.command = command;
  captured.index = index;
  captured.value = value;
  ++captured.calls;
  return captured.returnValue;
}

}  // namespace

int main(int argc, char** argv) {
  try {
    require(argc == 3, "Usage: test_host_callback <installed OsxFL path> <stats.json>");
    std::ifstream source(argv[1], std::ios::binary);
    require(source.good(), "Cannot read the selected installed launcher");
    const std::vector<std::uint8_t> bytes(
        (std::istreambuf_iterator<char>(source)), std::istreambuf_iterator<char>());
    require(sha256(bytes.data(), bytes.size()) == kSourceDigest,
            "Installed launcher identity differs from the investigated version");
    require(kArm64Offset + kArm64Size <= bytes.size(), "Missing arm64 slice");
    const std::uint8_t* slice = bytes.data() + kArm64Offset;
    require(sha256(slice, kArm64Size) == kSliceDigest, "Arm64 slice identity mismatch");
    require(sha256(slice + kWideOffset, kWideSize) == kWideDigest,
            "Wide callback bytes differ from retained REA evidence");
    require(sha256(slice + kLegacyOffset, kLegacySize) == kLegacyDigest,
            "Legacy callback bytes differ from retained REA evidence");

    CallbackMapping wideMemory(slice + kWideOffset, kWideSize);
    CallbackMapping legacyMemory(slice + kLegacyOffset, kLegacySize);
    using WideCallback = std::int64_t (*)(void*, std::int64_t, std::int64_t, std::int64_t);
    using LegacyCallback = std::uint64_t (*)(void*, std::int32_t, std::int32_t, std::int32_t);
    const auto originalWide = wideMemory.function<WideCallback>();
    const auto originalLegacy = legacyMemory.function<LegacyCallback>();

    const std::array<std::int64_t, 13> commands = {
        INT64_MIN, INT32_MIN, -1, 0, 1, 2, 3, 4, 5, INT32_MAX,
        static_cast<std::int64_t>(INT32_MAX) + 1, UINT32_MAX, INT64_MAX};
    const std::array<std::int64_t, 21> indexes = {
        INT64_MIN, -4'294'967'297LL, -4'294'967'296LL, -4'294'967'295LL,
        INT32_MIN, -2, -1, 0, 1, 2, 3, 127, 128, INT32_MAX,
        static_cast<std::int64_t>(INT32_MAX) + 1, UINT32_MAX,
        4'294'967'296LL, 4'294'967'297LL, 4'294'967'298LL,
        INT64_MAX - 1, INT64_MAX};
    const std::array<std::int64_t, 6> values = {
        INT64_MIN, -1, 0, 1, UINT32_MAX, INT64_MAX};
    std::size_t wideCases = 0;
    for (const auto command : commands) {
      for (const auto index : indexes) {
        for (const auto value : values) {
          require(originalWide(nullptr, command, index, value) ==
                      veggie_loops::VeggieLoopsHost::dispatch(command, index, value),
                  "Wide callback differential mismatch");
          ++wideCases;
        }
      }
    }
    std::mt19937_64 random(0x564c53545544494fULL);
    for (std::size_t iteration = 0; iteration < 10'000; ++iteration) {
      const auto command = iteration % 2 == 0 ? 3 : static_cast<std::int64_t>(random());
      const auto index = static_cast<std::int64_t>(random());
      const auto value = static_cast<std::int64_t>(random());
      require(originalWide(nullptr, command, index, value) ==
                  veggie_loops::VeggieLoopsHost::dispatch(command, index, value),
              "Random wide callback differential mismatch");
      ++wideCases;
    }

    // The original legacy adapter reads self[0] and VMT+0xd8. A stub table at
    // precisely that offset verifies input sign extension and result truncation.
    std::array<void*, 28> vmt{};
    vmt[0xd8 / sizeof(void*)] = reinterpret_cast<void*>(&stubDispatch);
    StubSelf self{vmt.data()};
    const std::array<std::int32_t, 9> legacyInputs = {
        INT32_MIN, -2, -1, 0, 1, 2, 3, 4, INT32_MAX};
    const std::array<std::uint64_t, 6> returnValues = {
        0, 1, UINT32_MAX, 0x1'0000'0000ULL, 0x12345678'abcdef01ULL, UINT64_MAX};
    std::size_t legacyCases = 0;
    for (const auto command : legacyInputs) {
      for (const auto index : legacyInputs) {
        for (const auto value : legacyInputs) {
          for (const auto result : returnValues) {
            captured.returnValue = result;
            const auto before = captured.calls;
            const auto observed = originalLegacy(&self, command, index, value);
            require(captured.calls == before + 1 && captured.self == &self,
                    "Legacy adapter did not invoke the expected stub exactly once");
            require(captured.command == static_cast<std::int64_t>(command) &&
                        captured.index == static_cast<std::int64_t>(index) &&
                        captured.value == static_cast<std::int64_t>(value),
                    "Legacy adapter sign-extension mismatch");
            require(observed == static_cast<std::uint32_t>(result),
                    "Legacy adapter result-truncation mismatch");
            ++legacyCases;
          }
        }
      }
    }

    // Point the same stub VMT at the original wide callback to check the entire
    // legacy-to-wide path against the independent reconstruction.
    vmt[0xd8 / sizeof(void*)] = reinterpret_cast<void*>(originalWide);
    std::size_t composedCases = 0;
    for (const auto command : legacyInputs) {
      for (const auto index : legacyInputs) {
        for (const auto value : legacyInputs) {
          require(originalLegacy(&self, command, index, value) ==
                      veggie_loops::VeggieLoopsHost::dispatchLegacy(command, index, value),
                  "Composed legacy callback differential mismatch");
          ++composedCases;
        }
      }
    }

    std::ostringstream stats;
    stats << "{\n  \"status\": \"passed\",\n"
          << "  \"architecture\": \"arm64\",\n"
          << "  \"source_sha256\": \"" << kSourceDigest << "\",\n"
          << "  \"slice_sha256\": \"" << kSliceDigest << "\",\n"
          << "  \"original_wide_callback_bytes\": " << kWideSize << ",\n"
          << "  \"original_legacy_callback_bytes\": " << kLegacySize << ",\n"
          << "  \"wide_differential_cases\": " << wideCases << ",\n"
          << "  \"legacy_adapter_cases\": " << legacyCases << ",\n"
          << "  \"composed_legacy_differential_cases\": " << composedCases << ",\n"
          << "  \"total_cases\": " << wideCases + legacyCases + composedCases << ",\n"
          << "  \"engine_loaded\": false,\n"
          << "  \"original_application_launched\": false,\n"
          << "  \"limitations\": [\"Only two standalone host callbacks were executed against stub self/vtables. This does not validate an audio engine or live FL Studio behavior.\"]\n}\n";
    std::ofstream output(argv[2]);
    require(output.good(), "Cannot open test stats destination");
    output << stats.str();
    require(output.good(), "Cannot save test stats");
    std::cout << stats.str();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
