#include "prepared_lookup.hpp"
#include <bit>
#include <cmath>
#include <cstdint>
#include <limits>
#if defined(__clang__)
#pragma STDC FENV_ACCESS ON
#endif

namespace vl::labs::prepared_lookup {
namespace {
bool overlap(const void *a, std::size_t n, const void *b, std::size_t m) noexcept {
  const auto x = reinterpret_cast<std::uintptr_t>(a);
  const auto y = reinterpret_cast<std::uintptr_t>(b);
  return n && m && (x >= y ? x - y < m : y - x < n);
}
bool sample_ok(float value) noexcept {
  return (std::bit_cast<std::uint32_t>(value) & UINT32_C(0x7fffffff)) <= UINT32_C(0x40000000);
}
bool table_ok(float value) noexcept {
  const auto bits = std::bit_cast<std::uint32_t>(value);
  const auto magnitude = bits & UINT32_C(0x7fffffff);
  return magnitude <= UINT32_C(0x3f800000) &&
         (!(bits & UINT32_C(0x80000000)) || magnitude == 0);
}
}

bool lookup_prepared(float input, std::span<const float> table,
                     float &output) noexcept {
  static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559);
  if (table.empty() || table.size() > maximum_prepared_count || !sample_ok(input) ||
      overlap(&output, sizeof output, table.data(), table.size_bytes())) return false;
  for (float item : table) if (!table_ok(item)) return false;
  const auto count = static_cast<std::uint32_t>(table.size());
  // 0x20d48c..498: signed conversion of wrapping W(count-1), then float multiply.
  // Our bounded positive prepared count makes the subtraction/conversion exact.
  const auto last = static_cast<std::int32_t>(count - 1);
  const float scale = static_cast<float>(last);
  const float scaled = scale * input;
  if (scaled <= 0.0f) { output = table.front(); return true; }
  // 0x20d4ac..4bc recomputes the same scale from stable count.
  if (scaled >= static_cast<float>(last)) { output = table.back(); return true; }
  // 0x20d4c0 and 4d0 use distinct signed integer conversions in GPR/SIMD.
  // This C++ expression models their finite-domain value, not instruction count
  // or exception status. Those differences require later compiled/native proof.
  const auto index = static_cast<std::int32_t>(scaled);
  const auto next = static_cast<std::int64_t>(index) + 1;
  float lower = 0.0f;
  // 0x20d4dc initializes lower+0; unsigned CMP/B.LS skips an invalid load.
  if (static_cast<std::uint32_t>(index) < count)
    lower = table[static_cast<std::size_t>(index)];
  const float integer_value = static_cast<float>(index); // 0x20d4f4
  const float fraction = scaled - integer_value;        // 0x20d500
  float upper = 0.0f;
  // 0x20d508 initializes upper+0, then unsigned guard before the second load.
  if (static_cast<std::uint32_t>(next) < count)
    upper = table[static_cast<std::size_t>(next)];
  const float difference = upper - lower;              // 0x20d520
  output = std::fma(fraction, difference, lower);       // 0x20d524 FMADD S0,S0,S2,S1
  return true;
}
} // namespace vl::labs::prepared_lookup
