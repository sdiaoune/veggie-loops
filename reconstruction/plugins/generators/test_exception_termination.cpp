#include <CommonCrypto/CommonDigest.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native body replay requires the reviewed macOS arm64 slice"
#endif
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>

#include <array>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <exception>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace {
void require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
std::vector<std::uint8_t> read(const char* path) {
  std::ifstream input(path, std::ios::binary); require(input.good(), "Cannot read helper image");
  return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
std::string hash(const std::uint8_t* input, std::size_t length) {
  std::array<unsigned char, 32> digest;
  CC_SHA256(input, static_cast<CC_LONG>(length), digest.data());
  std::ostringstream output;
  for (auto byte : digest) output << std::hex << std::setfill('0') << std::setw(2) << unsigned(byte);
  return output.str();
}
struct Event { std::uint64_t kind, argument; bool operator==(const Event&) const = default; };
int eventDescriptor = -1;
extern "C" void* beginCatchCapture(void* value) {
  const Event event{1, reinterpret_cast<std::uintptr_t>(value)};
  (void)::write(eventDescriptor, &event, sizeof(event)); return value;
}
[[noreturn]] void terminationCapture() {
  const Event event{2, 0}; (void)::write(eventDescriptor, &event, sizeof(event)); _Exit(91);
}

class Replay {
 public:
  Replay(const std::vector<std::uint8_t>& image, std::size_t offset, std::size_t length)
      : offset_(offset) {
    require(offset + length <= image.size(), "Helper image range invalid");
    std::vector<std::size_t> calls;
    for (std::size_t i = 0; i < length; i += 4) {
      std::uint32_t instruction; std::memcpy(&instruction, image.data() + offset + i, 4);
      if ((instruction & 0xfc000000u) == 0x94000000u) {
        auto immediate = static_cast<std::int32_t>((instruction & 0x03ffffffu) << 6) >> 6;
        calls.push_back(offset + i + static_cast<std::int64_t>(immediate) * 4);
      }
    }
    require(calls.size() == 2, "Helper must contain begin_catch then terminate calls");
    const auto page = static_cast<std::size_t>(sysconf(_SC_PAGESIZE));
    require(page == 16384, "Reviewed replay requires macOS arm64 16K pages");
    const auto maximum = std::max(offset + length, std::max(calls[0], calls[1]) + 16);
    size_ = (maximum + page - 1) / page * page;
    base_ = static_cast<std::uint8_t*>(mmap(nullptr, size_, PROT_READ | PROT_WRITE,
                                          MAP_PRIVATE | MAP_ANON, -1, 0));
    require(base_ != MAP_FAILED, "Cannot map helper replay");
    std::memcpy(base_ + offset, image.data() + offset, length);
    thunk(calls[0], 0x1000, reinterpret_cast<void*>(&beginCatchCapture));
    thunk(calls[1], 0x1020, reinterpret_cast<void*>(&std::terminate));
    require(mprotect(base_, size_, PROT_READ | PROT_EXEC) == 0, "Cannot protect helper replay");
    sys_icache_invalidate(base_, size_);
    require(std::memcmp(base_ + offset, image.data() + offset, length) == 0,
            "Original helper body changed");
  }
  ~Replay() { munmap(base_, size_); }
  void run(void* value) const { reinterpret_cast<void (*)(void*)>(base_ + offset_)(value); }
 private:
  void thunk(std::size_t stub, std::size_t body, void* destination) {
    const auto delta = static_cast<std::int32_t>(body) - static_cast<std::int32_t>(stub);
    const std::uint32_t branch = 0x14000000u | ((delta / 4) & 0x03ffffffu);
    std::memcpy(base_ + stub, &branch, 4);
    const std::array<std::uint32_t, 2> instructions{0x58000050, 0xd61f0200};
    std::memcpy(base_ + body, instructions.data(), 8);
    const auto address = reinterpret_cast<std::uintptr_t>(destination);
    std::memcpy(base_ + body + 8, &address, 8);
  }
  std::uint8_t* base_ = nullptr;
  std::size_t offset_, size_;
};
struct Result { int status; std::vector<Event> events; };
Result isolated(const Replay& replay, std::uintptr_t argument, bool custom) {
  int descriptors[2]; require(pipe(descriptors) == 0, "Cannot create observation pipe");
  const pid_t child = fork(); require(child >= 0, "Cannot fork isolated helper test");
  if (child == 0) {
    close(descriptors[0]); eventDescriptor = descriptors[1];
    const rlimit noCore{0, 0}; (void)setrlimit(RLIMIT_CORE, &noCore);
    const int quiet = open("/dev/null", O_WRONLY);
    if (quiet >= 0) { dup2(quiet, STDERR_FILENO); close(quiet); }
    if (custom) std::set_terminate(terminationCapture);
    replay.run(reinterpret_cast<void*>(argument)); _Exit(92);
  }
  close(descriptors[1]); Result result{};
  Event event;
  while (::read(descriptors[0], &event, sizeof(event)) == sizeof(event)) result.events.push_back(event);
  close(descriptors[0]); require(waitpid(child, &result.status, 0) == child, "Cannot collect helper subprocess");
  return result;
}
}

