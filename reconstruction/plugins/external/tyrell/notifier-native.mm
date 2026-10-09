// Private read-only notifier descriptor and queue mapping.
#if !defined(__APPLE__) || !defined(__x86_64__)
#error Intel Tyrell layout only.
#endif
#define main vl_probe_unused_main
#include "../../../../reconstruction/plugins/common/vst2_probe.mm"
#undef main
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <bit>
#include <limits>
template<class T>T field(const void*p,size_t o){T v;std::memcpy(&v,static_cast<const char*>(p)+o,sizeof v);return v;}
static std::string sha(const std::string&path){std::ifstream f(path,std::ios::binary);require(bool(f),"No target");CC_SHA256_CTX c;CC_SHA256_Init(&c);std::array<char,65536>b;while(f.read(b.data(),b.size())||f.gcount())CC_SHA256_Update(&c,b.data(),CC_LONG(f.gcount()));require(f.eof(),"Read failed");std::array<unsigned char,32>d;CC_SHA256_Final(d.data(),&c);std::string h;for(auto x:d){h+="0123456789abcdef"[x>>4];h+="0123456789abcdef"[x&15];}return h;}
#include "notifier-storage.h"
#include <xmmintrin.h>
#include <cfenv>

namespace {
using Notify=void(*)(void*,int32_t,float,float,uint8_t);
struct Session {
 Bundle bundle;Instance instance;uintptr_t base{};void* audio{};void* config{};
 void* descriptors{};void* raw{};void* pointers{};void* specialMap{};
 void* records{};void* queue{};void* publicMap{};
 int32_t count{},specialCount{},publicCount{};
 Notify forward{},direct{};
 Session(const char* path){
  require(sha(std::string(path)+"/Contents/MacOS/TyrellN6")=="a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54","Target identity");
  transport.sampleRate=48000;transport.tempo=120;
  auto u=CFURLCreateFromFileSystemRepresentation(nullptr,reinterpret_cast<const UInt8*>(path),std::strlen(path),true);require(u,"URL");bundle.value=CFBundleCreate(nullptr,u);CFRelease(u);require(bundle.value&&CFBundleLoadExecutable(bundle.value),"Bundle load");
  auto entry=reinterpret_cast<Effect*(*)(Dispatch)>(CFBundleGetFunctionPointerForName(bundle.value,CFSTR("VSTPluginMain")));require(entry,"Entry");Dl_info image{};require(dladdr(reinterpret_cast<void*>(entry),&image)&&image.dli_fbase,"Base");base=reinterpret_cast<uintptr_t>(image.dli_fbase);require(reinterpret_cast<uintptr_t>(entry)-base==0x3ddb0,"Entry address");
  instance.value=entry(host);auto*e=instance.value;require(e&&e->magic==0x56737450,"Factory");e->dispatcher(e,0,0,0,nullptr,0);instance.opened=true;require(std::fegetround()==FE_TONEAREST&&(_mm_getcsr()&0xe040)==0,"Nearest-even/gradual FP required");
  void*manager=field<void*>(e->object,0x138);require(manager,"Manager");audio=field<void*>(manager,0x40);require(audio&&audio==field<void*>(manager,0x48),"Receiver identity");auto*vt=field<void*>(audio,0);require(reinterpret_cast<uintptr_t>(vt)-base==0x3173b0,"Receiver VFT");forward=reinterpret_cast<Notify>(field<void*>(vt,0x298));direct=reinterpret_cast<Notify>(field<void*>(vt,0x2c8));require(reinterpret_cast<uintptr_t>(forward)-base==0x154430&&reinterpret_cast<uintptr_t>(direct)-base==0x154450,"Notifier identity");
  config=field<void*>(audio,0x428);require(config,"Configuration");descriptors=field<void*>(audio,0x4e0);require(descriptors==field<void*>(config,0),"Descriptor identity");raw=field<void*>(config,0x10);pointers=field<void*>(config,0x18);specialMap=field<void*>(config,0x28);queue=field<void*>(config,0x30);records=field<void*>(config,0x38);publicMap=field<void*>(config,0x78);count=field<int32_t>(audio,0x4c4);specialCount=field<int32_t>(audio,0x4cc);publicCount=field<int32_t>(audio,0x4c8);require(count==213&&specialCount==82&&publicCount==92,"Counts");
  const auto bytes=[](void*p,size_t n){return static_cast<unsigned char*>(p)+n;};
  require(raw==bytes(config,400)&&pointers==bytes(raw,size_t(count)*4)&&specialMap==bytes(pointers,size_t(count)*8)&&queue==bytes(specialMap,size_t(count)*4)&&records==bytes(queue,size_t(specialCount)*4)&&field<void*>(config,0x48)==bytes(records,size_t(specialCount)*16),"Allocated queue/record geometry");
 }
 auto metadata()const{std::array<VLTyrellNotifyDescriptor,213>d{};for(int32_t i=0;i<count;++i){auto*p=static_cast<unsigned char*>(descriptors)+size_t(i)*116;d[i]={field<int32_t>(p,72),field<uint32_t>(p,92),field<float>(p,76),field<float>(p,80),field<int32_t>(specialMap,size_t(i)*4),field<void*>(pointers,size_t(i)*8)!=nullptr};}return d;}
 VLTyrellNotifyState snapshot()const{
  VLTyrellNotifyState s{};s.internal_count=count;s.special_count=specialCount;s.queue_count=field<int32_t>(config,0x20);s.dirty=field<int32_t>(config,0x50);s.immediate=field<uint8_t>(audio,0x4bc);s.depth=field<int32_t>(audio,0x5a0);
  std::memcpy(s.raw,raw,size_t(count)*4);std::memcpy(s.special,records,size_t(specialCount)*16);std::memcpy(s.queue,queue,size_t(specialCount)*4);
  for(int32_t i=0;i<count;++i)if(auto*p=field<void*>(pointers,size_t(i)*8))s.pointee_bits[i]=field<uint32_t>(p,0);
  return s;
 }
 template<class T>void write(void*p,size_t n,T value){std::memcpy(static_cast<unsigned char*>(p)+n,&value,sizeof value);}
 void mode(int32_t q,uint8_t immediate,int32_t depth){write(config,0x20,q);write(audio,0x4bc,immediate);write(audio,0x5a0,depth);}
 struct Restore {
  Session&session;VLTyrellNotifyState saved;std::array<void*,213> savedPointers{};
  Restore(Session&s):session(s),saved(s.snapshot()){for(int32_t i=0;i<s.count;++i)savedPointers[i]=field<void*>(s.pointers,size_t(i)*8);}
  void apply(){auto&s=session;std::memcpy(s.raw,saved.raw,size_t(s.count)*4);std::memcpy(s.records,saved.special,size_t(s.specialCount)*16);std::memcpy(s.queue,saved.queue,size_t(s.specialCount)*4);for(int32_t i=0;i<s.count;++i)if(savedPointers[i])std::memcpy(savedPointers[i],&saved.pointee_bits[i],4);s.write(s.config,0x20,saved.queue_count);s.write(s.config,0x50,saved.dirty);s.write(s.audio,0x4bc,uint8_t(saved.immediate));s.write(s.audio,0x5a0,saved.depth);}
  void verify()const{const auto actual=session.snapshot();require(!std::memcmp(&saved,&actual,sizeof saved),"Captured scalar restoration differs");}
  ~Restore(){apply();}
 };
};
uint64_t ordinary=0,queued=0,synthetic=0,comparedWords=0,otherChanges=0,ordinaryOther=0,queuedOther=0;
void compare(Session&s,int32_t id,uint8_t force,float value,bool viaForward,bool expectFull){
 const auto metadata=s.metadata();auto expected=s.snapshot();const auto before=expected;VLTyrellNotifyResult plan{};
 require(vl_tyrell_notifier_storage(metadata.data(),&expected,id,force,value,&plan),"Prepared source rejected measured context");
 (viaForward?s.forward:s.direct)(s.audio,id,value,0,force);const auto actual=s.snapshot();
 const auto equal=[](const void*a,const void*b,size_t n){return std::memcmp(a,b,n)==0;};
 if(!equal(&actual.raw[id],&expected.raw[id],4)){std::cerr<<"id="<<id<<" value="<<std::hexfloat<<value<<" expectedraw="<<expected.raw[id]<<" actualraw="<<actual.raw[id]<<'\n';throw std::runtime_error("Raw differs");}
 require(equal(actual.special,expected.special,size_t(s.specialCount)*16),"Special record differs");require(equal(actual.queue,expected.queue,size_t(s.specialCount)*4)&&actual.queue_count==expected.queue_count,"Queue differs");require(actual.dirty==expected.dirty&&actual.immediate==expected.immediate&&actual.depth==expected.depth,"Configuration fields differ");
 require(actual.pointee_bits[id]==expected.pointee_bits[id],"Selected pointee differs");
 for(int32_t i=0;i<s.count;++i)if(i!=id&&(std::bit_cast<uint32_t>(actual.raw[i])!=std::bit_cast<uint32_t>(before.raw[i])||actual.pointee_bits[i]!=before.pointee_bits[i]))++otherChanges;
 if(expectFull)require(equal(&actual,&expected,sizeof actual),"Whole prepared state differs");
 comparedWords+=uint64_t(s.specialCount)*4+s.specialCount+6+2;
}
}
int main(int argc,char**argv){std::cout<<std::unitbuf;@autoreleasepool{try{
 require(argc==2,"Expected installed bundle");
 {
  Session s(argv[1]);require(s.snapshot().queue_count==-1,"Factory override expected");
  for(int32_t index=0;index<s.publicCount;++index){const int32_t id=field<int32_t>(s.publicMap,size_t(index)*4);const auto d=s.metadata()[id];
   for(float fraction:{0.0f,.125f,.25f,.5f,.75f,.875f,1.0f}){float value=d.minimum+(d.maximum-d.minimum)*fraction;if(d.type==0)value=std::floor(value+0.5f);compare(s,id,0,value,(ordinary&1)!=0,false);++ordinary;}
  }
  ordinaryOther=otherChanges;
 }
 {
  Session s(argv[1]);Session::Restore restore(s);s.mode(0,0,0);
  for(int32_t index=0;index<s.publicCount;++index){const int32_t id=field<int32_t>(s.publicMap,size_t(index)*4);const auto d=s.metadata()[id];if(d.type!=1||!(d.flags&2))continue;
   for(float fraction:{0.0f,.125f,.5f,.875f,1.0f,.5f}){float value=d.minimum+(d.maximum-d.minimum)*fraction;compare(s,id,0,value,(queued&1)!=0,true);++queued;}
   // Drain is intentionally not simulated. Clear the prepared queue/motions
   // back to the saved factory context before moving to another parameter.
   restore.apply();restore.verify();s.mode(0,0,0);
  }
  restore.apply();const auto restored=s.snapshot();require(std::memcmp(&restore.saved,&restored,sizeof(VLTyrellNotifyState))==0,"Restoration differs");
 }
 {
  Session s(argv[1]);Session::Restore restore(s);
  const std::array<std::array<int32_t,3>,8> controls{{{0,-1,0},{0,0,0},{0,1,0},{1,0,0},{255,-1,0},{0,0,1},{0,0,2},{0,0,255}}};
  for(int32_t index=0;index<s.publicCount;++index){const int32_t id=field<int32_t>(s.publicMap,size_t(index)*4);const auto d=s.metadata()[id];if(d.type!=1||!(d.flags&2))continue;const int32_t slot=d.special_index;const int32_t other=(slot+1)%s.specialCount;
   for(auto mode:controls)for(int32_t kind:{0,1,2})for(int32_t remaining:{0,17,50})for(float fraction:{-.125f,0.0f,.25f,.5f,1.0f,1.125f}){
    restore.apply();restore.verify();s.mode(kind?1:0,uint8_t(mode[0]),mode[1]);s.write(s.config,0x50,int32_t(0));
    const float current=d.minimum+(d.maximum-d.minimum)*.25f,target=d.minimum+(d.maximum-d.minimum)*.75f;
    s.write(s.raw,size_t(id)*4,current);if(auto*p=field<void*>(s.pointers,size_t(id)*8))s.write(p,0,current);
    s.write(s.records,size_t(slot)*16+4,.25f);s.write(s.records,size_t(slot)*16+8,remaining);s.write(s.records,size_t(slot)*16+12,target);
    if(kind){const int32_t member=kind==1?slot:other;s.write(s.queue,0,member);if(kind==2)s.write(s.records,size_t(other)*16+8,int32_t(17));}
    const float value=d.minimum+(d.maximum-d.minimum)*fraction;
    compare(s,id,uint8_t(mode[2]),value,(synthetic&1)!=0,true);++synthetic;
   }
  }
  restore.apply();const auto restored=s.snapshot();require(std::memcmp(&restore.saved,&restored,sizeof restored)==0,"Mode-grid restoration differs");
 }
 {
  Session s(argv[1]);Session::Restore restore(s);const int32_t id=field<int32_t>(s.publicMap,0);const auto d=s.metadata()[id];require(d.type==1&&d.flags&2,"Cyclic fixture parameter");
  auto*descriptor=static_cast<unsigned char*>(s.descriptors)+size_t(id)*116;
  struct WordGuard{void*p;uint32_t word;explicit WordGuard(void*v):p(v),word(field<uint32_t>(v,0)){}void restore(){std::memcpy(p,&word,4);}~WordGuard(){restore();}} flags(descriptor+92);
  s.write(descriptor,92,d.flags|0x200u);
  for(unsigned i=0;i<512;++i){restore.apply();restore.verify();s.mode(0,0,0);const float current=d.minimum+(d.maximum-d.minimum)*(float(i%33)/32);s.write(s.raw,size_t(id)*4,current);s.write(s.records,size_t(d.special_index)*16+12,current);if(auto*p=field<void*>(s.pointers,size_t(id)*8))s.write(p,0,current);const float value=d.minimum+(d.maximum-d.minimum)*(float((i*17)%33)/32);compare(s,id,0,value,(i&1)!=0,true);++synthetic;}
  // Flags restored before original destruction; scalar snapshot readback is
  // separate from any unmeasured original class state.
  restore.apply();restore.verify();flags.restore();require(field<uint32_t>(descriptor,92)==flags.word,"Flag restoration differs");const auto restored=s.snapshot();require(std::memcmp(&restore.saved,&restored,sizeof restored)==0,"Cyclic scalar restoration differs");
 }
 {
  Session s(argv[1]);Session::Restore restore(s);const int32_t id=field<int32_t>(s.publicMap,0);auto*descriptor=static_cast<unsigned char*>(s.descriptors)+size_t(id)*116;
  struct TypeGuard{void*p;int32_t word;explicit TypeGuard(void*v):p(v),word(field<int32_t>(v,0)){}void restore(){std::memcpy(p,&word,4);}~TypeGuard(){restore();}} type(descriptor+72);
  for(int32_t value:{3,4,0x103,0x104,0x604,-252}){s.write(descriptor,72,value);compare(s,id,0,25,true,true);++synthetic;}
  restore.apply();restore.verify();type.restore();require(field<int32_t>(descriptor,72)==type.word,"Type restoration differs");const auto restored=s.snapshot();require(std::memcmp(&restore.saved,&restored,sizeof restored)==0,"Type scalar restoration differs");
 }
 queuedOther=otherChanges-ordinaryOther;
 std::cout<<"{\"status\":\"passed_actual_factory_notifier_storage\",\"ordinary_public_calls\":"<<ordinary<<",\"controlled_queued_calls\":"<<queued<<",\"synthetic_calls\":"<<synthetic<<",\"compared_words\":"<<comparedWords<<",\"outside_selected_raw_pointee_changes\":"<<otherChanges<<",\"ordinary_other_changes\":"<<ordinaryOther<<",\"controlled_other_changes\":"<<queuedOther<<",\"substituted_callbacks\":false,\"full_plugin_equivalence\":false}\n";
 return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}
