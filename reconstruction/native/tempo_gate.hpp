#pragma once

#include <bit>
#include <cfenv>
#include <cstdint>

namespace veggie_loops::tempo_gate {

// Independent reconstruction of the bounded arm64 routine at 0x4a7cc0.
// Labels retain source offsets because the globals' wider meanings are unknown.
// The four callbacks are supplied by the caller; no FL Studio runtime is used.
struct State {
  double valueA70 = 0.0;  // Source global 0x167da70, read after probe.
  double valueA80 = 0.0;  // Source global 0x167da80, initially written every call.
  std::uint8_t byteFlag = 0;  // Source global 0x18d7ed6.
  std::uintptr_t opaquePointer = 0;  // Source global 0x19b4848.
};

inline bool hasNaNBits(double value) noexcept {
  const auto bits = std::bit_cast<std::uint64_t>(value);
  return (bits & 0x7ff0000000000000ULL) == 0x7ff0000000000000ULL &&
         (bits & 0x000fffffffffffffULL) != 0;
}

template <typename Callbacks>
void update(State& state, float input, Callbacks& callbacks) {
  const double converted = static_cast<double>(input);
  state.valueA80 = converted;
  if (state.byteFlag == 0) return;
  if (static_cast<std::uint32_t>(callbacks.probe()) == 0) return;

  // The native FCMPE comparison raises invalid for either quiet or signaling
  // NaNs, and takes the unequal branch. Preserve that masked exception flag.
  if (hasNaNBits(state.valueA70) || hasNaNBits(converted)) {
    std::feraiseexcept(FE_INVALID);
  }
  if (state.valueA70 == converted) return;

  callbacks.enter(state.opaquePointer);
  callbacks.apply(state.valueA80, std::uint32_t{1});
  callbacks.leave(state.opaquePointer);
}

}  // namespace veggie_loops::tempo_gate
