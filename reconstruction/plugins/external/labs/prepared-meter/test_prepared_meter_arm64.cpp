#if !defined(__APPLE__) || !defined(__aarch64__)
#error "This proposed FPCR-checked numerical fixture requires macOS arm64."
#endif
#include "prepared_meter.hpp"
#include <array>
#include <bit>
#include <cfenv>
#include <cstdint>
#include <cstdio>
#include <initializer_list>

static bool check(bool value, const char *label) {
  if (!value) std::fprintf(stderr, "FAIL:%s\n", label);
  return value;
}
static float number(std::uint32_t word) { return std::bit_cast<float>(word); }
static std::uint32_t bits(float value) { return std::bit_cast<std::uint32_t>(value); }
int main() {
  std::uint64_t fpcr = 0;
  asm volatile("mrs %0, fpcr" : "=r"(fpcr));
  constexpr std::uint64_t incompatible = (UINT64_C(3) << 22) | (UINT64_C(1) << 24) |
      (UINT64_C(1) << 19) | (UINT64_C(31) << 8) | (UINT64_C(1) << 15);
  if (!check(std::fegetround() == FE_TONEAREST && !(fpcr & incompatible), "FP_environment")) return 1;
  using namespace vl::labs::prepared_meter;
  Transfer table{};
  table[278] = number(0x3e4a5d14); table[279] = number(0x3f3fa563);
  float output = -1.0f;
  if (!check(lookup(number(0x3e8e9049), table, output) && bits(output) == 0x3e940ad7,
             "synthetic_fused_lookup")) return 1;
  State state{};
  state.fastLevel = number(0x3f5212de); state.fastRate = number(0x3f685bcc);
  const float elapsed = number(0x3e3ae4bb);
  if (!check(advance(state, elapsed) && bits(state.fastLevel) == 0x3f27aa4b,
             "synthetic_fused_decay")) return 1;
  volatile float rounded_product = number(0x3f685bcc) * elapsed;
  volatile float separated = number(0x3f5212de) - rounded_product;
  if (!check(bits(separated) == 0x3f27aa4a, "separated_decay_witness")) return 1;
  State holding{}; holding.fastLevel = 0.75f; holding.fastRate = 1.0f; holding.fastRemaining = 0.25f;
  if (!check(advance(holding, 0.5f) && holding.fastLevel == 0.75f && bits(holding.fastRemaining) == 0,
             "hold_has_no_same_call_residual_decay")) return 1;
  State clamp{}; clamp.fastLevel = 0.25f; clamp.fastRate = 1.0f;
  if (!check(advance(clamp, 1.0f) && bits(clamp.fastLevel) == 0, "finite_negative_clamp_positive_zero")) return 1;
  for (std::uint32_t level_sign : {UINT32_C(0), UINT32_C(0x80000000)})
    for (std::uint32_t rate_sign : {UINT32_C(0), UINT32_C(0x80000000)})
      for (std::uint32_t elapsed_sign : {UINT32_C(0), UINT32_C(0x80000000)}) {
        State zero{}; zero.fastLevel = number(level_sign); zero.fastRate = number(rate_sign); zero.slowLevel = 1.0f;
        zero.reserved = {0xa5, 0x5a, 0xc3}; const auto reserved = zero.reserved;
        if (!check(advance(zero, number(elapsed_sign)) && bits(zero.fastLevel) == 0 &&
                   zero.slowLevel == 1.0f && zero.reserved == reserved,
                   "finite_signed_zero_clamp_with_positive_peer")) return 1;
      }
  std::printf("{\"own_source_checks_passed\":13,\"fpcr\":%llu,\"original_called\":false,\"full\":false}\n",
              static_cast<unsigned long long>(fpcr));
  return 0;
}
