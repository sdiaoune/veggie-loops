#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <span>

namespace vl::labs::meter {
// Own caller-managed state, not a reconstructed LABS C++ class. All reads,
// writes and destruction must be serialized; there is no internal lock.
// Valid live readable/writable objects and spans are caller preconditions.
// State floats must be finite with abs<=1024 and both rates nonnegative;
// elapsed must be finite0..64.
// Samples are finite-2..2. Tables contain1000 finite0..1 values; thresholds
// contain100 ordered finite0..1 values and end at1. Signed zeros are allowed.
// Table/output/state storage overlap is rejected where both are arguments.
// Validation is a new-API extension, not native malformed-input behavior.
// Default round-to-nearest, masked traps and ordinary IEEE binary32/64 are
// required. Numerical/native instruction, fusion, flag and class parity are
// unverified; this source uses explicit unfused arithmetic.
struct State {
  float olderSample = 0, previousSample = 0;
  float fastLevel = 0, fastRate = 0, fastHold = 0, fastRemaining = 0;
  float slowLevel = 0, slowRate = 0, slowHold = 0, slowRemaining = 0;
  std::uint8_t activity = 0;
  std::array<std::uint8_t, 3> reserved{};
  float activityHold = 0, activityRemaining = 0;
};
static_assert(sizeof(State) == 52);
static_assert(offsetof(State, fastLevel) == 8);
static_assert(offsetof(State, slowLevel) == 24);
static_assert(offsetof(State, activity) == 40);
static_assert(offsetof(State, activityHold) == 44);
static_assert(offsetof(State, activityRemaining) == 48);
using Transfer = std::array<float, 1000>;

bool build_transfer(std::span<const double> thresholds, Transfer &output) noexcept;
bool lookup(float sample, std::span<const float> table, float &output) noexcept;
bool push_sample(State &state, float sample, std::span<const float> table) noexcept;
bool advance(State &state, float elapsed) noexcept;
} // namespace vl::labs::meter
