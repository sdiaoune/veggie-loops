#include "three_osc_clock_context.hpp"
#include <bit>
#include <cmath>
namespace veggie_loops::three_osc::clock {
namespace {
bool bounded(double x) noexcept{return std::isfinite(x)&&std::abs(x)<=0x1p52;}
bool validClock(double x) noexcept{return std::isfinite(x)&&x>=1&&x<=0x1p32;}
uint32_t roundedWord(double x) noexcept {
 return uint32_t(uint64_t(static_cast<int64_t>(std::rint(x))));
}
}
bool ticks(const TicksContext&c,TimePacket&p) noexcept {
 if(!bounded(c.cachedTicks)||!bounded(c.samplePositionFraction)||!validClock(c.samplesPerTick)||c.latencySamples<0||!bounded(p.t))return false;
 double value=c.cachedTicks;
 if(c.senderActive||c.future){
  const double delta=double(c.samplePosition)-c.samplePositionFraction;
  const double current=double(c.currentTick)+delta/c.samplesPerTick;
  value=current>=double(c.minimumTick)?current:double(c.minimumTick);
  value-=double(c.latencySamples)/c.samplesPerTick;
 }
 if(c.roundLocal){
  uint32_t word=roundedWord(value);
  if(c.songMode==1)word-=uint32_t(c.localStart);
  value=double(std::bit_cast<int32_t>(word));
 }
 if(p.t!=0)value+=p.t/c.samplesPerTick;
 p.t=value;return true;
}
bool delivery(const DeliveryContext&c,Delivery&out) noexcept {
 if(c.sampleRate<8000||c.sampleRate>384000||c.signatureFirst<1||c.signatureFirst>1024||c.signatureSecond<1||c.signatureSecond>1024||c.ppq<4||c.ppq>(1<<20)||!std::isfinite(c.tempo)||c.tempo<=0||c.tempo>1000||!validClock(c.samplesPerTick))return false;
 const float clock=static_cast<float>(c.samplesPerTick);
 Delivery value{};value.timeSignature={c.signatureFirst,c.signatureSecond,c.ppq};value.sampleRate=c.sampleRate;
 value.samplesPerTickDispatchValue=intptr_t(std::bit_cast<int32_t>(clock));
 value.tempoEventValue=std::bit_cast<int32_t>(c.tempo);
 value.tempoEventFlags=roundedWord(c.samplesPerTick);
 out=value;return true;
}
}
