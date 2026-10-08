#include "three_osc_envelope.hpp"
using namespace veggie_loops::three_osc::envelope;
extern "C" {
void vl_osc_envelope_prepare_curve(Curve* curve,float amount) {prepareCurve(*curve,amount);}
void vl_osc_envelope_prepare_raw_curve(Curve* curve,int amount) {prepareRawCurve(*curve,amount);}
void vl_osc_envelope_initialize(State* state,const Configuration* cfg) {initialize(*state,*cfg);}
void vl_osc_envelope_release(State* state,const Configuration* cfg) {release(*state,*cfg);}
void vl_osc_envelope_step(const Configuration* cfg,State* state) {step(*cfg,*state);}
}
