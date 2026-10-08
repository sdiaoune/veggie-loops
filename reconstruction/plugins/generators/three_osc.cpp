#include "three_osc.hpp"

// A small independently compiled C ABI for the reconstructed component.
// This library does not claim VST/AU compatibility or complete plugin parity.
extern "C" {
void vl_three_osc_set_sample_rate(veggie_loops::three_osc::OscState* state,
                                double rate) {
  veggie_loops::three_osc::setSampleRate(*state, rate);
}
double vl_three_osc_phase_to_pitch(const veggie_loops::three_osc::OscState* state,
                                 double increment) {
  return veggie_loops::three_osc::phaseAddToPitch(*state, increment);
}
float vl_three_osc_process_wave(const veggie_loops::three_osc::OscState* state,
                               float phase) {
  return veggie_loops::three_osc::processWave(*state, phase);
}
std::uintptr_t vl_three_osc_render(
    veggie_loops::three_osc::OscState* state,
    veggie_loops::three_osc::Runtime* runtime, std::int32_t opcode,
    const veggie_loops::three_osc::RenderArguments* arguments) {
  return veggie_loops::three_osc::dispatchRender(*state, *runtime, opcode, *arguments);
}
}
