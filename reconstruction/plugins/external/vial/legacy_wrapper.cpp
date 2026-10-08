// Original experimental legacy-format glue for the GPL upstream Vial source.
// GPL-3.0-or-later. This is not the installed Vital 1.0.7 wrapper, and does not
// implement an editor, host automation callbacks, programs or realtime safety.
#include "JuceHeader.h"
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter();
struct Legacy;
using Dispatch = intptr_t (*)(Legacy*, int32_t, int32_t, intptr_t, void*, float);
using Render = void (*)(Legacy*, float**, float**, int32_t);
struct Legacy {
    int32_t magic; Dispatch dispatch; Render accumulating;
    void (*setParameter)(Legacy*, int32_t, float);
    float (*getParameter)(Legacy*, int32_t);
    int32_t programs, parameters, inputs, outputs, flags;
    intptr_t reserved1, reserved2; int32_t delay, realQualities, offlineQualities;
    float ioRatio; void* object; void* user; int32_t id, version;
    Render replacing; void (*doubleReplacing)(Legacy*, double**, double**, int32_t); char future[56];
};
struct MidiRecord { int32_t type, byteSize, offset, flags, length, noteOffset; uint8_t data[4]; int8_t detune; uint8_t offVelocity, r1, r2; };
struct EventList { int32_t count; intptr_t reserved; MidiRecord* events[2]; };
static_assert(sizeof(Legacy)==192 && sizeof(MidiRecord)==32);
struct Processor {
    juce::ScopedJuceInitialiser_GUI initialiser;
    std::unique_ptr<juce::AudioProcessor> synth;
    Legacy effect{};
    juce::MemoryBlock state;
    juce::MidiBuffer midi;
    double rate=48000;
    int block=512;
    bool prepared=false;
    Processor() {
        juce::AudioProcessor::setTypeOfNextNewPlugin(juce::AudioProcessor::wrapperType_VST);
        try { synth.reset(createPluginFilter()); }
        catch (...) { juce::AudioProcessor::setTypeOfNextNewPlugin(juce::AudioProcessor::wrapperType_Undefined); throw; }
        juce::AudioProcessor::setTypeOfNextNewPlugin(juce::AudioProcessor::wrapperType_Undefined);
        if (!synth) throw std::bad_alloc();
        synth->setPlayConfigDetails(0,2,rate,block);
    }
    ~Processor() { if(prepared) synth->releaseResources(); }
};
static Processor& owner(Legacy* effect) { return *static_cast<Processor*>(effect->object); }
static void setParameter(Legacy* effect, int32_t index, float value) {
    auto& p=owner(effect); const auto& params=p.synth->getParameters();
    if(index>=0 && index<params.size() && std::isfinite(value) && value>=0 && value<=1) params[index]->setValue(value);
}
static float getParameter(Legacy* effect, int32_t index) {
    const auto& params=owner(effect).synth->getParameters(); return index>=0 && index<params.size()?params[index]->getValue():0;
}
static void render(Legacy* effect,float**,float** outputs,int32_t frames) {
    auto& p=owner(effect);
    if(!outputs || frames<0 || frames>p.block) return;
    for(int channel=0;channel<2;++channel) { if(!outputs[channel]) return; std::fill(outputs[channel],outputs[channel]+frames,0); }
    if(!p.prepared) return;
    // The current process block can be shorter than the announced maximum.
    // Events outside it are invalid for this call and are discarded, rather
    // than handed to a processor with offsets beyond its audio buffer.
    if(frames==0){p.midi.clear();return;}
    p.midi.clear(frames,std::numeric_limits<int>::max()-frames);
    juce::AudioBuffer<float> audio(outputs,2,frames);
    p.synth->processBlock(audio,p.midi); p.midi.clear();
}
static intptr_t dispatch(Legacy* effect,int32_t op,int32_t index,intptr_t value,void* pointer,float option) {
    auto& p=owner(effect);
    switch(op) {
        case 0: return 1;
        case 1: delete &p; return 1;
        case 2: return value==0?1:0;
        case 3: return 0;
        case 5: if(pointer) std::strcpy(static_cast<char*>(pointer),"Init");return pointer?1:0;
        case 6: case 7: case 8: {
            if(!pointer || index<0 || index>=p.synth->getParameters().size()) return 0;
            const auto* param=p.synth->getParameters()[index];
            const auto text=op==6?param->getLabel():op==7?param->getText(param->getValue(),7):param->getName(7);
            text.copyToUTF8(static_cast<char*>(pointer),8);return 1;
        }
        case 10:
            if(!p.prepared && std::isfinite(option) && option>=8000 && option<=192000) {p.rate=option;return 1;}return 0;
        case 11: if(!p.prepared && value>=1 && value<=8192){p.block=int(value);return 1;}return 0;
        case 12:
            if(value && !p.prepared){p.synth->setPlayConfigDetails(0,2,p.rate,p.block);p.synth->prepareToPlay(p.rate,p.block);p.prepared=true;return 1;}
            if(!value && p.prepared){p.synth->releaseResources();p.prepared=false;p.midi.clear();}return 1;
        case 23:
            if(!pointer) return 0;p.state.reset();p.synth->getStateInformation(p.state);
            *static_cast<void**>(pointer)=p.state.getData();return intptr_t(p.state.getSize());
        case 24:
            if(!pointer || value<=0 || value>64*1024*1024) return 0;
            p.synth->setStateInformation(pointer,int(value));return 1;
        case 25: {
            if(!pointer)return 0;auto* events=static_cast<EventList*>(pointer);
            if(events->count<0 || events->count>4096) return 0;
            const auto* pointers=reinterpret_cast<MidiRecord* const*>(static_cast<const char*>(pointer)+offsetof(EventList,events));
            for(int i=0;i<events->count;++i){
                const auto* e=pointers[i];
                if(!e || e->type!=1 || e->byteSize<32 || e->offset<0 || e->offset>=p.block)continue;
                const int status=e->data[0]&0xf0;
                const int bytes=(status==0xc0 || status==0xd0)?2:3;
                if(status>=0x80 && status<=0xe0) p.midi.addEvent(e->data,bytes,e->offset);
            }return 1;
        }
        case 26: return index>=0 && index<effect->parameters;
        case 45: case 48: if(pointer)std::strcpy(static_cast<char*>(pointer),"Vial Research");return pointer?1:0;
        case 47: if(pointer)std::strcpy(static_cast<char*>(pointer),"Vial Audio");return pointer?1:0;
        case 49: return 0x10006;
        case 51: if(pointer && (!std::strcmp(static_cast<char*>(pointer),"receiveVstEvents") || !std::strcmp(static_cast<char*>(pointer),"receiveVstMidiEvent")))return 1;return 0;
        case 58: return 2400;
        case 71: case 72: return 1;
        default: return 0;
    }
}
extern "C" __attribute__((visibility("default"))) Legacy* VSTPluginMain(Dispatch host) {
    if(!host || host(nullptr,1,0,0,nullptr,0)<2000)return nullptr;
    try {
        auto p=std::make_unique<Processor>();auto& effect=p->effect;
        effect.magic=0x56737450;effect.dispatch=dispatch;effect.setParameter=setParameter;effect.getParameter=getParameter;
        effect.programs=1;effect.parameters=p->synth->getParameters().size();effect.inputs=0;effect.outputs=2;
        effect.flags=(1<<4)|(1<<5)|(1<<8);effect.ioRatio=1;effect.object=p.get();effect.id=0x5669616c;effect.version=0x10006;effect.replacing=render;
        p.release();return &effect;
    }catch(...){return nullptr;}
}
