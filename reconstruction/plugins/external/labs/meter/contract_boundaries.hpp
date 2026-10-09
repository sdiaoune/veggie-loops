#pragma once
// Own source-contract fixture only. Expected ordinates are hand-derived from
// the declared 999-cell grid and dyadic cell values, never from candidate code.
#include <algorithm>
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstring>
#include <limits>
#include <stdexcept>

namespace meter_contract_v2 {
using namespace vl::labs::meter;
struct Counts { unsigned lookups = 0, builds = 0, states = 0, atomics = 0; };
inline void check(bool ok, const char *message) {
  if (!ok) throw std::runtime_error(message);
}
inline bool bytes_equal(const State &a, const State &b) {
  return std::memcmp(&a, &b, sizeof a) == 0;
}
template <class T> struct Guarded {
  std::array<unsigned char, 16> before{};
  T value{};
  std::array<unsigned char, 16> after{};
  Guarded() { before.fill(0x35); after.fill(0xa7); }
  bool intact() const {
    return std::all_of(before.begin(), before.end(), [](auto v) { return v == 0x35; }) &&
           std::all_of(after.begin(), after.end(), [](auto v) { return v == 0xa7; });
  }
};
inline float f(std::uint32_t bits) { return std::bit_cast<float>(bits); }
inline void word(State &s, std::size_t offset, std::uint32_t bits) {
  // Every chosen offset is an actual live float field in the declared State.
  std::memcpy(reinterpret_cast<unsigned char *>(&s) + offset, &bits, sizeof bits);
}

inline Counts run() {
  check(std::fegetround() == FE_TONEAREST, "Source-contract round-to-nearest precondition differs");
  Counts counts{};
  Guarded<Transfer> cell{};
  cell.value.fill(.375f);
  cell.value.front() = .125f; cell.value.back() = .875f;
  cell.value[249] = .75f; cell.value[250] = .25f;
  cell.value[499] = .875f; cell.value[500] = .125f;
  cell.value[749] = .125f; cell.value[750] = .875f;
  const Transfer table_before = cell.value;
  // .25 -> index249 + .75, .5 -> index499 + .5, .75 -> index749 + .25.
  // nextbelow(.5): scaled499.5-2^-15, output .5+3*2^-17 (0x3f000180).
  // nextabove(.5): scaled499.5+2^-14, output .5-3*2^-16 (0x3efffa00).
  // nextbelow(1): scaled999-2^-14, output .875-2^-15 (0x3f5ffe00).
  constexpr std::array<std::array<std::uint32_t, 2>, 14> pairs{{
      {0xc0000000, 0x3e000000}, {0x80000001, 0x3e000000},
      {0x80000000, 0x3e000000}, {0x00000000, 0x3e000000},
      {0x00000001, 0x3e000000}, {0x3e800000, 0x3ec00000},
      {0x3f000000, 0x3f000000}, {0x3f400000, 0x3ea00000},
      {0x3effffff, 0x3f000180}, {0x3f000001, 0x3efffa00},
      {0x3f7fffff, 0x3f5ffe00}, {0x3f800000, 0x3f600000},
      {0x3f800001, 0x3f600000}, {0x40000000, 0x3f600000}}};
  for (const auto &pair : pairs) {
    Guarded<float> out; out.value = 123.0f;
    check(lookup(f(pair[0]), cell.value, out.value), "Caller-table valid lookup rejected");
    check(std::bit_cast<std::uint32_t>(out.value) == pair[1], "Caller-table lookup/ULP bits differ");
    check(out.intact() && cell.intact() &&
          !std::memcmp(cell.value.data(), table_before.data(), sizeof table_before),
          "Lookup guard/input storage changed");
    ++counts.lookups;
  }
  auto zero_table = cell.value; zero_table.front() = f(0x80000000);
  for (std::uint32_t input : {0x00000000u, 0x80000000u}) {
    float out = 123.0f;
    check(lookup(f(input), zero_table, out) && std::bit_cast<std::uint32_t>(out) == 0x80000000,
          "Signed-zero lower endpoint representation differs");
    ++counts.lookups;
  }

  Guarded<std::array<double, 100>> thresholds;
  thresholds.value.fill(1.0);
  for (std::size_t i = 0; i < 10; ++i) thresholds.value[i] = 0.0;
  const double third = static_cast<double>(f(0x3eaaaaab));
  const double two_thirds = static_cast<double>(f(0x3f2aaaab));
  for (std::size_t i = 10; i < 20; ++i) thresholds.value[i] = third;
  for (std::size_t i = 20; i < 90; ++i) thresholds.value[i] = two_thirds;
  const auto threshold_base = thresholds.value;
  // The first <= threshold determines step: 0,10,20,90 respectively.
  // Rational ordinates independently rounded to binary32:
  // 10/99=0x3dcede62, 20/99=0x3e4ede62, 90/99=0x3f68ba2f.
  constexpr std::array<std::size_t, 7> rows{0, 332, 333, 334, 666, 667, 999};
  constexpr std::array<std::uint32_t, 7> base_bits{
      0x00000000, 0x3dcede62, 0x3dcede62, 0x3e4ede62,
      0x3e4ede62, 0x3f68ba2f, 0x3f68ba2f};
  for (unsigned variant = 0; variant < 4; ++variant) {
    thresholds.value = threshold_base;
    if (variant == 1 || variant == 2) {
      const double adjusted = std::nextafter(third,
          variant == 1 ? -std::numeric_limits<double>::infinity()
                       : std::numeric_limits<double>::infinity());
      for (std::size_t i = 10; i < 20; ++i) thresholds.value[i] = adjusted;
    } else if (variant == 3) {
      for (std::size_t i = 0; i < 10; ++i) thresholds.value[i] = -0.0;
    }
    const auto input_before = thresholds.value;
    Guarded<Transfer> output; output.value.fill(.75f);
    check(build_transfer(thresholds.value, output.value), "Repeated-threshold valid build rejected");
    for (std::size_t i = 0; i < rows.size(); ++i) {
      const auto bits = variant == 1 && rows[i] == 333 ? 0x3e4ede62u : base_bits[i];
      check(std::bit_cast<std::uint32_t>(output.value[rows[i]]) == bits,
            "Repeated-threshold first-match/tie row differs");
    }
    check(thresholds.intact() && output.intact() &&
          !std::memcmp(thresholds.value.data(), input_before.data(), sizeof input_before),
          "Transfer build guard/input changed");
    ++counts.builds;
  }

  State zeros{}; zeros.olderSample = -0.0f; zeros.fastLevel = -0.0f;
  zeros.fastRate = -0.0f; zeros.slowRate = -0.0f; zeros.activityHold = -0.0f;
  zeros.reserved = {0x13, 0x57, 0x9b};
  for (float elapsed : {0.0f, -0.0f}) {
    auto s = zeros; check(advance(s, elapsed) && bytes_equal(s, zeros), "Inactive signed-zero state changed");
    ++counts.states;
  }
  State active{}; active.fastLevel = .75f; active.slowLevel = .25f;
  active.fastRate = .5f; active.slowRate = .25f;
  const auto active_before = active;
  check(advance(active, -0.0f) && bytes_equal(active, active_before), "Active negative-zero elapsed differs");
  ++counts.states;
  auto timer = zeros; timer.activity = 7; timer.activityRemaining = 0.0f;
  auto timer_wanted = timer; timer_wanted.activity = 0;
  check(advance(timer, 0.0f) && bytes_equal(timer, timer_wanted), "Negative-zero activity hold clear differs");
  ++counts.states;
  auto history = zeros; auto history_wanted = history;
  history_wanted.olderSample = 0.0f; history_wanted.previousSample = -0.0f;
  check(push_sample(history, -0.0f, zero_table) && bytes_equal(history, history_wanted),
        "Signed-zero history/tie representation differs");
  ++counts.states;
  for (const auto sample_bits : {0x3f7fffffu, 0x3f800001u}) {
    State s{}; s.fastHold = .5f; s.slowHold = .25f; s.activityHold = .75f;
    State wanted = s; wanted.previousSample = f(sample_bits);
    wanted.fastLevel = wanted.slowLevel = f(sample_bits == 0x3f7fffff ? 0x3f5ffe00 : 0x3f600000);
    wanted.fastRemaining = .5f; wanted.slowRemaining = .25f;
    if (sample_bits > 0x3f800000) { wanted.activity = 1; wanted.activityRemaining = .75f; }
    check(push_sample(s, f(sample_bits), cell.value) && bytes_equal(s, wanted),
          "Current-sample one-ULP activity boundary differs");
    ++counts.states;
  }
  State equal_hold{}; equal_hold.fastLevel = 1.0f; equal_hold.fastRate = .5f;
  equal_hold.slowLevel = .5f; equal_hold.slowRate = .25f;
  equal_hold.fastRemaining = equal_hold.slowRemaining = .5f;
  equal_hold.activity = 7; equal_hold.activityHold = .5f; equal_hold.activityRemaining = .5f;
  auto hold_wanted = equal_hold;
  hold_wanted.fastRemaining = hold_wanted.slowRemaining = hold_wanted.activityRemaining = 0.0f;
  check(advance(equal_hold, .5f) && bytes_equal(equal_hold, hold_wanted), "Exact hold crossing changed this-call levels/activity");
  ++counts.states;
  hold_wanted.activity = 0;
  check(advance(equal_hold, 0.0f) && bytes_equal(equal_hold, hold_wanted), "Next-call zero elapsed activity clear differs");
  ++counts.states;

  constexpr std::array<std::size_t, 12> field_offsets{0,4,8,12,16,20,24,28,32,36,44,48};
  for (auto offset : field_offsets) for (auto bad : {0x7f800000u,0xff800000u,0x7fc00000u,0x44800001u}) {
    Guarded<State> s; s.value.reserved = {0x13,0x57,0x9b}; word(s.value, offset, bad);
    const State before = s.value;
    check(!push_sample(s.value, .5f, cell.value) && bytes_equal(s.value, before) && s.intact(),
          "Invalid state push changed caller storage"); ++counts.atomics;
    check(!advance(s.value, .5f) && bytes_equal(s.value, before) && s.intact(),
          "Invalid state advance changed caller storage"); ++counts.atomics;
  }
  for (auto offset : {12u,28u}) {
    State s{}; word(s, offset, 0xbf800000); const State before = s;
    check(!push_sample(s, .5f, cell.value) && bytes_equal(s, before), "Negative rate push accepted"); ++counts.atomics;
    check(!advance(s, .5f) && bytes_equal(s, before), "Negative rate advance accepted"); ++counts.atomics;
  }
  for (auto bad : {0x7f800000u,0xff800000u,0x7fc00000u,0x40000001u}) {
    State s{}; const State before = s;
    check(!push_sample(s, f(bad), cell.value) && bytes_equal(s, before), "Invalid sample changed state"); ++counts.atomics;
  }
  for (auto bad : {0xbf800000u,0x42800001u,0x7f800000u,0xff800000u,0x7fc00000u}) {
    State s{}; const State before = s;
    check(!advance(s, f(bad)) && bytes_equal(s, before), "Invalid elapsed changed state"); ++counts.atomics;
  }
  std::array<float,1001> sized{};
  for (std::size_t count : {0u,1u,999u,1001u}) {
    float out = 123.0f;
    check(!lookup(.5f, std::span<const float>(sized.data(), count), out) && out == 123.0f,
          "Invalid live table count changed output"); ++counts.atomics;
  }
  for (auto bad : {0x7fc00000u,0x7f800000u,0x80000001u,0x3f800001u}) {
    auto table = cell.value; table[19] = f(bad); float out = 123.0f;
    check(!lookup(.5f, table, out) && out == 123.0f, "Invalid table lookup changed output"); ++counts.atomics;
    State s{}; const State before = s;
    check(!push_sample(s, .5f, table) && bytes_equal(s, before), "Invalid table push changed state"); ++counts.atomics;
  }
  auto alias = cell.value; const auto alias_before = alias;
  // Float output is an actual live table element: this overlap test is legal.
  check(!lookup(.5f, alias, alias[499]) && !std::memcmp(alias.data(), alias_before.data(), sizeof alias),
        "Live table/output alias changed storage"); ++counts.atomics;
  for (std::size_t count : {0u,99u}) {
    Transfer output{}; output.fill(.75f); const auto before = output;
    check(!build_transfer(std::span<const double>(threshold_base.data(), count), output) &&
          !std::memcmp(output.data(), before.data(), sizeof output), "Invalid threshold count changed output"); ++counts.atomics;
  }
  for (unsigned bad = 0; bad < 4; ++bad) {
    auto input = threshold_base;
    if (bad == 0) input[19] = std::numeric_limits<double>::quiet_NaN();
    if (bad == 1) input[19] = std::numeric_limits<double>::infinity();
    if (bad == 2) input[19] = 0.0; // decreasing after the repeated positive third
    if (bad == 3) input.fill(.875); // ordered finite values, endpoint1 alone missing
    Transfer output{}; output.fill(.75f); const auto before = output;
    check(!build_transfer(input, output) && !std::memcmp(output.data(), before.data(), sizeof output),
          "Invalid threshold values changed output"); ++counts.atomics;
  }
  check(counts.lookups == 16 && counts.builds == 4 && counts.states == 9 && counts.atomics == 128,
        "Extended source-contract fixture counter differs");
  return counts;
}
} // namespace meter_contract_v2
