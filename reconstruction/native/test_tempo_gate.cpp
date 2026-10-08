#include "tempo_gate.hpp"

#if !defined(__APPLE__) || !defined(__aarch64__)
#error This isolated differential test requires macOS on Apple Silicon.
#endif

#include <CommonCrypto/CommonDigest.h>
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <array>
#include <bit>
#include <cerrno>
#include <cfenv>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <memory>
#include <random>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#pragma STDC FENV_ACCESS ON

namespace {

using veggie_loops::tempo_gate::State;
constexpr std::size_t kSliceOffset = 36'454'400;
constexpr std::size_t kSliceSize = 26'584'592;
constexpr std::size_t kBodyOffset = 0x4a7cc0;
constexpr std::size_t kBodySize = 152;
constexpr std::size_t kProbeOffset = 0x2c45a0;
constexpr std::size_t kEnterOffset = 0x8ac020;
constexpr std::size_t kApplyOffset = 0x6f2520;
constexpr std::size_t kLeaveOffset = 0x8ac050;
constexpr std::size_t kValueA70Offset = 0x167da70;
constexpr std::size_t kValueA80Offset = 0x167da80;
constexpr std::size_t kByteOffset = 0x18d7ed6;
constexpr std::size_t kPointerOffset = 0x19b4848;
constexpr char kSourceDigest[] =
    "22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37";
constexpr char kSliceDigest[] =
    "04db862b730950c5e2b678e5477900bec29ab839bf35611dce92be1795636eb0";
constexpr char kBodyDigest[] =
    "aead95b1e84e16ade8815efdd1de30c7c4c396ca8dd7ebbae986198f4e045806";

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

std::vector<std::uint8_t> readFile(const char* path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), std::string("Cannot read ") + path);
  return {(std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>()};
}

std::string sha256(const std::uint8_t* bytes, std::size_t size) {
  require(size <= std::numeric_limits<CC_LONG>::max(), "Digest input too large");
  std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest{};
  CC_SHA256(bytes, static_cast<CC_LONG>(size), digest.data());
  std::ostringstream output;
  for (unsigned char byte : digest) {
    output << std::hex << std::setw(2) << std::setfill('0')
           << static_cast<unsigned>(byte);
  }
  return output.str();
}

struct Plan {
  std::uint32_t probeResult = 0;
  bool probeChangesA70 = false;
  double probeA70 = 0;
  bool probeChangesA80 = false;
  double probeA80 = 0;
  bool enterChangesA80 = false;
  double enterA80 = 0;
  bool enterChangesPointer = false;
  std::uintptr_t enterPointer = 0;
  bool applyChangesPointer = false;
  std::uintptr_t applyPointer = 0;
};

struct Event {
  unsigned kind = 0;  // 0 probe, 1 enter, 2 apply, 3 leave.
  std::uint64_t argument = 0;
  std::uint32_t flag = 0;
  std::uint64_t a70 = 0;
  std::uint64_t a80 = 0;
  std::uintptr_t pointer = 0;
  bool operator==(const Event&) const = default;
};

struct Observation {
  State state;
  std::vector<Event> events;
  int exceptions = 0;
};

// Capturing stubs see either the sparse native globals or the model's State.
// They do not perform floating-point arithmetic or call any engine routine.
struct Hooks {
  double* a70 = nullptr;
  double* a80 = nullptr;
  std::uintptr_t* pointer = nullptr;
  const Plan* plan = nullptr;
  std::vector<Event>* events = nullptr;

  void record(unsigned kind, std::uint64_t argument = 0, std::uint32_t flag = 0) {
    events->push_back({kind, argument, flag, std::bit_cast<std::uint64_t>(*a70),
                       std::bit_cast<std::uint64_t>(*a80), *pointer});
  }
  std::uint32_t probe() {
    record(0);
    if (plan->probeChangesA70) *a70 = plan->probeA70;
    if (plan->probeChangesA80) *a80 = plan->probeA80;
    return plan->probeResult;
  }
  void enter(std::uintptr_t value) {
    record(1, value);
    if (plan->enterChangesA80) *a80 = plan->enterA80;
    if (plan->enterChangesPointer) *pointer = plan->enterPointer;
  }
  void apply(double value, std::uint32_t flag) {
    record(2, std::bit_cast<std::uint64_t>(value), flag);
    if (plan->applyChangesPointer) *pointer = plan->applyPointer;
  }
  void leave(std::uintptr_t value) { record(3, value); }
};

