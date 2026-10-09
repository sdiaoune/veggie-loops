// Synthetic own-source numerical checks; measured test platform: macOS arm64.
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "This FPCR witness requires a macOS arm64 executable."
#endif
#include "prepared_lookup.hpp"
#include <array>
#include <bit>
#include <cfenv>
#include <cstdint>
#include <cstdio>
#include <limits>

static bool check(bool value, const char *name) {
  if (!value) std::fprintf(stderr, "FAIL:%s\n", name);
  return value;
}

int main() {
  std::uint64_t fpcr = 0;
  asm volatile("mrs %0, fpcr" : "=r"(fpcr));
  constexpr std::uint64_t incompatible = (UINT64_C(3) << 22) |
      (UINT64_C(1) << 24) | (UINT64_C(1) << 19) |
      (UINT64_C(31) << 8) | (UINT64_C(1) << 15);
  if (!check(std::fegetround() == FE_TONEAREST && !(fpcr & incompatible),
             "own_process_numeric_environment")) return 1;
  using vl::labs::prepared_lookup::lookup_prepared;
  auto bits = [](float x) { return std::bit_cast<std::uint32_t>(x); };
  auto number = [](std::uint32_t x) { return std::bit_cast<float>(x); };
  std::array<float, 1000> table{};
  table[278] = number(UINT32_C(0x3e4a5d14));
  table[279] = number(UINT32_C(0x3f3fa563));
  const float sample = number(UINT32_C(0x3e8e9049));
  float result = -1.0f;
  if (!check(lookup_prepared(sample, table, result) &&
             bits(result) == UINT32_C(0x3e940ad7), "fused_rational_witness")) return 1;
  const auto fused_bits = bits(result);
  const float scaled = 999.0f * sample;
  const float fraction = scaled - 278.0f;
  const float difference = table[279] - table[278];
  const float product = fraction * difference;
  const float separate = table[278] + product;
  if (!check(bits(separate) == UINT32_C(0x3e940ad6), "separated_rational_witness")) return 1;
  const std::array<float, 2> endpoints{number(UINT32_C(0x80000000)), 1.0f};
  if (!check(lookup_prepared(0.0f, endpoints, result) &&
             bits(result) == UINT32_C(0x80000000), "signed_zero_endpoint")) return 1;
  if (!check(lookup_prepared(-2.0f, endpoints, result) &&
             bits(result) == UINT32_C(0x80000000), "negative_input_maps_first")) return 1;
  if (!check(lookup_prepared(2.0f, endpoints, result) && result == 1.0f,
             "upper_endpoint")) return 1;
  const std::array<float, 1> singleton{0.75f};
  if (!check(lookup_prepared(0.5f, singleton, result) && result == 0.75f,
             "singleton_table")) return 1;
  result = 0.25f;
  if (!check(!lookup_prepared(std::numeric_limits<float>::infinity(), endpoints, result) &&
             result == 0.25f, "nonfinite_rejection_preserves_output")) return 1;
  const std::array<float, 2> invalid{0.0f, std::numeric_limits<float>::quiet_NaN()};
  if (!check(!lookup_prepared(0.5f, invalid, result) && result == 0.25f,
             "invalid_table_rejection_preserves_output")) return 1;
  if (!check(!lookup_prepared(0.5f, table, table[278]) &&
             bits(table[278]) == UINT32_C(0x3e4a5d14), "overlap_rejection_preserves_table")) return 1;
  std::printf("{\"own_source_checks_passed\":9,\"own_process_fpcr\":%llu,"
              "\"fused_bits\":\"0x%08x\",\"separate_bits\":\"0x%08x\","
              "\"original_plugin_called\":false,\"full_plugin_equivalence\":false}\n",
              static_cast<unsigned long long>(fpcr), fused_bits, bits(separate));
  return 0;
}
