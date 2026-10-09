#include "three_osc_declick.hpp"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <vector>
namespace veggie_loops::three_osc::declick {
void generate(const Curve& curve,int shape,int direction,std::int32_t offset,
              std::int32_t total,float* output,std::int32_t count) {
  const float start=shape==3 ? (direction==1 ? float(offset+1):float(total-offset))
                              : (direction==1 ? float(total-offset):float(offset+1));
  const float step=(shape==3 ? direction==1 : direction!=1) ? 1.0f:-1.0f;
  for(int i=0;i<count;++i)output[i]=std::fma(float(i),step,start);
  const float coefficient=static_cast<float>((shape==3 ? 3.141592653589793:1.0)/double(total+1));
  vDSP_vsmul(output,1,&coefficient,output,1,static_cast<vDSP_Length>(count));
  std::vector<float> temporary(static_cast<std::size_t>(count));
  if(shape==3) {
    vvcosf(temporary.data(),output,&count);
    const float one=1.0f,half=0.5f;
    vDSP_vsadd(temporary.data(),1,&one,output,1,static_cast<vDSP_Length>(count));
    vDSP_vsmul(output,1,&half,output,1,static_cast<vDSP_Length>(count));
  }
  if(std::bit_cast<std::uint32_t>(curve.amount)!=0) {
    if(!std::signbit(curve.amount)) for(int i=0;i<count;++i)output[i]=1.0f-output[i];
    vDSP_vsmul(output,1,&curve.logarithm,output,1,static_cast<vDSP_Length>(count));
    vvexpf(temporary.data(),output,&count);
    const float negativeOne=-1.0f;
    vDSP_vsadd(temporary.data(),1,&negativeOne,output,1,static_cast<vDSP_Length>(count));
    vDSP_vsmul(output,1,&curve.inverse,output,1,static_cast<vDSP_Length>(count));
    if(!std::signbit(curve.amount)) for(int i=0;i<count;++i)output[i]=1.0f-output[i];
  }
}
void applyRelease(const float* table,std::int32_t tableFrames,ReleaseState& state,
                  float* stereo,std::int32_t frames) {
  if(state.position<0)return;
  const int wait=std::min(state.waitFrames,frames);
  state.waitFrames-=wait;stereo+=wait*2;frames-=wait;
  if(frames==0)return;
  const int remaining=std::max(0,tableFrames-state.position);
  const int active=std::min(remaining,frames);
  for(int i=0;i<active;++i) {
    const float gain=table[state.position+i];
    stereo[2*i]*=gain;stereo[2*i+1]*=gain;
  }
  std::fill(stereo+active*2,stereo+frames*2,0.0f);
  state.position+=frames;
}
}
extern "C" void vl_osc_declick_generate(const veggie_loops::three_osc::declick::Curve* curve,
 int shape,int direction,int offset,int total,float* output,int count) {
  veggie_loops::three_osc::declick::generate(*curve,shape,direction,offset,total,output,count);
}
extern "C" void vl_osc_declick_release(const float* table,int count,
 veggie_loops::three_osc::declick::ReleaseState* state,float* stereo,int frames) {
  veggie_loops::three_osc::declick::applyRelease(table,count,*state,stereo,frames);
}