Hooks* activeHooks = nullptr;
extern "C" std::uint32_t probeStub() { return activeHooks->probe(); }
extern "C" void enterStub(std::uintptr_t value) { activeHooks->enter(value); }
extern "C" void applyStub(std::uint32_t flag, double value) {
  activeHooks->apply(value, flag);
}
extern "C" void leaveStub(std::uintptr_t value) { activeHooks->leave(value); }

class SparseReplay final {
 public:
  explicit SparseReplay(const std::vector<std::uint8_t>& slice) {
    const long page = sysconf(_SC_PAGESIZE);
    require(page > 0, "Cannot determine page size");
    pageSize_ = static_cast<std::size_t>(page);
    require(pageSize_ % 4096 == 0, "Page alignment does not preserve ADRP addresses");
    size_ = pageStart(kPointerOffset) + pageSize_;
    base_ = static_cast<std::uint8_t*>(
        mmap(nullptr, size_, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0));
    if (base_ == MAP_FAILED) {
      throw std::runtime_error(std::string("mmap failed: ") + std::strerror(errno));
    }
    try {
      const std::array<std::size_t, 5> codeLocations = {
          kBodyOffset, kProbeOffset, kEnterOffset, kApplyOffset, kLeaveOffset};
      for (const auto offset : codeLocations) codePages_.insert(pageStart(offset));
      for (const auto pageOffset : codePages_) protect(pageOffset, PROT_READ | PROT_WRITE);
      std::memcpy(base_ + kBodyOffset, slice.data() + kBodyOffset, kBodySize);
      trampoline(kProbeOffset, reinterpret_cast<void*>(&probeStub));
      trampoline(kEnterOffset, reinterpret_cast<void*>(&enterStub));
      trampoline(kApplyOffset, reinterpret_cast<void*>(&applyStub));
      trampoline(kLeaveOffset, reinterpret_cast<void*>(&leaveStub));
      for (const auto pageOffset : codePages_) {
        protect(pageOffset, PROT_READ | PROT_EXEC);
        sys_icache_invalidate(base_ + pageOffset, pageSize_);
      }
      const std::array<std::size_t, 4> dataLocations = {
          kValueA70Offset, kValueA80Offset, kByteOffset, kPointerOffset};
      for (const auto offset : dataLocations) dataPages_.insert(pageStart(offset));
      for (const auto pageOffset : dataPages_) {
        require(!codePages_.contains(pageOffset), "Code/data pages overlap");
        protect(pageOffset, PROT_READ | PROT_WRITE);
      }
      std::construct_at(a70(), 0.0);
      std::construct_at(a80(), 0.0);
      std::construct_at(byteFlag(), std::uint8_t{0});
      std::construct_at(pointer(), std::uintptr_t{0});
      require(sha256(base_ + kBodyOffset, kBodySize) == kBodyDigest,
              "Mapped original routine was changed");
    } catch (...) {
      munmap(base_, size_);
      base_ = nullptr;
      throw;
    }
  }

  ~SparseReplay() { if (base_) munmap(base_, size_); }
  SparseReplay(const SparseReplay&) = delete;
  SparseReplay& operator=(const SparseReplay&) = delete;

  Observation run(float input, const State& initial, const Plan& plan) {
    *a70() = initial.valueA70;
    *a80() = initial.valueA80;
    *byteFlag() = initial.byteFlag;
    *pointer() = initial.opaquePointer;
    Observation observation;
    Hooks hooks{a70(), a80(), pointer(), &plan, &observation.events};
    activeHooks = &hooks;
    std::feclearexcept(FE_ALL_EXCEPT);
    using Routine = void (*)(void*, float);
    reinterpret_cast<Routine>(base_ + kBodyOffset)(nullptr, input);
    observation.exceptions = std::fetestexcept(FE_ALL_EXCEPT);
    activeHooks = nullptr;
    observation.state = {*a70(), *a80(), *byteFlag(), *pointer()};
    return observation;
  }

  std::size_t reservationSize() const { return size_; }
  std::size_t codePageCount() const { return codePages_.size(); }
  std::size_t dataPageCount() const { return dataPages_.size(); }
  std::size_t pageSize() const { return pageSize_; }

