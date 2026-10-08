#pragma once

#include <cstdint>

namespace veggie_loops {

// Independent reconstruction of the standalone launcher's capability callback.
// Evidence: analysis/native/launcher/host-dispatcher2-instructions.json.
// This answers host capability requests; it does not implement an audio engine.
struct VeggieLoopsHost final {
  static constexpr std::int64_t dispatch(std::int64_t command,
                                         std::int64_t index,
                                         std::int64_t /* value */) noexcept {
    return command == 3 && static_cast<std::uint32_t>(index) < 2 ? 1 : 0;
  }

  // The 32-bit callback sign-extends its inputs before calling Dispatcher2 and
  // preserves only the low 32 bits of that callback's result.
  static constexpr std::uint32_t dispatchLegacy(std::int32_t command,
                                               std::int32_t index,
                                               std::int32_t value) noexcept {
    return static_cast<std::uint32_t>(dispatch(command, index, value));
  }
};

}  // namespace veggie_loops