int main(int argc, char** argv) {
  try {
    require(argc == 5, "Usage: test_exception_termination <private native slice> <rebuilt dylib> <compiler-helper offset> <report.json>");
    const auto native = read(argv[1]), compiled = read(argv[2]);
    require(hash(native.data(), native.size()) == "c90d11fe12c86d620aabd135078c7cca49cc2b007b0c750e0db63a1e7508db48",
            "Native helper slice identity mismatch");
    require(hash(native.data() + 0x1fe0, 12) == "ef6c64834a5fda5ee1889c8aed8b9dd61447b3a0aed23d823a1d43dff36a1222",
            "Native termination helper hash mismatch");
    const auto compiledOffset = static_cast<std::size_t>(std::stoull(argv[3], nullptr, 16));
    Replay a(native, 0x1fe0, 12), b(compiled, compiledOffset, 16);
    std::size_t cases = 0;
    for (auto argument : {std::uintptr_t(0), std::uintptr_t(0x1234), UINTPTR_MAX}) {
      const auto original = isolated(a, argument, true), reconstructed = isolated(b, argument, true);
      require(original.status == reconstructed.status && original.events == reconstructed.events,
              "Native/compiler helper observations differ");
      require(WIFEXITED(original.status) && WEXITSTATUS(original.status) == 91 &&
                  original.events == std::vector<Event>{{1, argument}, {2, 0}},
              "Helper did not preserve catch argument then invoke terminate handler");
      ++cases;
    }
    const auto original = isolated(a, 0, false), reconstructed = isolated(b, 0, false);
    require(WIFSIGNALED(original.status) && WTERMSIG(original.status) == SIGABRT &&
                WIFSIGNALED(reconstructed.status) && WTERMSIG(reconstructed.status) == SIGABRT &&
                original.events == reconstructed.events && original.events == std::vector<Event>{{1, 0}},
            "Default standard termination behavior differed"); ++cases;
    std::ostringstream report;
    report << "{\n  \"status\": \"passed\",\n  \"isolated_native_model_pairs\": " << cases
           << ",\n  \"original_helper_bytes\": 12,\n  \"original_body_sha256\": \"ef6c64834a5fda5ee1889c8aed8b9dd61447b3a0aed23d823a1d43dff36a1222\",\n"
           << "  \"compiler_helper_offset\": " << compiledOffset << ",\n"
           << "  \"compiled_library_sha256\": \"" << hash(compiled.data(), compiled.size()) << "\",\n"
           << "  \"begin_catch_argument_and_call_order_match\": true,\n"
           << "  \"real_std_terminate_called\": true,\n  \"default_result\": \"SIGABRT\",\n"
           << "  \"custom_terminate_handler_result\": \"exit91\",\n"
           << "  \"original_body_unchanged\": true,\n  \"full_exception_unwinding_parity\": false,\n"
           << "  \"limitations\": [\"begin_catch is replaced by an observation stub; exception-object layout and unwinding metadata are not compared. Only the helper's call order, argument preservation and real std::terminate behavior are proved. No huge allocations or original FL host/plugin initialization occur.\"]\n}\n";
    std::ofstream output(argv[4]); require(output.good(), "Cannot write helper proof");
    output << report.str(); std::cout << report.str(); return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
