#include "live_compressor.hpp"
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <utility>

namespace veggie_loops::purity::classes {
DynamicProcessor::~DynamicProcessor() noexcept = default;
PeakCompressor::~PeakCompressor() noexcept = default;
RMSCompressor::~RMSCompressor() noexcept = default;
void DynamicProcessor::commonInit(){dirty=1;}
void DynamicProcessor::init(){if(!dirty){dirty=1;gain=1;}}
void RMSCompressor::init(){if(!dirty){dirty=1;gain=1;detector=0;}}
void DynamicProcessor::setSampleRate(float value){rate=value;}
void DynamicProcessor::setBPM(double value){bpm=value;}
void DynamicProcessor::setPPQ(double value){ppq=value;}
void DynamicProcessor::value2string(int32_t index,float value,char* output){
    // Valid raw-class callers provide at least64 writable bytes; the C facade
    // formats into temporary storage and checks the actual caller capacity.
    if(index==0){const float mapped=value*.99f+.01f;if(mapped>0){const float db=std::log10(mapped)*20.0f;std::snprintf(output,64,"%.2f dB",double(db));}else std::memcpy(output,"-oo",4);}
    else if(index==1){const float mapped=value*19.0f+1.0f;std::snprintf(output,64,"%.1f : 1",double(mapped));}
    else if(index==2){const float squared=value*value;const float cubed=squared*value;const int ms=int(cubed*4990.0f+.5f)+10;std::snprintf(output,64,"%d ms",ms);}
}
void DynamicProcessor::getParamDisplay(int32_t index,char* output){const std::array<float,3> targets{targetThreshold,targetRatio,targetRelease};value2string(index,targets[size_t(index)],output);}
void DynamicProcessor::setParamValue(const float* values){targetThreshold=values[0];targetRatio=values[1];targetRelease=values[2];}
void DynamicProcessor::setWetOnly(bool value){wetOnly=uint8_t(value);}
void DynamicProcessor::commonPrepare(){dirty=1;}
void DynamicProcessor::prepare(){commonPrepare();}
void DynamicProcessor::commonCalc(){}
void DynamicProcessor::calc(){commonCalc();}
void DynamicProcessor::process(float*,float*,int32_t){dirty=0;}
VLPurityPeakCompressor DynamicProcessor::prepared() const noexcept {
    VLPurityPeakCompressor state{};state.sample_rate=rate;
    state.threshold=threshold;state.ratio=ratio;state.release=release;
    state.target_threshold=targetThreshold;state.target_ratio=targetRatio;state.target_release=targetRelease;
    state.dirty=dirty;state.gain=gain;return state;
}
void DynamicProcessor::copyResult(const VLPurityPeakCompressor& state) noexcept {
    threshold=state.threshold;ratio=state.ratio;release=state.release;dirty=state.dirty;gain=state.gain;
}
void PeakCompressor::process(float* left,float* right,int32_t count){
    if(count==0){dirty=0;return;}auto state=prepared();if(vl_purity_peak_compress(&state,left,right,count))copyResult(state);
}
void RMSCompressor::process(float* left,float* right,int32_t count){
    if(count==0){dirty=0;return;}VLPurityRMSCompressor state{};state.base=prepared();state.detector=detector;
    if(vl_purity_rms_compress(&state,left,right,count)){copyResult(state.base);detector=state.detector;}
}
}