 private:
  std::size_t pageStart(std::size_t offset) const { return offset - offset % pageSize_; }
  void protect(std::size_t offset, int protection) {
    if (mprotect(base_ + offset, pageSize_, protection) != 0) {
      throw std::runtime_error(std::string("mprotect failed: ") + std::strerror(errno));
    }
  }
  // Generated test code: LDR x16, literal at +8; BR x16; our stub address.
  // This preserves the original routine's BL return address and argument regs.
  void trampoline(std::size_t offset, void* target) {
    const std::array<std::uint32_t, 2> instructions = {0x58000050, 0xd61f0200};
    const auto pointerBits = reinterpret_cast<std::uintptr_t>(target);
    std::memcpy(base_ + offset, instructions.data(), sizeof(instructions));
    std::memcpy(base_ + offset + 8, &pointerBits, sizeof(pointerBits));
  }
  double* a70() const { return reinterpret_cast<double*>(base_ + kValueA70Offset); }
  double* a80() const { return reinterpret_cast<double*>(base_ + kValueA80Offset); }
  std::uint8_t* byteFlag() const { return base_ + kByteOffset; }
  std::uintptr_t* pointer() const {
    return reinterpret_cast<std::uintptr_t*>(base_ + kPointerOffset);
  }
  std::uint8_t* base_ = nullptr;
  std::size_t size_ = 0;
  std::size_t pageSize_ = 0;
  std::set<std::size_t> codePages_;
  std::set<std::size_t> dataPages_;
};

Observation runModel(float input, const State& initial, const Plan& plan) {
  Observation observation{initial, {}, 0};
  Hooks hooks{&observation.state.valueA70, &observation.state.valueA80,
              &observation.state.opaquePointer, &plan, &observation.events};
  std::feclearexcept(FE_ALL_EXCEPT);
  veggie_loops::tempo_gate::update(observation.state, input, hooks);
  observation.exceptions = std::fetestexcept(FE_ALL_EXCEPT);
  return observation;
}

bool equal(const Observation& left, const Observation& right) {
  return std::bit_cast<std::uint64_t>(left.state.valueA70) ==
             std::bit_cast<std::uint64_t>(right.state.valueA70) &&
         std::bit_cast<std::uint64_t>(left.state.valueA80) ==
             std::bit_cast<std::uint64_t>(right.state.valueA80) &&
         left.state.byteFlag == right.state.byteFlag &&
         left.state.opaquePointer == right.state.opaquePointer &&
         left.events == right.events && left.exceptions == right.exceptions;
}

}  // namespace

