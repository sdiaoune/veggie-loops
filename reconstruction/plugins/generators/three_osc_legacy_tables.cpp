#include "three_osc_legacy_tables.hpp"
// Caller owns 6*16384 writable floats; calls do not use shared RNG state.
extern "C" void vl_osc_generate_legacy_tables(float* output) {
  veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(output,6*16384));
}
extern "C" void vl_osc_generate_legacy_noise(std::uint32_t seed,std::uint32_t count,std::uint32_t* output) {
  veggie_loops::three_osc::legacy::NoiseGenerator generator(seed);
  for(std::uint32_t i=0;i<count;++i) output[i]=generator.next();
}
