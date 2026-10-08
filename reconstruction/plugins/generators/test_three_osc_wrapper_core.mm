#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_wrapper_core.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace {
void require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
template<class T> T load(const void* value, size_t offset) {
  T result; std::memcpy(&result,static_cast<const char*>(value)+offset,sizeof(result)); return result;
}
template<class F> F method(void* object, size_t offset) {
  return reinterpret_cast<F>(load<void**>(object,0)[offset/8]);
}
template<class F> F symbol(void* library, const char* name) {
  auto result = reinterpret_cast<F>(dlsym(library,name)); require(result != nullptr,"Missing rebuilt export"); return result;
}
std::string hash(const void* value,size_t length) {
  std::array<unsigned char,32> bytes; CC_SHA256(value,static_cast<CC_LONG>(length),bytes.data());
  std::ostringstream result; for (auto byte : bytes) result << std::hex << std::setfill('0') << std::setw(2) << unsigned(byte);
  return result.str();
}
struct Object { void** methods; };
std::array<void*,96> hostMethods;
std::array<void*,32> pathMethods;
Object pathObject{pathMethods.data()};
const char* dataPath;
extern "C" intptr_t noop() { return 0; }
extern "C" intptr_t hostDispatcher(void*,intptr_t,intptr_t id,intptr_t,intptr_t) {
  if (id == 71) return reinterpret_cast<intptr_t>(&pathObject);
  if (id == 29) return reinterpret_cast<intptr_t>(dataPath); return 0;
}
extern "C" void computeLR(void*,float* left,float* right,float pan,float volume) {
  *left = volume * std::sqrt((1.0f-pan)*0.5f); *right = volume * std::sqrt((1.0f+pan)*0.5f);
}
struct Stream { void** methods; std::vector<uint8_t> bytes; size_t cursor = 0; };
extern "C" intptr_t writeStream(Stream* stream,const void* value,uint32_t length,void*) {
  const auto* first = static_cast<const uint8_t*>(value); stream->bytes.insert(stream->bytes.end(),first,first+length); return 0;
}
extern "C" intptr_t readStream(Stream* stream,void* value,uint32_t length,void* completed) {
  require(stream->cursor+length <= stream->bytes.size(),"Native stream overread");
  std::memcpy(value,stream->bytes.data()+stream->cursor,length); stream->cursor += length;
  if (completed) std::memcpy(completed,&length,4); return 0;
}
struct Levels { float pan=0,volume=0.8f,pitch=6000,cutoff=1,resonance=0; };
struct VoiceParameters { Levels initial,final; };
struct NoiseGlobals { float* values; uint32_t seed,reserved; };
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc == 5,"Usage: test_three_osc_wrapper_core <native wrapper> <native engine> <rebuilt library> <private data directory/>");
    std::ifstream file(argv[1],std::ios::binary); std::vector<char> source{std::istreambuf_iterator<char>(file),{}};
    require(hash(source.data(),source.size()) == "c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Native wrapper identity mismatch");
    std::ifstream engineFile(argv[2],std::ios::binary); std::vector<char> engineSource{std::istreambuf_iterator<char>(engineFile),{}};
    require(hash(engineSource.data(),engineSource.size()) == "d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f","Native engine identity mismatch");
    [NSApplication sharedApplication]; dataPath=argv[4];
    hostMethods.fill(reinterpret_cast<void*>(&noop)); pathMethods.fill(reinterpret_cast<void*>(&noop));
    hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatcher); hostMethods[0x1c0/8]=reinterpret_cast<void*>(&computeLR);
    alignas(16) std::array<std::byte,512> host{}; auto** vmt=hostMethods.data(); std::memcpy(host.data(),&vmt,8);
    // HQ mode does not dereference the host's legacy waveforms, but pointer
    // identity is used to recognize noise/stereo. Supply distinct identities.
    std::array<std::array<float,16384>,6> waveIdentities{};
    for (size_t i=0;i<6;++i) {
      for (size_t sample=0;sample<waveIdentities[i].size();++sample)
        waveIdentities[i][sample]=std::sin(float(sample)*0.0003834952f*float(i+1));
      void* pointer=waveIdentities[i].data(); std::memcpy(host.data()+0x18+i*8,&pointer,8);
    }
    void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); require(native,"Cannot load native wrapper");
    const auto create=symbol<void*(*)(void*,intptr_t)>(native,"CreatePlugInstance");
    void* plugin=create(host.data(),42); require(plugin,"Native factory empty");
    Dl_info nativeImage{}; require(dladdr(reinterpret_cast<void*>(create),&nativeImage),"Cannot locate wrapper base");
    const auto parameter=method<int32_t(*)(void*,int,int,uint32_t)>(plugin,0xf8);
    const auto state=method<void(*)(void*,void*,int)>(plugin,0xe0);
    const auto dispatcher=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(plugin,0xd0);
    const auto trigger=method<uintptr_t(*)(void*,void*,intptr_t)>(plugin,0x110);
    const auto render=method<int(*)(void*,uintptr_t,float*,int*)>(plugin,0x130);
    const auto release=method<void(*)(void*,uintptr_t)>(plugin,0x118);
    const auto kill=method<void(*)(void*,uintptr_t)>(plugin,0x120);
    std::array<void*,5> streamMethods{}; streamMethods[3]=reinterpret_cast<void*>(&readStream);streamMethods[4]=reinterpret_cast<void*>(&writeStream);
    Stream stream{streamMethods.data(),{},0}; state(plugin,&stream,1);
    require(stream.bytes.size()==460 && load<uint32_t>(stream.bytes.data(),0)==14,"Unreviewed native state layout");
    stream.bytes[92]=1;
    void* originalEngine=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL); require(originalEngine,"Cannot resolve native engine globals");
    auto* nativeNoise=symbol<NoiseGlobals*>(originalEngine,"p2");
    void* rebuilt=dlopen(argv[3],RTLD_NOW|RTLD_LOCAL); require(rebuilt,"Cannot load rebuilt core");
    auto* modelNoise=symbol<NoiseGlobals*>(rebuilt,"p2");
    const auto modelCreate=symbol<decltype(&vl_osc_core_create)>(rebuilt,"vl_osc_core_create");
    const auto modelDestroy=symbol<decltype(&vl_osc_core_destroy)>(rebuilt,"vl_osc_core_destroy");
    const auto modelParameter=symbol<decltype(&vl_osc_core_parameter)>(rebuilt,"vl_osc_core_parameter");
    const auto modelRestore=symbol<decltype(&vl_osc_core_restore_prefix)>(rebuilt,"vl_osc_core_restore_prefix");
    const auto modelSave=symbol<decltype(&vl_osc_core_save_prefix)>(rebuilt,"vl_osc_core_save_prefix");
    const auto modelDerived=symbol<decltype(&vl_osc_core_derived)>(rebuilt,"vl_osc_core_derived");
    const auto modelRate=symbol<decltype(&vl_osc_core_set_sample_rate)>(rebuilt,"vl_osc_core_set_sample_rate");
    const auto modelRandom=symbol<decltype(&vl_osc_core_random_state)>(rebuilt,"vl_osc_core_random_state");
    const auto modelTrigger=symbol<decltype(&vl_osc_core_trigger)>(rebuilt,"vl_osc_core_trigger");
    const auto modelRender=symbol<decltype(&vl_osc_core_render)>(rebuilt,"vl_osc_core_render");
    const auto modelRelease=symbol<decltype(&vl_osc_core_release)>(rebuilt,"vl_osc_core_release");
    const auto modelKill=symbol<decltype(&vl_osc_core_kill)>(rebuilt,"vl_osc_core_kill");
    const auto modelPhases=symbol<decltype(&vl_osc_core_voice_phases)>(rebuilt,"vl_osc_core_voice_phases");
    const auto modelCount=symbol<decltype(&vl_osc_core_voice_count)>(rebuilt,"vl_osc_core_voice_count");
    const auto modelCustom=symbol<decltype(&vl_osc_core_custom_wave)>(rebuilt,"vl_osc_core_custom_wave");
    const auto modelTables=symbol<decltype(&vl_osc_core_host_tables)>(rebuilt,"vl_osc_core_host_tables");
    const auto modelMode=symbol<decltype(&vl_osc_core_render_mode)>(rebuilt,"vl_osc_core_render_mode");
    const auto modelPayloadRestore=symbol<decltype(&vl_osc_core_restore_payload)>(rebuilt,"vl_osc_core_restore_payload");
    const auto modelPayloadSave=symbol<decltype(&vl_osc_core_save_payload)>(rebuilt,"vl_osc_core_save_payload");
    auto* model=modelCreate(&computeLR,nullptr); require(model,"Cannot create rebuilt core");
    std::array<const float*,6> tables;for (size_t i=0;i<6;++i) tables[i]=waveIdentities[i].data();
    require(modelTables(model,tables.data()),"Cannot configure rebuilt host tables");
    const auto synchronizeRandom=[&] {
      vl_osc_random_state random;
      std::memcpy(random.words,static_cast<const char*>(nativeImage.dli_fbase)+0x2f20b0,sizeof(random.words));
      random.index=load<uint32_t>(nativeImage.dli_fbase,0x257370);
      random.seed=load<uint32_t>(nativeImage.dli_fbase,0x2884bc);
      random.previous_seed=load<uint32_t>(nativeImage.dli_fbase,0x256f98);
      // A not-yet-initialized native generator is initialized by one native
      // Random(1) invocation, without changing the installed file.
      if (random.index>624 || random.seed!=random.previous_seed) {
        reinterpret_cast<uintptr_t(*)(int)>(static_cast<char*>(nativeImage.dli_fbase)+0x16210)(1);
        std::memcpy(random.words,static_cast<const char*>(nativeImage.dli_fbase)+0x2f20b0,sizeof(random.words));
        random.index=load<uint32_t>(nativeImage.dli_fbase,0x257370);
        random.seed=load<uint32_t>(nativeImage.dli_fbase,0x2884bc);
        random.previous_seed=load<uint32_t>(nativeImage.dli_fbase,0x256f98);
      }
      require(modelRandom(model,&random),"Cannot set rebuilt RNG fixture");
    };
    const auto comparePhases=[&](uintptr_t nativeVoice,vl_osc_voice* modelVoice) {
      std::array<uint32_t,6> phases; uint8_t stereo;
      modelPhases(modelVoice,phases.data(),&stereo);
      if (std::memcmp(phases.data(),reinterpret_cast<void*>(nativeVoice+16),24)!=0) {
        for (int i=0;i<6;++i) std::cerr<<"phase["<<i<<"] native="<<load<uint32_t>(reinterpret_cast<void*>(nativeVoice),16+i*4)<<" model="<<phases[i]<<'\n';
        throw std::runtime_error("Raw voice phases differ");
      }
      require(stereo==load<uint8_t>(reinterpret_cast<void*>(nativeVoice),40),"Raw voice stereo differs");
    };
    constexpr std::array<int,21> mins{-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0};
    constexpr std::array<int,21> maxs{64,6,24,100,64,50,128,64,6,24,100,64,50,128,64,6,24,100,64,50,64};
    std::mt19937 random(90117); size_t cases=0,values=0,updates=0,stateCases=0,customCases=0,editorUpdates=0,legacyCases=0;
    std::array<float,16384> customWave{};
    const auto compareDerived=[&] {
      std::array<vl_osc_derived,3> result; uint32_t ring; uint8_t stereo;
      modelDerived(model,result.data(),&ring,&stereo);
      require(ring==load<uint32_t>(plugin,0x208) && stereo==load<uint8_t>(plugin,0x210),"Derived ring/stereo differs");
      for (int i=0;i<3;++i) {
        const size_t offset=0x188+i*40;
        require(std::memcmp(&result[i],static_cast<const char*>(plugin)+offset,24)==0,"Derived control arithmetic differs");
        require(result[i].noise==load<uint8_t>(plugin,offset+32) && result[i].non_sine==load<uint8_t>(plugin,offset+33),"Derived waveform flags differ");
      }
    };
    for (int test=0;test<180;++test) {
      if (test==60 || test==120) {
        for (size_t i=0;i<customWave.size();++i) customWave[i]=std::sin(float(i)*0.0003834952f)+0.13f*std::cos(float(i)*0.001917476f);
        if (test==120) for (auto& sample:customWave) sample*=0.75f;
        dispatcher(plugin,10,0,reinterpret_cast<intptr_t>(customWave.data())); modelCustom(model,customWave.data());++customCases;
      }
      if (test==150) {dispatcher(plugin,10,0,0);modelCustom(model,nullptr);++customCases;}
      for (int i=0;i<21;++i) {
        const int value=mins[i]+static_cast<int>(random()%uint32_t(maxs[i]-mins[i]+1));
        std::memcpy(stream.bytes.data()+4+i*4,&value,4);
      }
      for (int i=0;i<3;++i) stream.bytes[88+i]=test%2;
      stream.bytes[91]=test%3; stream.bytes[92]=(test%3)!=0;
      // Native editor Save zero-fills its 364-byte record; Restore transfers
      // only five 68-byte groups and globals at +348/+352/+360. Mutate the
      // ignored/reserved input words rather than trusting default zero bytes.
      for (size_t offset=432;offset<440;++offset) stream.bytes[4+offset]=uint8_t(random()|1u);
      for (size_t offset=448;offset<452;++offset) stream.bytes[4+offset]=uint8_t(random()|1u);
      stream.cursor=0;state(plugin,&stream,0); require(modelRestore(model,stream.bytes.data()+4,89),"Rebuilt prefix restore failed");
      require(modelPayloadRestore(model,stream.bytes.data()+4,456),"Rebuilt payload restore failed");
      std::array<uint8_t,89> prefix;require(modelSave(model,prefix.data(),prefix.size()),"Rebuilt prefix save failed");
      require(std::memcmp(prefix.data(),stream.bytes.data()+4,89)==0,"Preset prefix differs");++stateCases;compareDerived();
      for (int step=0;step<12;++step) {
        const int index=random()%21;const int normalized=random()%1073741825u;
        require(parameter(plugin,index,normalized,49)==modelParameter(model,index,normalized,49),"Normalized update differs");
        require(parameter(plugin,index,0,2)==modelParameter(model,index,0,2),"Control get differs");compareDerived();++updates;
      }
      for (int step=0;step<12;++step) {
        const int index=21+int(random()%93),value=int(random()%1073741825u);
        require(parameter(plugin,index,value,49)==modelParameter(model,index,value,49),"Editor normalized update differs");
        require(parameter(plugin,index,0,2)==modelParameter(model,index,0,2),"Editor get differs");++editorUpdates;
      }
      for (int index=0;index<114;++index) {
        const int nativeValue=parameter(plugin,index,0,2),modelValue=modelParameter(model,index,0,2);
        if (nativeValue!=modelValue) {std::cerr<<"test="<<test<<" parameter="<<index<<" native="<<nativeValue<<" model="<<modelValue<<'\n';throw std::runtime_error("114-control state differs");}
      }
      Stream saved{streamMethods.data(),{},0};state(plugin,&saved,1);
      std::array<uint8_t,456> payload;require(modelPayloadSave(model,payload.data(),payload.size()),"Rebuilt payload save failed");
      require(std::memcmp(payload.data(),saved.bytes.data()+4,89)==0 && std::memcmp(payload.data()+92,saved.bytes.data()+96,364)==0,
              "Full preset semantic bytes differ");
      // Reset editor fields to the saved case before trigger; editor modulation
      // is intentionally outside this raw-voice test and reconstruction.
      stream.cursor=0;state(plugin,&stream,0);require(modelPayloadRestore(model,stream.bytes.data()+4,456),"Case payload reset failed");
      for (int index=0;index<21;++index) {const int value=parameter(plugin,index,0,2);modelParameter(model,index,value,1);}
      dispatcher(plugin,1,0,(test%2)*2);modelMode(model,(test%2)*2);
      const int sampleRate=std::array<int,5>{22050,44100,48000,96000,192000}[test%5];
      dispatcher(plugin,4,0,sampleRate);require(modelRate(model,sampleRate),"Rebuilt sample rate failed");
      synchronizeRandom();
      std::array<VoiceParameters,2> parameters;
      parameters[0].final.pitch=static_cast<float>(test%70)*100.0f;
      parameters[1].final.pitch=parameters[0].final.pitch+701.25f;
      std::array<uintptr_t,2> nativeVoices;std::array<vl_osc_voice*,2> modelVoices;
      for (int i=0;i<2;++i) {
        nativeVoices[i]=trigger(plugin,&parameters[i],100+i);modelVoices[i]=modelTrigger(model,100+i);
        require(nativeVoices[i] && modelVoices[i],"Voice trigger failed");comparePhases(nativeVoices[i],modelVoices[i]);
      }
      require(modelCount(model)==2,"Two live model voices missing");
      for (int block=0;block<6;++block) {
        const int voice=block%2;int frames=std::array<int,6>{0,1,17,64,129,511}[block];
        std::vector<float> original(size_t(frames)*2+2,0.25f),compiled=original;
        // Separate engines have equivalent shared RNGs. Fixture synchronization
        // reads native state and sets only the independently rebuilt artifact.
        modelNoise->seed=nativeNoise->seed;
        render(plugin,nativeVoices[voice],original.data(),&frames);
        require(modelRender(model,modelVoices[voice],parameters[voice].final.pitch,compiled.data(),frames),"Rebuilt raw render failed");
        if (std::memcmp(original.data(),compiled.data(),original.size()*4)!=0) {
          for (size_t i=0;i<original.size();++i) if (std::bit_cast<uint32_t>(original[i])!=std::bit_cast<uint32_t>(compiled[i])) {
            std::cerr << "test="<<test<<" block="<<block<<" sample="<<i<<" native="<<std::setprecision(9)<<original[i]<<" compiled="<<compiled[i]<<'\n';break;
          }
          throw std::runtime_error("Native HQ raw voice audio differs");
        }
        comparePhases(nativeVoices[voice],modelVoices[voice]);
        require(modelNoise->seed==nativeNoise->seed,"Small engine noise sequence differs");
        values+=original.size();++cases;
        if (!stream.bytes[92]) ++legacyCases;
        if (block==3) {release(plugin,nativeVoices[0]);modelRelease(model,modelVoices[0]);}
      }
      for (int i=0;i<2;++i) {kill(plugin,nativeVoices[i]);modelKill(model,modelVoices[i]);}
      require(modelCount(model)==0,"Model voices survived kill");
    }
    modelDestroy(model);method<void(*)(void*)>(plugin,0xc8)(plugin);
    dlclose(rebuilt);dlclose(originalEngine);dlclose(native);
    std::cout << "{\"status\":\"passed\",\"real_native_factory\":true,\"compiled_dylib_replayed\":true,\"core_parameter_updates\":"<<updates
              <<",\"integrated_editor_control_storage_updates\":"<<editorUpdates
              <<",\"version14_prefix_restores\":"<<stateCases<<",\"hq_voice_render_cases\":"<<(cases-legacyCases)<<",\"audio_floats_exact\":"<<values
              <<",\"legacy_voice_render_cases\":"<<legacyCases<<",\"version14_preserved_field_bytes\":441,\"version14_canonical_reserved_bytes\":12"
              <<",\"version14_defined_output_bytes\":453,\"reserved_input_mutation_cases\":"<<stateCases<<",\"parameter_contract_size\":114"
              <<",\"custom_wave_replacements_and_fallback\":"<<customCases<<",\"simultaneous_voices\":2,\"release_kill_verified\":true,\"random_phase_and_noise_verified\":true,\"full_plugin_recompiled\":false}\n";
    return 0;
  } catch (const std::exception& error) { std::cerr<<error.what()<<'\n';return 1; }
 }
}
