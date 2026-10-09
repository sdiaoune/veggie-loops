#include "meter.hpp"
#include <bit>
#include <cstring>
#include <limits>
#if defined(__clang__)
#pragma STDC FENV_ACCESS ON
#endif

namespace vl::labs::meter {
namespace {
static_assert(sizeof(float) == 4 && sizeof(double) == 8);
static_assert(std::numeric_limits<float>::is_iec559 && std::numeric_limits<double>::is_iec559);
bool overlap(const void *a, std::size_t n, const void *b, std::size_t m) noexcept {
  const auto x = reinterpret_cast<std::uintptr_t>(a), y = reinterpret_cast<std::uintptr_t>(b);
  return n && m && (x >= y ? x - y < m : y - x < n);
}
bool magnitude(float value, std::uint32_t maximum) noexcept {
  return (std::bit_cast<std::uint32_t>(value) & UINT32_C(0x7fffffff)) <= maximum;
}
bool nonnegative(float value, std::uint32_t maximum) noexcept {
  const auto bits = std::bit_cast<std::uint32_t>(value);
  return (bits & UINT32_C(0x7fffffff)) <= maximum &&
         (!(bits & UINT32_C(0x80000000)) || !(bits & UINT32_C(0x7fffffff)));
}
bool valid(const State &state) noexcept {
  constexpr std::array<std::size_t, 12> positions{0,4,8,12,16,20,24,28,32,36,44,48};
  const auto *bytes = reinterpret_cast<const std::uint8_t *>(&state);
  for (auto position : positions) {
    std::uint32_t bits = 0;
    std::memcpy(&bits, bytes + position, sizeof bits);
    if ((bits & UINT32_C(0x7fffffff)) > UINT32_C(0x44800000)) return false;
    if ((position == 12 || position == 28) && (bits & UINT32_C(0x80000000)) &&
        (bits & UINT32_C(0x7fffffff))) return false;
  }
  return true;
}
bool valid_table(std::span<const float> table) noexcept {
  if (table.size() != 1000) return false;
  for (float value : table) if (!nonnegative(value, UINT32_C(0x3f800000))) return false;
  return true;
}
float interpolate(float sample, std::span<const float> table) noexcept {
  const float scaled = static_cast<float>(table.size() - 1) * sample;
  if (scaled <= 0.0f) return table.front();
  if (scaled >= static_cast<float>(table.size() - 1)) return table.back();
  const auto index = static_cast<std::size_t>(scaled);
  const float distance = table[index + 1] - table[index];
  const float fraction = scaled - static_cast<float>(index);
  const float product = distance * fraction;
  return table[index] + product;
}
void decay(float &level, float rate, float &remaining, float elapsed) noexcept {
  if (remaining > 0.0f) {
    const float consumed = elapsed <= remaining ? elapsed : remaining;
    remaining = remaining - consumed;
  } else {
    const float amount = elapsed * rate;
    const float reduced = level - amount;
    level = reduced <= 0.0f ? 0.0f : reduced;
  }
}
} // namespace

bool build_transfer(std::span<const double> thresholds, Transfer &output) noexcept {
  if (thresholds.size() != 100 || overlap(thresholds.data(), thresholds.size_bytes(), &output, sizeof output)) return false;
  std::uint64_t previous = 0;
  for (double threshold : thresholds) {
    const auto bits = std::bit_cast<std::uint64_t>(threshold);
    const auto key = bits & UINT64_C(0x7fffffffffffffff);
    if (key > UINT64_C(0x3ff0000000000000) ||
        ((bits & UINT64_C(0x8000000000000000)) && key) || key < previous) return false;
    previous = key;
  }
  if (previous != UINT64_C(0x3ff0000000000000)) return false;
  Transfer next{};
  for (std::size_t sample = 0; sample < next.size(); ++sample) {
    const float normalized = static_cast<float>(sample) / 999.0f;
    std::size_t step = 0;
    while (step < thresholds.size() && static_cast<double>(normalized) > thresholds[step]) ++step;
    // The checked endpoint1 guarantees a matching threshold for all1000 rows.
    next[sample] = static_cast<float>(step) / 99.0f;
  }
  output = next;
  return true;
}
bool lookup(float sample, std::span<const float> table, float &output) noexcept {
  if (table.size() != 1000 || !magnitude(sample, UINT32_C(0x40000000)) ||
      overlap(&output, sizeof output, table.data(), table.size_bytes()) || !valid_table(table)) return false;
  output = interpolate(sample, table);
  return true;
}
bool push_sample(State &state, float sample, std::span<const float> table) noexcept {
  if (table.size() != 1000 || !magnitude(sample, UINT32_C(0x40000000)) || !valid(state) ||
      overlap(&state, sizeof state, table.data(), table.size_bytes()) || !valid_table(table)) return false;
  State next = state;
  // Keep finite comparison tie ordering, including the chosen signed-zero bits.
  float peak = sample <= next.previousSample ? next.previousSample : sample;
  const float olderPeak = sample <= next.olderSample ? next.olderSample : sample;
  if (next.previousSample <= next.olderSample) peak = olderPeak;
  const float mapped = interpolate(peak, table);
  next.olderSample = next.previousSample;
  next.previousSample = sample;
  if (sample > 1.0f) { next.activity = 1; next.activityRemaining = next.activityHold; }
  if (next.fastLevel < mapped) { next.fastLevel = mapped; next.fastRemaining = next.fastHold; }
  if (next.slowLevel < next.fastLevel) { next.slowLevel = next.fastLevel; next.slowRemaining = next.slowHold; }
  state = next;
  return true;
}
bool advance(State &state, float elapsed) noexcept {
  if (!nonnegative(elapsed, UINT32_C(0x42800000)) || !valid(state)) return false;
  State next = state;
  // Both channels advance whenever either level is positive.
  if (next.fastLevel > 0.0f || next.slowLevel > 0.0f) {
    decay(next.fastLevel, next.fastRate, next.fastRemaining, elapsed);
    decay(next.slowLevel, next.slowRate, next.slowRemaining, elapsed);
  }
  if (next.activity && next.activityHold >= 0.0f) {
    if (next.activityRemaining <= 0.0f) next.activity = 0;
    else {
      const float consumed = elapsed <= next.activityRemaining ? elapsed : next.activityRemaining;
      next.activityRemaining = next.activityRemaining - consumed;
    }
  }
  state = next;
  return true;
}
} // namespace vl::labs::meter
