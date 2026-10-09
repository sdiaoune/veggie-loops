#pragma once
// Independent prepared filter coefficient/kernel math. Native routing,
// preference/context production, double-order compensation and voice mixing
// remain separate. All calls require finite prepared values and valid buffers.
#include <array>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
namespace veggie_loops::three_osc::filter {
struct Coefficients {
  std::int32_t type=0;
  float cutoff=0,resonance=0,unused=0;
  std::array<float,5> biquad{};float padding=0;
  std::array<double,4> single{}; // positionsL/R, velocitiesL/R
};
static_assert(sizeof(Coefficients)==72 && offsetof(Coefficients,biquad)==0x10 && offsetof(Coefficients,single)==0x28);
struct Context {
  float rateRatio=1;
  float singleExponent=std::bit_cast<float>(0x40ccc14au);
  float biquadFrequencyExponent=std::bit_cast<float>(0x407ba308u);
  float biquadResonanceExponent=std::bit_cast<float>(0x401d45e5u);
  float silenceThreshold=0x1p-24f;
};
// Reviewed context: rate in[8000,384000]; logarithms/threshold are the observed
// initialized native defaults above. Their native production/routing is open.
inline Context context(std::int32_t rate) {Context result;result.rateRatio=float(44100.0/double(rate));return result;}
// Finite normalized cutoff/resonance in[-2,2], valid context. Single/special
// preparation alters only cutoff/resonance. Biquad supports native type1..5.
inline void singleCoefficients(float cutoff,float resonance,const Context& ctx,Coefficients& cfg) {
  if(cutoff<=0)cfg.cutoff=0;
  else if(cutoff>=1)cfg.cutoff=1;
  else {
    const float exponent=cutoff*ctx.singleExponent;
    const float curved=float((std::exp(double(exponent))-1.0)*double(1.0f/600.0f));
    const float value=curved*ctx.rateRatio;cfg.cutoff=value>=1 ? 1:value;
  }
  if(resonance<=0)cfg.resonance=0;
  else {
    resonance=resonance>1 ? 1:resonance;
    const float position=1.0f-resonance*0.625f;
    const float exponent=position*ctx.singleExponent;
    cfg.resonance=1.0f-float((std::exp(double(exponent))-1.0)*double(1.0f/600.0f));
  }
}
inline void designBiquad(double gain,double alpha,double sine,double cosine,Coefficients& cfg) {
  auto& c=cfg.biquad;
  if(cfg.type>=1 && cfg.type<=4) {
    const double inverse=1.0/(alpha+1.0);
    c[3]=float((inverse*cosine)*-2.0);c[4]=float(inverse*(1.0-alpha));
    if(cfg.type==1) {c[1]=float(inverse*(1.0-cosine));c[0]=c[1]*0.5f;c[2]=c[0];}
    if(cfg.type==2) {c[1]=0;c[0]=float(inverse*alpha);c[2]=float(inverse*-alpha);}
    if(cfg.type==3) {c[1]=float(inverse*-(cosine+1.0));c[0]=-c[1]*0.5f;c[2]=c[0];}
    if(cfg.type==4) {c[1]=c[3];c[0]=float(inverse);c[2]=float(inverse);}
  } else if(cfg.type==5) {
    const double extra=(gain-1.0)*cosine,weighted=alpha*sine;
    const double inverse=1.0/(gain+1.0+extra+weighted);
    c[3]=float((inverse*((gain-1.0)+(gain+1.0)*cosine))*-2.0);
    c[4]=float(inverse*((gain+1.0+extra)-weighted));
    c[1]=float(((inverse*gain)*2.0)*((gain-1.0)-(gain+1.0)*cosine));
    c[0]=float((inverse*gain)*(((gain+1.0)-extra)+weighted));
    c[2]=float((inverse*gain)*(((gain+1.0)-extra)-weighted));
  }
}
inline void biquadCoefficients(float cutoff,float resonance,const Context& ctx,Coefficients& cfg) {
  const float minimum=float(double(ctx.rateRatio)*0.02);
  const float curved=float(((std::exp(double(cutoff*ctx.biquadFrequencyExponent))-1.0)*double(0.0596f)+0.02)*double(ctx.rateRatio));
  cfg.cutoff=curved<minimum ? minimum:curved>3 ? 3:curved;
  if(resonance<=0)cfg.resonance=0.1f;
  else {resonance=resonance>1 ? 1:resonance;cfg.resonance=float((std::exp(double(resonance*ctx.biquadResonanceExponent))-1.0)*double(0.4f)+0.1);}
  const float sine=float(std::sin(double(cfg.cutoff))),cosine=float(std::cos(double(cfg.cutoff)));
  const float alpha=sine/(cfg.resonance*2.0f);
  designBiquad(0.0,double(alpha),double(sine),double(cosine),cfg);
}
inline void specialCoefficients(float cutoff,float resonance,const Context& ctx,Coefficients& cfg) {
  if(cutoff<=0)cfg.cutoff=0;
  else {
    const float curved=float(std::exp(double(cutoff)*3.258096538021482)-1.0);
    const float value=(curved*0.04f)*ctx.rateRatio;cfg.cutoff=value>=1 ? 1:value;
  }
  cfg.resonance=resonance<=0 ? 1:resonance>=1 ? 0.2f:1.0f-resonance*0.8f;
}
// source/output are disjoint or exactly identical; each has2*frames readable/
// writable floats. They do not overlap state. Frames in[0,4096], finite samples
// |x|<=1 and initial history |x|<=2. Prepared stable coefficients are required.
// Single coefficient ramps remain in[0,1.001] for every rendered frame.
inline void singleRender(float cutoff,float increment,Coefficients& cfg,const Context& ctx,
                         const float* source,float* output,std::int32_t frames) {
  auto state=cfg.single;
  for(int i=0;i<frames;++i) {
    for(int lane=0;lane<2;++lane) {
      const size_t p=size_t(lane),v=p+2;
      state[v]=state[v]+(double(source[2*i+lane])-state[p])*double(cutoff);
      state[p]=state[p]+state[v];state[v]=state[v]*double(cfg.resonance);
      output[2*i+lane]=float(state[p]);
    }
    cutoff=cutoff+increment;
  }
  for(auto& value:state)if(std::fabs(value)<double(ctx.silenceThreshold))value=0;
  cfg.single=state;
}
inline void biquadRender(const Coefficients& cfg,std::array<float,8>& state,
                         const float* source,float* output,std::int32_t frames) {
  const auto& c=cfg.biquad;
  for(int i=0;i<frames;++i)for(int lane=0;lane<2;++lane) {
    const size_t p=size_t(lane);
    const float value=((c[1]*state[p]+c[2]*state[p+2])-c[3]*state[p+4])-c[4]*state[p+6];
    state[p+6]=state[p+4];state[p+2]=state[p];state[p]=source[2*i+lane];
    state[p+4]=value+c[0]*state[p];output[2*i+lane]=state[p+4];
  }
}
inline void specialRender(const Coefficients& cfg,std::array<float,8>& state,const Context& ctx,
                          const float* source,float* output,std::int32_t frames) {
  for(int i=0;i<frames;++i)for(int lane=0;lane<2;++lane) {
    const size_t p=size_t(lane),v=p+2;
    state[p]=state[p]+cfg.cutoff*state[v];
    state[v]=state[v]+cfg.cutoff*((source[2*i+lane]-state[p])-cfg.resonance*state[v]);
    output[2*i+lane]=state[p];
  }
  for(auto& value:state)if(std::fabs(value)<ctx.silenceThreshold)value=0;
}
}
