// Independent caller-side memory checks for the documented DSP subsets.
// No original binary body, factory, preset or commercial resource is loaded.
#include "../effects/balance_dsp.hpp"
#include "../generators/three_osc.hpp"
#include <array>
#include <cstdint>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

void check(bool condition) {
  if (!condition) throw std::runtime_error("Independent model boundary check failed");
}

int main() {
  using namespace veggie_loops;
  for (const std::int32_t frames : {0, 1, 2, 7, 8, 9, 31, 32, 33, 1024, 8192}) {
    std::vector<float> input(static_cast<std::size_t>(frames) * 2 + 4, 0.25f);
    std::vector<float> output(input.size(), 42.0f);
    balance::State state{};
    state.current = {1, 1, 0, 0}; state.target = {1, 1, 0, 0};
    balance::process(state, input.data() + 1, output.data() + 1, frames, 0.01f, 0x1p-24f);
    check(output.front() == 42);
    check(output[static_cast<std::size_t>(frames) * 2 + 1] == 42);
    for (std::int32_t frame = 0; frame < frames; ++frame) {
      check(output[static_cast<std::size_t>(frame) * 2 + 1] == 0.25f);
      check(output[static_cast<std::size_t>(frame) * 2 + 2] == 0.25f);
    }
    balance::process(state, input.data() + 1, input.data() + 1, frames, 0.01f, 0x1p-24f);
    check(input.front() == 0.25f && input.back() == 0.25f);
  }

  std::array<std::vector<float>, 2> storage;
  for (auto& data : storage) data.resize(32770, 0.5f);
  std::array<float*, 2> tablePointers{storage[0].data(), storage[1].data()};
  std::array<std::int32_t, 2> sizes{32768, 32768};
  three_osc::MipMap map{2, 0, tablePointers.data(), sizes.data()};
  std::array<three_osc::MipMap*, 4> maps{&map, &map, &map, &map};
  three_osc::WaveTable factory{4, 0, maps.data()};
  three_osc::WaveTable custom{1, 0, maps.data()};
  three_osc::OscState state{};
  state.custom = custom;
  state.phaseIncrement = 0.01;
  state.lowerTable = storage[0].data();
  // This boundary needs two readable wrap samples after the 32768-point table.
  check(three_osc::processWave(state, 1.0f) == 0.5f);
  for (const std::int32_t waveform : {0, 1, 2, 3, 4, 5, 6}) {
    for (const std::uint32_t frames : {0u, 1u, 7u, 8u, 9u, 128u}) {
      std::vector<float> output(static_cast<std::size_t>(frames) * 2 + 2, 0.25f);
      three_osc::Runtime runtime{waveform == 6 ? nullptr : &factory, 123};
      const auto phase = std::numeric_limits<std::uint32_t>::max();
      const auto returned = three_osc::addOsc(state, runtime, waveform, output.data(), frames,
                                             0.5f, phase, 8000000, false);
      check(returned == phase + frames * 8000000u);
      for (std::uint32_t frame = 0; frame < frames; ++frame)
        check(output[static_cast<std::size_t>(frame) * 2 + 1] == 0.25f);
      check(output[static_cast<std::size_t>(frames) * 2] == 0.25f);
      check(output[static_cast<std::size_t>(frames) * 2 + 1] == 0.25f);
    }
  }
  std::cout << "Independent documented-domain model boundary checks passed\n";
}