using veggie_loops::purity::classes::DynamicProcessor;
using veggie_loops::purity::classes::PeakCompressor;
using veggie_loops::purity::classes::RMSCompressor;
struct VLPurityLiveCompressor {
    std::unique_ptr<DynamicProcessor> object;
    int32_t kind=0;
    bool initialized=false;
};
namespace {
int32_t kindOf(int32_t kind){return kind==5||kind==6?6:kind==7?7:0;}
bool unit(float v){return std::isfinite(v)&&v>=0&&v<=1;}
size_t objectSize(const VLPurityLiveCompressor& h){return h.kind==7?72:64;}
bool overlap(const void* a,size_t as,const void* b,size_t bs){
    if(!as||!bs)return false;const auto x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);
    if(x>std::numeric_limits<uintptr_t>::max()-as||y>std::numeric_limits<uintptr_t>::max()-bs)return true;
    return x<y+bs&&y<x+as;
}
bool overlapsObject(const VLPurityLiveCompressor& h,const void* p,size_t size){return overlap(&h,sizeof h,p,size)||overlap(h.object.get(),objectSize(h),p,size);}
std::unique_ptr<DynamicProcessor> make(int32_t kind,int32_t enabled){
    std::unique_ptr<DynamicProcessor> object;
    if(kind==6)object.reset(new(std::nothrow)PeakCompressor);else object.reset(new(std::nothrow)RMSCompressor);
    if(object&&enabled)object->init();return object;
}
bool validHandle(const VLPurityLiveCompressor* h){return h&&h->object;}
bool validNumerical(const VLPurityLiveCompressor& h){
    const auto& o=*h.object;return h.initialized&&std::isfinite(o.rate)&&o.rate>=8000&&o.rate<=192000&&
        unit(o.threshold)&&unit(o.ratio)&&unit(o.release)&&unit(o.targetThreshold)&&unit(o.targetRatio)&&unit(o.targetRelease)&&unit(o.gain)&&
        (h.kind!=7||(std::isfinite(static_cast<const RMSCompressor&>(o).detector)&&static_cast<const RMSCompressor&>(o).detector>=0&&static_cast<const RMSCompressor&>(o).detector<=131072));
}
int formatted(VLPurityLiveCompressor* h,int32_t index,float value,bool display,char* output,size_t capacity){
    if(!validHandle(h)||!output||index<0||index>2||!capacity||overlapsObject(*h,output,capacity)||(!display&&!unit(value)))return 0;
    std::array<char,64> temporary{};
    if(display)h->object->getParamDisplay(index,temporary.data());else h->object->value2string(index,value,temporary.data());
    const size_t length=std::strlen(temporary.data())+1;if(length>capacity)return 0;
    std::memcpy(output,temporary.data(),length);return 1;
}
}
extern "C" {
VLPurityLiveCompressor* vl_purity_live_create(int32_t inputKind,int32_t enabled){
    const int32_t kind=kindOf(inputKind);if(!kind||(enabled!=0&&enabled!=1))return nullptr;
    auto h=std::unique_ptr<VLPurityLiveCompressor>(new(std::nothrow)VLPurityLiveCompressor);if(!h)return nullptr;
    h->object=make(kind,enabled);if(!h->object)return nullptr;h->kind=kind;h->initialized=enabled;return h.release();
}
void vl_purity_live_destroy(VLPurityLiveCompressor* h){delete h;}
int vl_purity_live_replace(VLPurityLiveCompressor* h,int32_t inputKind,int32_t enabled){
    const int32_t kind=kindOf(inputKind);if(!validHandle(h)||!kind||(enabled!=0&&enabled!=1))return 0;
    auto object=make(kind,enabled);if(!object)return 0;h->object=std::move(object);h->kind=kind;h->initialized=enabled;return 1;
}
int vl_purity_live_sample_rate(VLPurityLiveCompressor* h,float rate){if(!validHandle(h)||!std::isfinite(rate)||rate<8000||rate>192000)return 0;h->object->setSampleRate(rate);return 1;}
int vl_purity_live_bpm(VLPurityLiveCompressor* h,double value){if(!validHandle(h)||!std::isfinite(value))return 0;h->object->setBPM(value);return 1;}
int vl_purity_live_ppq(VLPurityLiveCompressor* h,double value){if(!validHandle(h)||!std::isfinite(value))return 0;h->object->setPPQ(value);return 1;}
int vl_purity_live_parameters(VLPurityLiveCompressor* h,const float* p){if(!validHandle(h)||!p||overlapsObject(*h,p,12)||!unit(p[0])||!unit(p[1])||!unit(p[2]))return 0;h->object->setParamValue(p);return 1;}
int vl_purity_live_wet_only(VLPurityLiveCompressor* h,int32_t value){if(!validHandle(h)||(value!=0&&value!=1))return 0;h->object->setWetOnly(value!=0);return 1;}
int vl_purity_live_lifecycle(VLPurityLiveCompressor* h,int32_t operation){
    if(!validHandle(h)||operation<0||operation>5)return 0;
    switch(operation){case 0:h->object->commonInit();break;case 1:if(!h->initialized&&h->object->dirty)return 0;h->object->init();h->initialized=true;break;case 2:h->object->commonPrepare();break;case 3:h->object->prepare();break;case 4:h->object->commonCalc();break;case 5:h->object->calc();break;}return 1;
}
int vl_purity_live_process(VLPurityLiveCompressor* h,float* left,float* right,int32_t count){
    if(!validHandle(h)||count<0||count>8192)return 0;
    if(count==0){h->object->process(left,right,0);return 1;}
    if(!validNumerical(*h)||!left||!right)return 0;
    const size_t bytes=size_t(count)*4;
    if((left!=right&&overlap(left,bytes,right,bytes))||overlapsObject(*h,left,bytes)||overlapsObject(*h,right,bytes))return 0;
    for(int32_t i=0;i<count;++i)if(!std::isfinite(left[i])||std::fabs(left[i])>4||!std::isfinite(right[i])||std::fabs(right[i])>4)return 0;
    h->object->process(left,right,count);return 1;
}
int vl_purity_live_snapshot(const VLPurityLiveCompressor* h,VLPurityLiveSnapshot* out){
    if(!validHandle(h)||!out||overlapsObject(*h,out,sizeof *out))return 0;
    VLPurityLiveSnapshot state{};const auto&o=*h->object;state.version=1;state.kind=h->kind;state.object_bytes=uint32_t(objectSize(*h));state.initialized=h->initialized;
    state.sample_rate=o.rate;state.bpm=o.bpm;state.ppq=o.ppq;state.current[0]=o.threshold;state.current[1]=o.ratio;state.current[2]=o.release;
    state.targets[0]=o.targetThreshold;state.targets[1]=o.targetRatio;state.targets[2]=o.targetRelease;state.dirty=o.dirty;state.wet_only=o.wetOnly;state.gain=o.gain;
    if(h->kind==7)state.detector=static_cast<const RMSCompressor&>(o).detector;*out=state;return 1;
}
int vl_purity_live_format(VLPurityLiveCompressor* h,int32_t i,float v,char* out,size_t n){return formatted(h,i,v,false,out,n);}
int vl_purity_live_display(VLPurityLiveCompressor* h,int32_t i,char* out,size_t n){return formatted(h,i,0,true,out,n);}
const void* vl_purity_live_object(const VLPurityLiveCompressor* h){return validHandle(h)?h->object.get():nullptr;}
}
static_assert(sizeof(VLPurityLiveSnapshot)==80);
