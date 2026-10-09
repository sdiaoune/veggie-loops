#include "three_osc_filter_routing.hpp"
using namespace veggie_loops::three_osc;
extern "C" uint8_t vl_osc_filter_route(filter_routing::State* state,const filter_routing::Inputs* inputs,
 const filter::Context* ctx,const float* source,float* output,int frames,float* left,float* right) {
  return uint8_t(filter_routing::process(*state,*inputs,*ctx,source,output,frames,*left,*right));
}
