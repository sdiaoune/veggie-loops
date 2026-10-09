#include "three_osc_filter.hpp"
using namespace veggie_loops::three_osc::filter;
extern "C" void vl_osc_filter_single_coefficients(float cutoff,float resonance,const Context* ctx,Coefficients* cfg) {singleCoefficients(cutoff,resonance,*ctx,*cfg);}
extern "C" void vl_osc_filter_biquad_coefficients(float cutoff,float resonance,const Context* ctx,Coefficients* cfg) {biquadCoefficients(cutoff,resonance,*ctx,*cfg);}
extern "C" void vl_osc_filter_special_coefficients(float cutoff,float resonance,const Context* ctx,Coefficients* cfg) {specialCoefficients(cutoff,resonance,*ctx,*cfg);}
extern "C" void vl_osc_filter_single_render(float cutoff,float increment,Coefficients* cfg,const Context* ctx,const float* source,float* output,int frames) {singleRender(cutoff,increment,*cfg,*ctx,source,output,frames);}
extern "C" void vl_osc_filter_biquad_render(const Coefficients* cfg,std::array<float,8>* state,const float* source,float* output,int frames) {biquadRender(*cfg,*state,source,output,frames);}
extern "C" void vl_osc_filter_special_render(const Coefficients* cfg,std::array<float,8>* state,const Context* ctx,const float* source,float* output,int frames) {specialRender(*cfg,*state,*ctx,source,output,frames);}
