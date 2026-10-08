#include "three_osc_envelope_coefficients.hpp"
using namespace veggie_loops::three_osc::envelope;
extern "C" void vl_osc_envelope_prepare_configuration(Configuration* cfg,double tempo,
                                                     std::uint32_t clockSetting,const float* const* tables) {
  prepareConfiguration(*cfg,tempo,clockSetting,{tables[0],tables[1],tables[2]});
}
