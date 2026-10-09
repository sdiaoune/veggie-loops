#include "three_osc_default_voice.h"
#include "three_osc_declick.hpp"
#include "three_osc_gain_mix.hpp"
#include "three_osc_voice_output.hpp"
#include <cmath>
#include <memory>
#include <new>
#include <vector>
struct vl_osc_default_voice {
  vl_osc_core* core=nullptr;vl_osc_voice* raw=nullptr;
  std::vector<float> releaseTable;
  veggie_loops::three_osc::declick::ReleaseState release;
  float left=-1,right=-1,maximumStep=0.001f;bool initial=true;
};
extern "C" vl_osc_default_voice* vl_osc_default_voice_create(vl_osc_core* core,vl_osc_voice* raw,int32_t rate) {
  if(!core || !raw || rate<8000 || rate>384000)return nullptr;
  try {
    auto result=std::make_unique<vl_osc_default_voice>();result->core=core;result->raw=raw;
    const float ratio=static_cast<float>(44100.0/double(rate));
    result->maximumStep=static_cast<float>(double(ratio)*0.001);
    const auto length=static_cast<int>(std::nearbyint(10.0*0.001*double(rate)));
    result->releaseTable.resize(static_cast<size_t>(length));
    veggie_loops::three_osc::declick::generate({},3,1,0,length,result->releaseTable.data(),length);
    return result.release();
  }catch(const std::bad_alloc&) {return nullptr;}
}
extern "C" void vl_osc_default_voice_destroy(vl_osc_default_voice* voice) {delete voice;}
extern "C" void vl_osc_default_voice_release(vl_osc_default_voice* voice) {
  if(voice && voice->release.position<0) {voice->release.position=0;vl_osc_core_release(voice->core,voice->raw);}
}
extern "C" int vl_osc_default_voice_set_sample_rate(vl_osc_default_voice* voice,int32_t rate) {
  if(!voice || rate<8000 || rate>384000)return 0;
  const float ratio=static_cast<float>(44100.0/double(rate));
  voice->maximumStep=static_cast<float>(double(ratio)*0.001);return 1;
}
extern "C" int vl_osc_default_voice_render(vl_osc_default_voice* voice,float pan,float volume,float pitch,
 float* destination,uint32_t frames) {
  if(!voice || !destination || !std::isfinite(pan) || std::fabs(pan)>1 || !std::isfinite(volume) || volume<0 || volume>1 ||
     !std::isfinite(pitch) || pitch<-9600 || pitch>9600 || frames<1 || frames>4096 || voice->release.position>INT32_MAX-4096)return 0;
  try {
    std::vector<float> raw(size_t(frames)*2);
    if(!vl_osc_core_render(voice->core,voice->raw,pitch,raw.data(),frames))return 0;
    namespace output=veggie_loops::three_osc::voice_output;
    float left,right;output::gains(pan,volume,0,0.70710677f,left,right);
    if(voice->left==-1)voice->left=0;if(voice->right==-1)voice->right=0;
    if(voice->initial) {voice->left=left;voice->right=right;}
    veggie_loops::three_osc::declick::applyRelease(voice->releaseTable.data(),int(voice->releaseTable.size()),voice->release,raw.data(),int(frames));
    float leftStep,rightStep;
    output::slew(voice->left,voice->maximumStep,0x33800000u,int(frames),leftStep,left);
    output::slew(voice->right,voice->maximumStep,0x33800000u,int(frames),rightStep,right);
    if(std::bit_cast<uint32_t>(leftStep)==0 && std::bit_cast<uint32_t>(rightStep)==0)
      veggie_loops::three_osc::gain_mix::fixed(left,right,raw.data(),destination,frames);
    else veggie_loops::three_osc::gain_mix::ramp(voice->left,voice->right,leftStep,rightStep,raw.data(),destination,frames);
    voice->left=left;voice->right=right;voice->initial=false;return 1;
  }catch(const std::bad_alloc&) {return 0;}
}
extern "C" void vl_osc_default_voice_get_state(const vl_osc_default_voice* voice,vl_osc_default_voice_state* out) {
  if(voice && out)*out={voice->left,voice->right,voice->release.position,uint8_t(voice->initial)};
}
