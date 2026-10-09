#pragma once
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

// Independently written numerical behavior. Native host, UI and application
// integration are separate obligations; this class is not a plugin certificate.
namespace vl::stereo_shaper {
struct Processor {
  std::array<std::int32_t,6> raw{0,12800,12800,0,0,0};
  std::array<float,4> targets{}, current{};
  bool dirty=true;
  std::int32_t sampleRate=44100, prePost=0, send=0;
  float limit=0x1.0624dep-10f;
  double omegaScale=0x1.2acb24b91e1eep-13;
  float frequencyCap=0x1.58765cp+14f;
  float delayFactor=0x1.c39582p-2f, delayTime=0;
  std::vector<float> delay;
  std::size_t cursor=0;
  std::int32_t phaseChannel=0;
  float cutoff=0;
  std::array<double,5> coefficients{}; // b0,b1,b2,a1,a2
  std::array<double,4> history{}; // x1,x2,y1,y2

  static float gain(std::int32_t value) {
    const float unit=float(double(value)*0.000078125);
    const float magnitude=std::abs(unit);
    const float mapped=magnitude==1.0f?1.0f:
      float((std::exp(double(magnitude*0x1.193ea8p+0f))-1.0)*0.5);
    return mapped*float((unit>0)-(unit<0));
  }
  void updateMatrix() {
    if(!dirty)return;
    targets={gain(raw[1]),gain(raw[2]),gain(raw[0]),gain(raw[3])};
    dirty=false;
  }
  void resetDelay() {
    delay.assign(std::size_t(std::nearbyint(delayTime*delayFactor)),0.0f);
    cursor=0;
  }
  void updatePhase() {
    phaseChannel=(raw[5]>0)-(raw[5]<0);
    if(!phaseChannel){history.fill(0);return;}
    const double curve=std::exp(double(1.0f-std::abs(float(raw[5])*0x1p-12f))*8.517393171418904);
    cutoff=float(double(float(curve-1.0))*4.398+10.0);
    cutoff=std::min(cutoff,frequencyCap);
    const double omega=double(cutoff)*omegaScale;
    const double sine=std::sin(omega),cosine=std::cos(omega);
    const double scale=1.0/(sine+1.0);
    const double a1=scale*cosine*-2.0, a2=scale*(1.0-sine);
    coefficients={a2,a1,1.0,a1,a2};
  }
  void parameter(std::int32_t index,std::int32_t value) {
    raw[std::size_t(index)]=value;
    if(index<4)dirty=true;
    else if(index==4){delayTime=float(std::exp(double(float(std::abs(value))*0x1p-12f)*6.90875477931522)-1.0)*50.0f;resetDelay();}
    else updatePhase();
  }
  void resume() {current=targets;history.fill(0);}
  void changeRate(std::int32_t rate) {
    sampleRate=rate;limit=float((44100.0/double(rate))*0.001);
    omegaScale=(1.0/double(rate))*6.283185307179586;
    frequencyCap=float(double(rate)*0.4999);
    delayFactor=float(double(rate)/100000.0);resetDelay();updatePhase();
  }
  std::array<float,4> ramp(std::int32_t count) {
    std::array<float,4> step{};
    for(std::size_t k=0;k<4;++k){
      const float start=current[k];step[k]=targets[k]-start;
      if(std::bit_cast<std::uint32_t>(step[k])!=0){
        current[k]=targets[k];step[k]/=float(count);
        if(std::abs(step[k])>limit){
          step[k]=std::bit_cast<float>(std::bit_cast<std::uint32_t>(limit)|(std::bit_cast<std::uint32_t>(step[k])&0x80000000u));
          current[k]=start+step[k]*float(count);
          if((std::bit_cast<std::uint32_t>(current[k])&0x7fffffffu)<0x33800000u){current[k]=0;step[k]=-start/float(count);}
        }
      }
    }
    return step;
  }
  void processSelected(float* audio,std::int32_t count) {
    if(!delay.empty())for(std::int32_t i=0;i<count;++i){
      const std::size_t channel=raw[4]>0?1:0, index=2*std::size_t(i)+channel;
      const float old=audio[index];audio[index]=delay[cursor];delay[cursor]=old;
      if(++cursor==delay.size())cursor=0;
    }
    if(phaseChannel)for(std::int32_t i=0;i<count;++i){
      const std::size_t channel=phaseChannel>0?1:0,index=2*std::size_t(i)+channel;
      const double input=audio[index];
      const double output=(((coefficients[2]*history[1]+coefficients[1]*history[0])-coefficients[3]*history[2])-coefficients[4]*history[3])+coefficients[0]*input;
      history={input,history[0],output,history[2]};audio[index]=float(output);
    }
  }
  void render(const float* input,float* output,std::int32_t count,float* sideOutput) {
    std::array<float,2048> dry;
    if(send>0 && sideOutput)std::memcpy(dry.data(),input,std::size_t(count)*8);
    if(prePost==0){if(input!=output)std::memcpy(output,input,std::size_t(count)*8);processSelected(output,count);input=output;}
    updateMatrix();auto value=current;const auto step=ramp(count);
    std::uint32_t changing=0;for(float s:step)changing|=std::bit_cast<std::uint32_t>(s);
    const bool diagonal=(std::bit_cast<std::uint32_t>(value[2])|std::bit_cast<std::uint32_t>(value[3]))==0;
    for(std::int32_t i=0;i<count;++i){
      const float left=input[2*i],right=input[2*i+1];
      const float l=value[0]*left, r=value[1]*right;
      output[2*i]=!changing&&diagonal?l:l+value[2]*right;
      output[2*i+1]=!changing&&diagonal?r:r+value[3]*left;
      if(changing)for(std::size_t k=0;k<4;++k)value[k]=step[k]+value[k];
    }
    if(prePost>0)processSelected(output,count);
    if(send>0 && sideOutput)for(std::size_t i=0;i<std::size_t(count)*2;++i){const float residual=dry[i]-output[i];sideOutput[i]=residual+sideOutput[i];}
  }
};
}
