#if !defined(__APPLE__) || !defined(__aarch64__)
#error Original object-offset fixtures require Apple arm64.
#endif
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include "live_compressor.h"
#include <array>
#include <bit>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>
namespace {
void require(bool v,const char* text){if(!v)throw std::runtime_error(text);}
std::string sha(NSData* data){std::array<unsigned char,32> bytes{};CC_SHA256(data.bytes,CC_LONG(data.length),bytes.data());std::string s;for(auto b:bytes){char hex[3];std::snprintf(hex,3,"%02x",b);s+=hex;}return s;}
template<class T>T field(const void* p,size_t offset){T value;std::memcpy(&value,(const char*)p+offset,sizeof value);return value;}
template<class F>F slot(void* p,int index){return reinterpret_cast<F>(field<void**>(p,0)[index]);}
template<class T>void exact(const T&a,const T&b,const char* label){require(std::memcmp(&a,&b,sizeof a)==0,label);}
struct Module {
    void* p;
    explicit Module(const char* path):p(dlopen(path,RTLD_NOW|RTLD_LOCAL)){if(!p)throw std::runtime_error(dlerror());}
    ~Module(){dlclose(p);}
    template<class F>F bind(const char* name){auto* result=dlsym(p,name);require(result,name);return reinterpret_cast<F>(result);}
};
struct API {
#define FN(name) decltype(&vl_purity_live_##name) name;
    FN(create) FN(destroy) FN(replace) FN(sample_rate) FN(bpm) FN(ppq) FN(parameters) FN(wet_only)
    FN(lifecycle) FN(process) FN(snapshot) FN(format) FN(display) FN(object)
#undef FN
    explicit API(Module&m){
#define BIND(name) name=m.bind<decltype(name)>("vl_purity_live_" #name);
        BIND(create) BIND(destroy) BIND(replace) BIND(sample_rate) BIND(bpm) BIND(ppq) BIND(parameters) BIND(wet_only)
        BIND(lifecycle) BIND(process) BIND(snapshot) BIND(format) BIND(display) BIND(object)
#undef BIND
    }
};
struct Owned {API&api;VLPurityLiveCompressor* handle;~Owned(){api.destroy(handle);}};
struct Descriptor {
    std::array<uint64_t,2> before{0x5415973c591234ab,0xfedcb78987654321};
    alignas(16)std::array<unsigned char,32> data{};
    std::array<uint64_t,2> after=before;
    ~Descriptor(){if(void*p=field<void*>(data.data(),24))slot<void(*)(void*)>(p,1)(p);}
    void guards(){require(before==std::array<uint64_t,2>{0x5415973c591234ab,0xfedcb78987654321}&&after==before,"Descriptor guards changed");}
};
}
int main(int argc,char**argv){@autoreleasepool{try{
    require(argc==3,"Expected original binary and compiled live library");
    NSData* bytes=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    require(bytes&&sha(bytes)=="ef2675ee69f9498ae10807820660e1158ba3c50684f44dea46b03efd7ceb1b07","Original universal identity changed");
    Module original(argv[1]),rebuilt(argv[2]);API api(rebuilt);
    auto factory=original.bind<int(*)(void*,int)>("_Z7_setIFXPN6Purity4tIFXEi");
    uint64_t factories=0,blocks=0,frames=0,definedRecords=0,displays=0,replacements=0,rawSlots=0,invalid=0;
    std::mt19937 rng(0x50554c43);auto uniform=[&]{return float(double(rng())/double(UINT32_MAX));};
    auto compare=[&](void*native,VLPurityLiveCompressor* handle){
        VLPurityLiveSnapshot s{};require(api.snapshot(handle,&s),"Snapshot rejected");
        const auto* own=api.object(handle);require(own,"No live C++ object");
        exact(s.sample_rate,field<float>(native,8),"Rate differs");exact(s.bpm,field<double>(native,16),"BPM differs");exact(s.ppq,field<double>(native,24),"PPQ differs");
        for(int i=0;i<3;++i){exact(s.current[i],field<float>(native,32+size_t(i)*4),"Current differs");exact(s.targets[i],field<float>(native,44+size_t(i)*4),"Target differs");}
        exact(s.dirty,field<uint8_t>(native,56),"Dirty differs");exact(s.wet_only,field<uint8_t>(native,57),"Wet flag differs");
        if(s.initialized){exact(s.gain,field<float>(native,60),"Gain differs");if(s.kind==7)exact(s.detector,field<float>(native,64),"RMS history differs");}
        for(size_t offset:{8u,32u,36u,40u,44u,48u,52u,60u}){
            if(offset!=60||s.initialized)exact(field<uint32_t>(own,offset),field<uint32_t>(native,offset),"Compiled C++ object float offset differs");
        }
        exact(field<uint64_t>(own,16),field<uint64_t>(native,16),"Compiled BPM offset differs");exact(field<uint64_t>(own,24),field<uint64_t>(native,24),"Compiled PPQ offset differs");
        exact(field<uint8_t>(own,56),s.dirty,"Compiled dirty offset");exact(field<uint8_t>(own,57),s.wet_only,"Compiled wet offset");
        if(s.kind==7&&s.initialized)exact(field<uint32_t>(own,64),field<uint32_t>(native,64),"Compiled RMS offset");
        require(s.object_bytes==(s.kind==7?72u:64u),"Object size");++definedRecords;
    };
    auto display=[&](void*native,VLPurityLiveCompressor* h,int i,float value){
        std::array<char,128>a,b;a.fill('\x57');b=a;
        slot<void(*)(void*,int,float,char*)>(native,7)(native,i,value,a.data()+16);
        require(api.format(h,i,value,b.data()+16,96),"Format rejected");require(a==b,"Formatted value differs");
        a.fill('\x57');b=a;slot<void(*)(void*,int,char*)>(native,8)(native,i,a.data()+16);require(api.display(h,i,b.data()+16,96),"Display rejected");require(a==b,"Stored display differs");
        for(int j=0;j<16;++j)require(a[size_t(j)]=='\x57'&&a[size_t(j)+112]=='\x57'&&b[size_t(j)]=='\x57'&&b[size_t(j)+112]=='\x57',"Display guard changed");displays+=2;
    };
    const std::array<float,6> rates{8000,11025,44100,48000,96000,192000};
    const std::array<int,8> counts{0,1,3,31,64,255,1024,8192};
    for(int kind:{5,6,7})for(int enabled:{0,1})for(float initialRate:rates)for(int sequence=0;sequence<8;++sequence){
        Descriptor desc;desc.data[0]=uint8_t(enabled);require(factory(desc.data.data(),kind)==1,"Native factory failed");++factories;
        Owned model{api,api.create(kind,enabled)};require(model.handle,"Model factory failed");void*native=field<void*>(desc.data.data(),24);require(field<int32_t>(desc.data.data(),4)==(kind==7?7:6),"Native factory kind mapping");compare(native,model.handle);
        for(int i=0;i<3;++i)display(native,model.handle,i,0);
        if(!enabled){slot<void(*)(void*)>(native,3)(native);require(api.lifecycle(model.handle,1),"Disabled init failed");compare(native,model.handle);}
        require(api.sample_rate(model.handle,initialRate),"Initial rate");slot<void(*)(void*,float)>(native,4)(native,initialRate);
        for(int block=0;block<16;++block){
            const float rate=rates[size_t(block+sequence)%rates.size()];const double bpm=block%5==0?-0.0:block%5==1?std::numeric_limits<double>::max():137.25+sequence;
            const double ppq=block%5==2?-std::numeric_limits<double>::max():double(block)*.125;
            std::array<float,3> parameters{uniform(),uniform(),uniform()};if(block==0)parameters={0,0,0};if(block==8)parameters={1,1,1};
            slot<void(*)(void*,float)>(native,4)(native,rate);require(api.sample_rate(model.handle,rate),"Rate call");
            slot<void(*)(void*,double)>(native,5)(native,bpm);require(api.bpm(model.handle,bpm),"BPM call");slot<void(*)(void*,double)>(native,6)(native,ppq);require(api.ppq(model.handle,ppq),"PPQ call");
            slot<void(*)(void*,const float*)>(native,9)(native,parameters.data());require(api.parameters(model.handle,parameters.data()),"Parameter call");
            slot<void(*)(void*,bool)>(native,10)(native,(block&1)!=0);require(api.wet_only(model.handle,block&1),"Wet call");
            if(block%4==0){slot<void(*)(void*)>(native,3)(native);require(api.lifecycle(model.handle,1),"Init call");}
            if(block%4==1){slot<void(*)(void*)>(native,2)(native);require(api.lifecycle(model.handle,0),"Common init");slot<void(*)(void*)>(native,3)(native);require(api.lifecycle(model.handle,1),"Dirty init");}
            if(block%4==2){for(int op:{2,3,4,5}){const int index=op==2?11:op==3?12:op==4?13:14;slot<void(*)(void*)>(native,index)(native);require(api.lifecycle(model.handle,op),"Prepare/calc call");}}
            compare(native,model.handle);for(int i=0;i<3;++i)display(native,model.handle,i,parameters[size_t(i)]);
            const int count=counts[size_t(block+sequence)%counts.size()];const bool alias=(sequence+block)%3==0;
            constexpr float guard=std::bit_cast<float>(uint32_t{0x5a21ab49});std::vector<float>nl(size_t(count)+4,guard),nr=nl,ml=nl,mr=nl;
            for(int i=0;i<count;++i){float l=uniform()*8-4,r=uniform()*8-4;if(i%8==0){l=4;r=-4;}if(i%8==1)l=-0.0f;if(i%8==2)r=std::numeric_limits<float>::denorm_min();nl[size_t(i)+2]=ml[size_t(i)+2]=l;nr[size_t(i)+2]=mr[size_t(i)+2]=r;}
            slot<void(*)(void*,float*,float*,int)>(native,15)(native,nl.data()+2,alias?nl.data()+2:nr.data()+2,count);
            if(block%2==0){auto* object=const_cast<void*>(api.object(model.handle));slot<void(*)(void*,float*,float*,int)>(object,15)(object,ml.data()+2,alias?ml.data()+2:mr.data()+2,count);++rawSlots;}
            else require(api.process(model.handle,ml.data()+2,alias?ml.data()+2:mr.data()+2,count),"Live C process rejected");
            require(std::memcmp(nl.data(),ml.data(),nl.size()*4)==0&&std::memcmp(nr.data(),mr.data(),nr.size()*4)==0,"Audio differs");
            for(auto*a:{&nl,&nr,&ml,&mr})require((*a)[0]==guard&&(*a)[1]==guard&&(*a)[size_t(count)+2]==guard&&(*a)[size_t(count)+3]==guard,"Audio guard");
            compare(native,model.handle);++blocks;frames+=uint64_t(count);
            // Exercise the compiled object's non-processing virtual slots too.
            if(block==6){auto* own=const_cast<void*>(api.object(model.handle));for(int index:{2,11,12,13,14}){slot<void(*)(void*)>(native,index)(native);slot<void(*)(void*)>(own,index)(own);++rawSlots;}compare(native,model.handle);}
        }
        desc.data[0]=1;const int next=kind==7?6:7;require(factory(desc.data.data(),next)==1&&api.replace(model.handle,next,1),"Replacement");++factories;++replacements;native=field<void*>(desc.data.data(),24);compare(native,model.handle);
        desc.data[0]=0;require(factory(desc.data.data(),kind)==1&&api.replace(model.handle,kind,0),"Disabled replacement");++factories;++replacements;native=field<void*>(desc.data.data(),24);compare(native,model.handle);for(int i=0;i<3;++i)display(native,model.handle,i,0);desc.guards();
    }
    // Validation extensions are exercised only on the rebuilt library.
    Owned valid{api,api.create(7,1)};require(valid.handle,"Boundary create");std::array<float,3> parameters{.2f,.7f,.8f};require(api.sample_rate(valid.handle,48000)&&api.parameters(valid.handle,parameters.data()),"Boundary setup");
    std::array<float,40> left{},right{};left.fill(1);right.fill(-1);require(api.process(valid.handle,left.data(),right.data(),16),"Boundary retained state");
    auto reject=[&](auto call){VLPurityLiveSnapshot before{},after{};require(api.snapshot(valid.handle,&before),"Before snapshot");const auto a=left,b=right;require(call()==0,"Invalid accepted");require(api.snapshot(valid.handle,&after)&&std::memcmp(&before,&after,sizeof before)==0,"Invalid mutated state");require(std::memcmp(a.data(),left.data(),sizeof left)==0&&std::memcmp(b.data(),right.data(),sizeof right)==0,"Invalid mutated audio");++invalid;};
    for(float rate:{7999.0f,192001.0f,float(NAN),float(INFINITY)})reject([&]{return api.sample_rate(valid.handle,rate);});
    for(double clock:{double(NAN),double(INFINITY)}){reject([&]{return api.bpm(valid.handle,clock);});reject([&]{return api.ppq(valid.handle,clock);});}
    for(int i=0;i<3;++i)for(float bad:{-.1f,1.1f,float(NAN),float(INFINITY)}){auto p=parameters;p[size_t(i)]=bad;reject([&]{return api.parameters(valid.handle,p.data());});}
    for(int bad:{-1,8})reject([&]{return api.lifecycle(valid.handle,bad);});for(int bad:{-1,2})reject([&]{return api.wet_only(valid.handle,bad);});
    for(int count:{-1,8193})reject([&]{return api.process(valid.handle,left.data(),right.data(),count);});
    reject([&]{return api.process(valid.handle,nullptr,right.data(),16);});reject([&]{return api.process(valid.handle,left.data(),left.data()+1,16);});
    reject([&]{return api.process(valid.handle,const_cast<float*>((const float*)api.object(valid.handle)),right.data(),16);});
    for(float bad:{-4.1f,4.1f,float(INFINITY),float(NAN)}){left[31]=bad;reject([&]{return api.process(valid.handle,left.data(),right.data(),32);});left[31]=1;}
    std::array<char,128> output;output.fill('\x36');const auto untouched=output;
    for(int index:{-1,3})reject([&]{const int r=api.display(valid.handle,index,output.data(),output.size());require(output==untouched,"Rejected text changed");return r;});
    for(size_t capacity:{0u,1u,3u})reject([&]{const int r=api.display(valid.handle,0,output.data(),capacity);require(output==untouched,"Short text changed");return r;});
    for(float value:{-.1f,1.1f,float(NAN),float(INFINITY)})reject([&]{const int r=api.format(valid.handle,0,value,output.data(),output.size());require(output==untouched,"Invalid text changed");return r;});
    reject([&]{return api.replace(valid.handle,8,1);});reject([&]{return api.replace(valid.handle,6,2);});
    Owned uninitialized{api,api.create(7,0)};require(uninitialized.handle,"Disabled create");require(!api.process(uninitialized.handle,left.data(),right.data(),1),"Disabled process accepted");
    require(api.lifecycle(uninitialized.handle,3)&&!api.lifecycle(uninitialized.handle,1),"Dirty disabled init not rejected");require(api.process(uninitialized.handle,nullptr,nullptr,0)&&api.lifecycle(uninitialized.handle,1),"Disabled recovery");
    std::printf("{\"status\":\"passed\",\"actual_native_factory_creations\":%llu,\"process_blocks\":%llu,\"stereo_frames\":%llu,\"defined_state_records\":%llu,\"display_comparisons\":%llu,\"replacement_sequences\":%llu,\"compiled_raw_virtual_calls\":%llu,\"atomic_invalid_cases\":%llu,\"full_plugin_equivalence\":false}\n",(unsigned long long)factories,(unsigned long long)blocks,(unsigned long long)frames,(unsigned long long)definedRecords,(unsigned long long)displays,(unsigned long long)replacements,(unsigned long long)rawSlots,(unsigned long long)invalid);
    return 0;
}catch(const std::exception&e){std::fprintf(stderr,"%s\n",e.what());return 1;}}}