int main(int argc, char** argv) {
  try {
    require(argc == 4, "Usage: test_tempo_gate <installed engine> <private arm64 slice> <stats.json>");
    const auto source = readFile(argv[1]);
    const auto slice = readFile(argv[2]);
    require(sha256(source.data(), source.size()) == kSourceDigest, "Source identity mismatch");
    require(slice.size() == kSliceSize &&
                sha256(slice.data(), slice.size()) == kSliceDigest, "Slice identity mismatch");
    require(kSliceOffset + kSliceSize <= source.size() &&
                std::memcmp(source.data() + kSliceOffset, slice.data(), kSliceSize) == 0,
            "Slice does not equal source range");
    require(sha256(slice.data() + kBodyOffset, kBodySize) == kBodyDigest, "Routine identity mismatch");
    SparseReplay replay(slice);
    std::size_t cases = 0;
    std::size_t mutationCases = 0;
    std::size_t exceptionCases = 0;
    auto check = [&](float input, State state, const Plan& plan, bool mutation = false) {
      const auto native = replay.run(input, state, plan);
      const auto model = runModel(input, state, plan);
      if (!equal(native, model)) {
        std::ostringstream message;
        message << "Differential mismatch at case " << cases << ", float bits0x"
                << std::hex << std::bit_cast<std::uint32_t>(input)
                << ", native flags=" << native.exceptions << ", model flags=" << model.exceptions
                << ", native events=" << native.events.size() << ", model events=" << model.events.size();
        throw std::runtime_error(message.str());
      }
      ++cases;
      if (mutation) ++mutationCases;
      if (native.exceptions != 0) ++exceptionCases;
    };

    const std::array<std::uint32_t, 19> floatBits = {
        0x00000000, 0x80000000, 0x3f800000, 0xbf800000, 0x42f00000,
        0x00800000, 0x00000001, 0x80000001, 0x7f7fffff, 0xff7fffff,
        0x7f800000, 0xff800000, 0x7fc00000, 0xffc00000, 0x7fc12345,
        0x7f800001, 0xff800001, 0x3f800001, 0x42f00001};
    const std::array<std::uint64_t, 15> doubleBits = {
        0x0000000000000000ULL, 0x8000000000000000ULL, 0x3ff0000000000000ULL,
        0xbff0000000000000ULL, 0x405e000000000000ULL, 0x0000000000000001ULL,
        0x0010000000000000ULL, 0x7fefffffffffffffULL, 0xffefffffffffffffULL,
        0x7ff0000000000000ULL, 0xfff0000000000000ULL, 0x7ff8000000000000ULL,
        0xfff8000000000000ULL, 0x7ff8000000004321ULL, 0x7ff0000000000001ULL};
    const std::array<std::uint8_t, 4> flags = {0, 1, 2, 255};
    const std::array<std::uint32_t, 4> probeResults = {0, 1, 2, UINT32_MAX};
    for (const auto bits : floatBits) {
      const float input = std::bit_cast<float>(bits);
      for (const auto currentBits : doubleBits) {
        for (const auto flag : flags) {
          for (const auto result : probeResults) {
            check(input, {std::bit_cast<double>(currentBits), -17.0, flag, 0x12345678},
                  Plan{.probeResult = result});
          }
        }
      }
      // Equal converted values must suppress enter/apply/leave for all finite
      // values; NaNs still take the unequal branch, including identical payloads.
      const double exact = static_cast<double>(input);
      for (const auto flag : flags) {
        for (const auto result : probeResults) {
          check(input, {exact, -17.0, flag, 0xabcdef01}, Plan{.probeResult = result});
        }
      }
    }

    const std::array<Plan, 7> mutationPlans = {
        Plan{.probeResult = 1, .probeChangesA70 = true, .probeA70 = 120.0},
        Plan{.probeResult = 1, .probeChangesA70 = true, .probeA70 = 121.0},
        Plan{.probeResult = 1, .probeChangesA80 = true, .probeA80 = 91.25},
        Plan{.probeResult = 1, .enterChangesA80 = true, .enterA80 = 88.5},
        Plan{.probeResult = 1, .enterChangesPointer = true, .enterPointer = 0x2222},
        Plan{.probeResult = 1, .applyChangesPointer = true, .applyPointer = 0x3333},
        Plan{.probeResult = 1, .probeChangesA70 = true, .probeA70 = -0.0,
             .probeChangesA80 = true, .probeA80 = -0.0,
             .enterChangesA80 = true, .enterA80 = 75.0,
             .enterChangesPointer = true, .enterPointer = 0x4444,
             .applyChangesPointer = true, .applyPointer = 0x5555}};
    for (const auto bits : floatBits) {
      for (const auto& plan : mutationPlans) {
        check(std::bit_cast<float>(bits), {119.0, -17.0, 1, 0x1111}, plan, true);
      }
    }
    std::mt19937_64 random(0x54454d504f474154ULL);
    for (std::size_t iteration = 0; iteration < 10'000; ++iteration) {
      check(std::bit_cast<float>(static_cast<std::uint32_t>(random())),
            {std::bit_cast<double>(random()), std::bit_cast<double>(random()),
             flags[iteration % flags.size()], static_cast<std::uintptr_t>(random())},
            Plan{.probeResult = probeResults[iteration % probeResults.size()]});
    }

    std::ostringstream stats;
    stats << "{\n  \"status\": \"passed\",\n  \"architecture\": \"arm64\",\n"
          << "  \"source_sha256\": \"" << kSourceDigest << "\",\n"
          << "  \"slice_sha256\": \"" << kSliceDigest << "\",\n"
          << "  \"body_sha256\": \"" << kBodyDigest << "\",\n"
          << "  \"original_body_bytes\": " << kBodySize << ",\n"
          << "  \"total_cases\": " << cases << ",\n"
          << "  \"callback_mutation_cases\": " << mutationCases << ",\n"
          << "  \"floating_exception_cases\": " << exceptionCases << ",\n"
          << "  \"reserved_bytes\": " << replay.reservationSize() << ",\n"
          << "  \"page_size\": " << replay.pageSize() << ",\n"
          << "  \"code_pages\": " << replay.codePageCount() << ",\n"
          << "  \"data_pages\": " << replay.dataPageCount() << ",\n"
          << "  \"external_calls_stubbed\": 4,\n"
          << "  \"original_body_unchanged\": true,\n"
          << "  \"original_engine_loaded_or_initialized\": false,\n"
          << "  \"limitations\": [\"Only the reviewed bounded body executed in sparse anonymous memory with four stub callbacks and synthetic globals. No engine, UI, audio, concurrency or full tempo implementation equivalence is established. Floating exception tests used masked/default macOS arm64 floating-point environment.\"]\n}\n";
    std::ofstream output(argv[3]);
    require(output.good(), "Cannot open stats destination");
    output << stats.str();
    require(output.good(), "Cannot save stats");
    std::cout << stats.str();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
