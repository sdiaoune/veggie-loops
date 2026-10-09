#pragma once
#include "live_compressor.h"
#include "../peak_compressor.h"
#include "../rms_compressor.h"
#include <cstdint>

namespace veggie_loops::purity::classes {
// Independent Itanium C++ object shape and virtual order. Raw C++ methods require
// serialized valid objects/buffers/indexes; the bounded C API validates inputs.
// Constructor sentinel clocks/targets match native stores. Native unspecified
// padding and uninitialized history are independently set to zero/gain1; they
// are excluded from native-defined constructor equivalence. Disabled objects
// cannot process positive frame counts through the C API until valid init.
// Direct C++ processing also requires the prepared peak/RMS numeric contract:
// rate8000..192000; finite current/target controls and gain in[0,1]; RMS detector
// in[0,131072]; fresh finite audio[-4,4], count0..8192 and identical or disjoint
// channels, with no object/audio overlap. Configure sentinel rate/targets before
// positive processing. Raw formatting requires index0..2,64 writable bytes and
// normalized value0..1; getParamDisplay additionally supports constructor target
// sentinel-1. Clock stores accept finite doubles. Do not mutate public numerical
// fields or pass prepared copyResult records outside their corresponding bounds.
class DynamicProcessor {
public:
    virtual ~DynamicProcessor() noexcept;
    virtual void commonInit();
    virtual void init();
    virtual void setSampleRate(float);
    virtual void setBPM(double);
    virtual void setPPQ(double);
    virtual void value2string(int32_t index, float value, char* output);
    virtual void getParamDisplay(int32_t index, char* output);
    virtual void setParamValue(const float* three);
    virtual void setWetOnly(bool);
    virtual void commonPrepare();
    virtual void prepare();
    virtual void commonCalc();
    virtual void calc();
    virtual void process(float* left, float* right, int32_t count);
    DynamicProcessor() noexcept = default;
    VLPurityPeakCompressor prepared() const noexcept;
    void copyResult(const VLPurityPeakCompressor&) noexcept;
    float rate=-1;
    std::uint32_t ratePadding=0;
    double bpm=-1, ppq=-1;
    float threshold=.5f, ratio=.5f, release=.5f;
    float targetThreshold=-1, targetRatio=-1, targetRelease=-1;
    std::uint8_t dirty=0, wetOnly=0;
    std::uint16_t controlPadding=0;
    float gain=1;
};
class PeakCompressor final:public DynamicProcessor {
public:
    ~PeakCompressor() noexcept override;
    void process(float*,float*,int32_t) override;
};
class RMSCompressor final:public DynamicProcessor {
public:
    ~RMSCompressor() noexcept override;
    void init() override;
    void process(float*,float*,int32_t) override;
    float detector=0;
    std::uint32_t detectorPadding=0;
};
static_assert(sizeof(DynamicProcessor)==64 && sizeof(PeakCompressor)==64 && sizeof(RMSCompressor)==72);
}
