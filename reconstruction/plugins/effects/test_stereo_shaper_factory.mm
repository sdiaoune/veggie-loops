#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This private measured-layout test requires macOS arm64.
#endif
#include "stereo_shaper_plugin.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>
#include <stdexcept>

namespace {
void require(bool value,const char*text){if(!value)throw std::runtime_error(text);}
template<class T>T load(const void* p,size_t offset){T result;std::memcpy(&result,static_cast<const char*>(p)+offset,sizeof(T));return result;}
template<class F>F method(void*p,size_t offset){return reinterpret_cast<F>(load<void**>(p,0)[offset/8]);}
std::string hash(const char* path){std::ifstream file(path,std::ios::binary);require(file.good(),"Missing source");std::vector<std::uint8_t>bytes{std::istreambuf_iterator<char>(file),{}};std::array<std::uint8_t,32>digest{};CC_SHA256(bytes.data(),CC_LONG(bytes.size()),digest.data());std::ostringstream out;for(auto b:digest)out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(b);return out.str();}
std::array<void*,96>hostTable{};std::array<void*,32>pathTable{};
struct Object{void**vmt;};Object paths{pathTable.data()};
const char*privatePath=nullptr;bool sideAvailable=true;std::vector<float>sideBuffer;std::vector<uint32_t>sideFlags;intptr_t sideSender=0,sideIndex=0;
#pragma pack(push,4)
struct IOBuffer{float*buffer;uint32_t flags;};
#pragma pack(pop)
extern "C" intptr_t noop(){return 0;}
extern "C" intptr_t hostDispatch(void*,intptr_t,intptr_t id,intptr_t,intptr_t){if(id==71)return reinterpret_cast<intptr_t>(&paths);if(id==29)return reinterpret_cast<intptr_t>(privatePath);if(id==50)return 4;return 0;}
extern "C" void getOutBuffer(void*,intptr_t sender,intptr_t index,IOBuffer*io){sideFlags.push_back(io->flags);sideSender=sender;sideIndex=index;if(io->flags==0)io->buffer=sideAvailable?sideBuffer.data():nullptr;}
struct Stream{void**vmt;std::array<uint8_t,36>bytes{};size_t cursor=0,calls=0;};
extern "C" int32_t streamRead(Stream*s,void*out,uint32_t length,uint32_t*done){require(s->cursor+length<=s->bytes.size(),"Read outside valid framing");std::memcpy(out,s->bytes.data()+s->cursor,length);s->cursor+=length;++s->calls;if(done)*done=length;return 0;}
extern "C" int32_t streamWrite(Stream*s,const void*in,uint32_t length,uint32_t*done){require(s->cursor+length<=s->bytes.size(),"Write outside valid framing");std::memcpy(s->bytes.data()+s->cursor,in,length);s->cursor+=length;++s->calls;if(done)*done=length;return 0;}
void word(uint8_t*p,uint32_t value){for(size_t i=0;i<4;++i)p[i]=uint8_t(value>>(i*8));}
template<class T>void same(T actual,T expected,const char* field,size_t count){if(std::memcmp(&actual,&expected,sizeof(T))!=0){std::cerr<<"Mismatch "<<field<<" case "<<count<<" actual="<<std::hexfloat<<actual<<" expected="<<expected<<'\n';throw std::runtime_error(field);}}
}
int main(int argc,char**argv){@autoreleasepool {try {
  require(argc==4,"Usage: test_stereo_shaper_factory <source> <private path/> <rebuilt numerical library>");require(hash(argv[1])=="0087d215734c061be930d5a01282e2a3654306cc595f8acb8ba3142051169804","Source SHA mismatch");
  [NSApplication sharedApplication];privatePath=argv[2];require(hash("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","DSP dependency SHA mismatch");hostTable.fill(reinterpret_cast<void*>(&noop));pathTable.fill(reinterpret_cast<void*>(&noop));hostTable[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostTable[0x1f0/8]=reinterpret_cast<void*>(&getOutBuffer);
  alignas(16)std::array<std::byte,512>host{};void**table=hostTable.data();std::memcpy(host.data(),&table,8);
  void*library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(library,"dlopen failed");auto factory=reinterpret_cast<void*(*)(void*,intptr_t)>(dlsym(library,"CreatePlugInstance"));require(factory,"Factory missing");void*native=factory(host.data(),0x564c);require(native,"Factory failed");
  using Parameter=int32_t(*)(void*,int32_t,int32_t,uint32_t);using Render=void(*)(void*,const float*,float*,int32_t);using Dispatch=intptr_t(*)(void*,intptr_t,intptr_t,intptr_t);
  const auto param=method<Parameter>(native,0xf8);const auto render=method<Render>(native,0x100);const auto dispatch=method<Dispatch>(native,0xd0);
  void*rebuilt=dlopen(argv[3],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Cannot load rebuilt library");
  const auto bind=[&](const char*name){void*symbol=dlsym(rebuilt,name);require(symbol,"Missing rebuilt numerical export");return symbol;};
  auto create=reinterpret_cast<decltype(&vl_stereo_shaper_create)>(bind("vl_stereo_shaper_create"));
  auto destroy=reinterpret_cast<decltype(&vl_stereo_shaper_destroy)>(bind("vl_stereo_shaper_destroy"));
  auto parameter=reinterpret_cast<decltype(&vl_stereo_shaper_parameter)>(bind("vl_stereo_shaper_parameter"));
  auto process=reinterpret_cast<decltype(&vl_stereo_shaper_render)>(bind("vl_stereo_shaper_render"));
  auto sampleRate=reinterpret_cast<decltype(&vl_stereo_shaper_sample_rate)>(bind("vl_stereo_shaper_sample_rate"));
  auto resume=reinterpret_cast<decltype(&vl_stereo_shaper_resume)>(bind("vl_stereo_shaper_resume"));
  auto routing=reinterpret_cast<decltype(&vl_stereo_shaper_routing)>(bind("vl_stereo_shaper_routing"));
  auto save=reinterpret_cast<decltype(&vl_stereo_shaper_save_state)>(bind("vl_stereo_shaper_save_state"));
  auto restoreState=reinterpret_cast<decltype(&vl_stereo_shaper_restore_state)>(bind("vl_stereo_shaper_restore_state"));
  auto*clone=create();require(clone,"Rebuilt instance creation failed");
  void*form=load<void*>(native,0xc0);const std::array<int32_t,6>defaults{0,12800,12800,0,0,0};
  for(int i=0;i<6;++i){void*knob=load<void*>(form,0x948+size_t(i)*8);require(load<int32_t>(knob,0x408)==(i<4?-25600:-4096)&&load<int32_t>(knob,0x40c)==(i<4?25600:4096)&&load<int32_t>(knob,0x410)==defaults[size_t(i)],"Original control range/default differs");same(load<double>(knob,0x430),i<4?1.0/51200.0:1.0/8192.0,"controlScale",0);}
  struct StateData{std::array<int32_t,6>raw{0,12800,12800,0,0,0};int32_t send=0,prePost=0;}model;
  std::mt19937 random(0x564c5353);size_t renders=0,frames=0,parameters=0,stateCases=0,sendCases=0;
  const auto checkState=[&]{for(int i=0;i<6;++i){int32_t value=0;require(parameter(clone,i,0,2,&value),"Rebuilt getter failed");same(value,param(native,i,0,2),"getter",parameters);same(value,model.raw[size_t(i)],"storedRaw",parameters);same(load<int32_t>(load<void*>(form,0x948+size_t(i)*8),0x410),value,"originalControlValue",parameters);}};
  const auto rebuiltChange=[&](int index,int value,uint32_t flags=1){int32_t result=0;require(parameter(clone,index,value,flags,&result),"Rebuilt set rejected valid value");return result;};
  const auto rebuiltResume=[&]{require(resume(clone),"Rebuilt resume failed");};
  const auto change=[&](int index,int value){same(param(native,index,value,17),int32_t(value),"rawReturn",parameters);same(rebuiltChange(index,value),int32_t(value),"rebuiltRawReturn",parameters);model.raw[size_t(index)]=value;++parameters;};
  const auto compare=[&](int count,bool alias,bool offset){const size_t start=offset?1:0;std::vector<float>input(size_t(count)*2+16),a(input.size(),1234),b(a);for(float&v:input)v=float(int32_t(random()%65536)-32768)/8192;
    for(size_t i=0;i<input.size();i+=13)input[i]=(i&1)?-0.0f:0.0f;
    const auto beforeInput=input;
    const auto beforeActual=alias?input:a,beforeRebuilt=alias?input:b;
    sideBuffer.assign(size_t(count)*2+8,0.25f);auto expectedSide=sideBuffer;sideFlags.clear();
    if(alias){a=input;b=input;render(native,a.data()+start,a.data()+start,count);require(process(clone,b.data()+start,b.data()+start,count,model.send>0&&sideAvailable?expectedSide.data():nullptr),"Rebuilt alias render rejected");}else {render(native,input.data()+start,a.data()+start,count);require(process(clone,input.data()+start,b.data()+start,count,model.send>0&&sideAvailable?expectedSide.data():nullptr),"Rebuilt render rejected");}
    for(size_t i=0;i<a.size();++i)if(std::bit_cast<uint32_t>(a[i])!=std::bit_cast<uint32_t>(b[i])){std::cerr<<"frame="<<count<<" index="<<i<<" alias="<<alias<<" offset="<<offset<<"\n";same(a[i],b[i],"audio",renders);}
    for(size_t i=0;i<a.size();++i)if(i<start||i>=start+size_t(count)*2){same(a[i],beforeActual[i],"originalMainGuard",renders);same(b[i],beforeRebuilt[i],"rebuiltMainGuard",renders);}
    require(std::memcmp(input.data(),beforeInput.data(),input.size()*sizeof(float))==0,"Original disjoint input changed");
    for(size_t i=size_t(count)*2;i<sideBuffer.size();++i){same(sideBuffer[i],0.25f,"originalSideGuard",renders);same(expectedSide[i],0.25f,"rebuiltSideGuard",renders);}
    if(model.send>0){require(sideFlags==std::vector<uint32_t>{0,1},"Side output lock/unlock sequence");require(sideSender==0x564c && sideIndex==model.send,"Side output identity");for(size_t i=0;i<size_t(count)*2;++i)same(sideBuffer[i],expectedSide[i],"sideResidual",renders);++sendCases;}else require(sideFlags.empty(),"Inactive side output called host");
    ++renders;frames+=count;checkState();
  };
  checkState();const std::array<int,20>lengths{0,1,2,3,4,7,8,9,15,16,17,31,32,33,63,64,65,257,512,1024};
  for(size_t sequence=0;sequence<512;++sequence){
    for(int i=0;i<4;++i)change(i,int(random()%51201)-25600);
    for(size_t j=0;j<4;++j)compare(lengths[(sequence+j)%lengths.size()],(j&1)!=0,(sequence&1)!=0);
    if(sequence%17==0){dispatch(native,2,0,0);rebuiltResume();checkState();}
  }
  std::cout<<"matrix_pass parameters="<<parameters<<" callbacks="<<renders<<" frames="<<frames<<'\n';
  for(int i=0;i<4;++i)change(i,i==1||i==2?12800:0);compare(1024,false,false);dispatch(native,2,0,0);rebuiltResume();
  for(int raw:{-4096,-4095,-2048,-1,0,1,2048,4095,4096}){change(4,raw);checkState();for(int length:lengths)compare(length,(length&1)!=0,(raw&1)!=0);}
  std::cout<<"delay_pass parameters="<<parameters<<" callbacks="<<renders<<" frames="<<frames<<'\n';change(4,0);
  for(int raw:{-4096,-4095,-2048,-1,0,1,2048,4095,4096}){change(5,raw);checkState();for(int length:lengths)compare(length,(length&1)!=0,(raw&1)!=0);}
  std::cout<<"phase_pass parameters="<<parameters<<" callbacks="<<renders<<" frames="<<frames<<'\n';
  std::array<void*,5>streamVmt{};streamVmt[3]=reinterpret_cast<void*>(&streamRead);streamVmt[4]=reinterpret_cast<void*>(&streamWrite);Stream stream{streamVmt.data()};using State=void(*)(void*,void*,int32_t);const auto state=method<State>(native,0xe0);
  const auto compareSave=[&]{stream.calls=stream.cursor=0;state(native,&stream,1);require(stream.calls==2&&stream.cursor==36,"Save framing");std::array<uint8_t,36>expected{};for(size_t i=0;i<6;++i)word(expected.data()+4+4*i,uint32_t(model.raw[i]));word(expected.data()+28,uint32_t(model.send));word(expected.data()+32,uint32_t(model.prePost));if(expected!=stream.bytes)for(size_t k=0;k<9;++k)std::cerr<<"stateWord"<<k<<" actual="<<load<uint32_t>(stream.bytes.data(),k*4)<<" model="<<load<uint32_t>(expected.data(),k*4)<<'\n';require(expected==stream.bytes,"Save bytes mismatch");std::array<uint8_t,36>rebuiltBytes{};require(save(clone,rebuiltBytes.data(),rebuiltBytes.size())&&rebuiltBytes==expected,"Rebuilt save differs");};compareSave();
  const auto restore=[&]{for(size_t i=0;i<6;++i)word(stream.bytes.data()+4+4*i,uint32_t(model.raw[i]));word(stream.bytes.data(),0);word(stream.bytes.data()+28,uint32_t(model.send));word(stream.bytes.data()+32,uint32_t(model.prePost));stream.calls=stream.cursor=0;state(native,&stream,0);require(stream.calls==2&&stream.cursor==36,"Restore framing");require(restoreState(clone,stream.bytes.data(),stream.bytes.size()),"Rebuilt restore rejected valid source state");++stateCases;compareSave();};
  for(size_t sequence=0;sequence<256;++sequence){
    const std::array<int32_t,5>rates{22050,44100,48000,96000,192000};const auto rate=rates[sequence%rates.size()];dispatch(native,4,0,rate);require(sampleRate(clone,rate),"Rebuilt rate change rejected");
    for(int i=0;i<4;++i)model.raw[size_t(i)]=int(random()%51201)-25600;
    model.raw[4]=int(random()%8193)-4096;model.raw[5]=int(random()%8193)-4096;model.prePost=int(sequence&1);model.send=int(sequence%4);sideAvailable=(sequence%3)!=0;
    restore();for(size_t j=0;j<4;++j)compare(lengths[(sequence+j)%lengths.size()],(j&1)!=0,(sequence&1)!=0);
    if(sequence%11==0){dispatch(native,2,0,0);rebuiltResume();checkState();}
  }
  std::cout<<"mixed_pass parameters="<<parameters<<" callbacks="<<renders<<" frames="<<frames<<" restored="<<stateCases<<" sends="<<sendCases<<'\n';
  model.send=0;model.prePost=0;model.raw={0,12800,12800,0,0,0};restore();dispatch(native,4,0,44100);require(sampleRate(clone,44100),"Rebuilt rate change rejected");
  for(int value=-25600;value<=25600;++value){change(0,value);compare(0,false,false);dispatch(native,2,0,0);rebuiltResume();compare(1,(value&1)!=0,false);}
  for(int value=-4096;value<=4096;++value){change(4,value);checkState();compare(1,false,(value&1)!=0);}
  change(4,0);
  for(int value=-4096;value<=4096;++value){change(5,value);checkState();compare(1,(value&1)!=0,false);if(value%257==0){dispatch(native,2,0,0);rebuiltResume();}}
  std::cout<<"exhaustive_pass parameters="<<parameters<<" callbacks="<<renders<<" frames="<<frames<<'\n';
  for(int index=0;index<6;++index){
    const int32_t minimum=index<4?-25600:-4096, maximum=index<4?25600:4096,range=maximum-minimum;
    for(size_t k=0;k<1024;++k){const int32_t unit=int32_t(random()%1073741825u);const int32_t expected=int32_t(std::nearbyint((double(unit)*0x1p-30)*double(range)))+minimum;const int32_t actual=param(native,index,unit,49);same(actual,expected,"normalizedReturn",parameters);same(rebuiltChange(index,unit,33),expected,"rebuiltNormalized",parameters);model.raw[size_t(index)]=expected;++parameters;compare(1,(k&1)!=0,(k&2)!=0);}
    for(int32_t unit:{0,536870911,536870912,536870913,1073741824}){const int32_t expected=int32_t(std::nearbyint((double(unit)*0x1p-30)*double(range)))+minimum;same(param(native,index,unit,49),expected,"normalizedEndpoint",parameters);same(rebuiltChange(index,unit,33),expected,"rebuiltNormalized",parameters);model.raw[size_t(index)]=expected;++parameters;compare(0,false,false);}
  }
  std::cout<<"complete_numerical_pass parameters="<<parameters<<" callbacks="<<renders<<" frames="<<frames<<" restores="<<stateCases<<" side_outputs="<<sendCases<<'\n';
  int32_t unused=777;require(!parameter(clone,6,0,1,&unused)&&unused==777,"Rejected index changed result");
  std::array<uint8_t,36>before{},after{};require(save(clone,before.data(),before.size()),"Save before rejection");auto invalid=before;word(invalid.data()+4,25601);require(!restoreState(clone,invalid.data(),invalid.size()),"Invalid parameter state accepted");require(save(clone,after.data(),after.size())&&before==after,"Invalid state changed serialized data");
  std::array<float,16>overlap{};const auto original=overlap;require(!process(clone,overlap.data(),overlap.data()+1,4,nullptr)&&overlap==original,"Partial main overlap accepted");require(!process(clone,overlap.data(),overlap.data()+8,4,overlap.data())&&overlap==original,"Side overlap accepted");
  require(routing(clone,0,0),"Valid own routing rejected");require(!routing(clone,4,0)&&!routing(clone,0,2),"Invalid own routing accepted");
  std::cout<<"{\"status\":\"passed\",\"actual_original_factory_created_and_destroyed\":true,\"compiled_numerical_c_abi_compared\":true,\"parameter_control_cases\":"<<parameters<<",\"render_cases\":"<<renders<<",\"stereo_frames\":"<<frames<<",\"state_restores\":"<<stateCases<<",\"synthetic_host_side_output_sequences\":"<<sendCases<<",\"full_plugin_equivalence\":false}\n";
  destroy(clone);method<void(*)(void*)>(native,0xc8)(native);dlclose(rebuilt);dlclose(library);return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}
