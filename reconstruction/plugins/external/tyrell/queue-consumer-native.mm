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

};
}
#include "queue-consumer-storage.h"
#include <map>
namespace {
template<class T>void write(void*p,size_t offset,T value){std::memcpy(static_cast<char*>(p)+offset,&value,sizeof value);}
struct Snapshot {
 VLTyrellQueueState state{};std::array<VLTyrellQueueDescriptor,213> descriptors{};std::vector<void*>pointees;
 explicit Snapshot(Session&s){
  auto&x=state;x.internal_count=s.count;x.special_count=s.specialCount;x.queue_count=field<int32_t>(s.config,0x20);x.dirty=field<int32_t>(s.config,0x50);x.xy_count=field<uint32_t>(s.config,0x40);x.xy_targets_per_control=field<uint32_t>(s.config,0x44);
  std::memcpy(x.raw,s.raw,size_t(s.count)*4);std::memcpy(x.records,s.records,size_t(s.specialCount)*16);std::memcpy(x.queue,s.queue,size_t(s.specialCount)*4);
  std::memcpy(x.marks,field<void*>(s.config,0x58),size_t(s.count)*4);std::memcpy(x.changed,field<void*>(s.config,0x60),size_t(s.count)*4);
  for(int32_t i=0;i<s.count;++i){
   auto*d=static_cast<char*>(s.descriptors)+size_t(i)*116;int32_t index=-1;
   if(auto*p=field<void*>(s.pointers,size_t(i)*8)){auto it=std::find(pointees.begin(),pointees.end(),p);if(it==pointees.end()){index=int32_t(pointees.size());pointees.push_back(p);x.pointee_words[index]=field<uint32_t>(p,0);}else index=int32_t(it-pointees.begin());}
   descriptors[i]={field<float>(d,76),field<float>(d,80),field<uint32_t>(d,92),index};
  }
  x.pointee_count=uint32_t(pointees.size());
 }
};
struct Restore {
 Session&s;std::vector<uint8_t>bytes,descriptorBytes;std::vector<std::pair<void*,uint32_t>>words;
 explicit Restore(Session&session):s(session){
  require(field<uint32_t>(s.config,0x40)==0&&field<uint32_t>(s.config,0x44)==0,"Unsupported original XY context");
  auto*marks=field<char*>(s.config,0x58);auto*changed=field<char*>(s.config,0x60);auto*end=changed+size_t(s.count)*4;
  require(marks==static_cast<char*>(field<void*>(s.config,0x48))&&changed==marks+size_t(s.count)*4&&end-static_cast<char*>(s.config)==7152,"Allocated consumer geometry");
  bytes.resize(7152);std::memcpy(bytes.data(),s.config,bytes.size());descriptorBytes.resize(size_t(s.count)*116);std::memcpy(descriptorBytes.data(),s.descriptors,descriptorBytes.size());
  Snapshot before(s);for(auto*p:before.pointees)words.emplace_back(p,field<uint32_t>(p,0));
 }
 void apply(){std::memcpy(s.config,bytes.data(),bytes.size());std::memcpy(s.descriptors,descriptorBytes.data(),descriptorBytes.size());for(auto[p,value]:words)std::memcpy(p,&value,4);}
 void verify(){require(!std::memcmp(s.config,bytes.data(),bytes.size())&&!std::memcmp(s.descriptors,descriptorBytes.data(),descriptorBytes.size()),"Captured byte restoration");for(auto[p,value]:words)require(field<uint32_t>(p,0)==value,"Pointee restoration");}
 ~Restore(){apply();}
};
using Consumer=void(*)(void*,void*,void*,void*);
Consumer consumer(Session&s){
 const auto*vt=field<void*>(s.audio,0);auto getter=reinterpret_cast<void*(*)(void*)>(field<void*>(vt,0x120));require(reinterpret_cast<uintptr_t>(getter)-s.base==0x153d90,"Getter identity");
 auto result=reinterpret_cast<Consumer>(getter(s.audio));require(reinterpret_cast<uintptr_t>(result)-s.base==0x153da0&&reinterpret_cast<uintptr_t>(field<void*>(vt,0x50))-s.base==0x137260,"Consumer/no-op identity");return result;
}
uint64_t directCalls=0,ordinaryCalls=0,restores=0,comparedWords=0,otherPointeeObservations=0,completionChecks=0;
std::map<int32_t,uint64_t>otherPointeeByRepresentativeID;
VLTyrellQueueResult expectedStep(Snapshot&before){VLTyrellQueueResult result{};require(vl_tyrell_queue_step(before.descriptors.data(),&before.state,&result),"Source rejected original prepared state");return result;}
void compare(Session&s,const Snapshot&expected,const VLTyrellQueueResult&result,bool whole){
 const Snapshot actual(s);require(!std::memcmp(actual.descriptors.data(),expected.descriptors.data(),sizeof actual.descriptors),"Descriptor route changed");
 auto a=actual.state,b=expected.state;
 if(!whole){
  std::array<bool,213>visited{};for(uint32_t i=0;i<result.visited_count;++i)visited[expected.descriptors[b.changed[i]].pointee_index]=true;
  for(uint32_t i=0;i<a.pointee_count;++i)if(!visited[i]){if(a.pointee_words[i]!=b.pointee_words[i]){++otherPointeeObservations;for(uint32_t id=0;id<a.internal_count;++id)if(expected.descriptors[id].pointee_index==int32_t(i)){++otherPointeeByRepresentativeID[int32_t(id)];break;}}a.pointee_words[i]=b.pointee_words[i];}
 }
 require(!std::memcmp(&a,&b,sizeof a),"Consumer scalar snapshot differs");comparedWords+=sizeof(a)/4;
}
void callDirect(Session&s){Snapshot before(s);const auto result=expectedStep(before);std::array<uint64_t,3>context{reinterpret_cast<uint64_t>(s.config),field<uint64_t>(s.audio,0x430),reinterpret_cast<uint64_t>(s.audio)};std::array<uint64_t,4>in{17,19,23,29},out{31,37,41,43};const auto oldIn=in,oldOut=out;
 consumer(s)(in.data(),out.data(),context.data(),nullptr);require(in==oldIn&&out==oldOut,"Ignored buffer guards changed");compare(s,before,result,true);++directCalls;
}
void prepare(Session&s,const std::vector<int32_t>&ids,const std::vector<int32_t>&remaining,bool cyclic,bool alias){
 write(s.config,0x20,int32_t(ids.size()));write(s.config,0x50,int32_t(7));
 for(size_t i=0;i<ids.size();++i){const int32_t id=ids[i],slot=field<int32_t>(s.specialMap,size_t(id)*4);require(slot>=0&&slot<s.specialCount,"Valid original slot");auto*d=static_cast<char*>(s.descriptors)+size_t(id)*116;const float lo=field<float>(d,76),hi=field<float>(d,80),value=lo+(hi-lo)*float(i+1)/float(ids.size()+1);
  require(field<int32_t>(d,72)==1&&field<void*>(s.pointers,size_t(id)*8),"Actual special float pointee");write(s.queue,i*4,slot);write(s.raw,size_t(id)*4,value);write(s.records,size_t(slot)*16+4,(hi-lo)*0.02f);write(s.records,size_t(slot)*16+8,remaining[i]);write(s.records,size_t(slot)*16+12,lo+(hi-lo)*.875f);
  write(d,92,field<uint32_t>(d,92)|(cyclic?0x200u:0u));
  if(alias&&i)write(s.pointers,size_t(id)*8,field<void*>(s.pointers,size_t(ids[0])*8));
 }
}
}
int main(int argc,char**argv){std::cout<<std::unitbuf;@autoreleasepool{try{
 require(argc==2,"Expected original bundle");
 {
  Session s(argv[1]);Restore restore(s);for(int32_t count:{-1,0}){restore.apply();write(s.config,0x20,count);callDirect(s);restore.apply();restore.verify();++restores;}
  for(int32_t publicIndex=0;publicIndex<s.publicCount;++publicIndex){const int32_t id=field<int32_t>(s.publicMap,size_t(publicIndex)*4);auto*d=static_cast<char*>(s.descriptors)+size_t(id)*116;if(field<int32_t>(d,72)!=1||!(field<uint32_t>(d,92)&2))continue;
   const float lo=field<float>(d,76),hi=field<float>(d,80),range=hi-lo;
   for(bool cyclic:{false,true})for(int32_t remaining:{-1,0,1,2,50})for(float increment:{-0.0f,0.0f,range*.02f,-range*.02f})for(float value:{lo,hi,lo+range*.5f,std::nextafter(lo,-INFINITY),std::nextafter(hi,INFINITY),lo-range*.125f,hi+range*.125f}){
    restore.apply();prepare(s,{id},{remaining},cyclic,false);write(s.raw,size_t(id)*4,value);const int32_t slot=field<int32_t>(s.specialMap,size_t(id)*4);write(s.records,size_t(slot)*16+4,increment);callDirect(s);restore.apply();restore.verify();++restores;
   }
  }
  std::vector<int32_t>ids;for(int32_t index=0;index<s.publicCount&&ids.size()<3;++index){const int32_t id=field<int32_t>(s.publicMap,size_t(index)*4);auto*d=static_cast<char*>(s.descriptors)+size_t(id)*116;if(field<int32_t>(d,72)==1&&(field<uint32_t>(d,92)&2))ids.push_back(id);}require(ids.size()==3,"Three original special IDs");std::sort(ids.begin(),ids.end());
  do{for(bool alias:{false,true})for(int32_t a:{0,1,2,50})for(int32_t b:{0,1,2,50})for(int32_t c:{0,1,2,50}){restore.apply();prepare(s,ids,{a,b,c},false,alias);callDirect(s);restore.apply();restore.verify();++restores;}}while(std::next_permutation(ids.begin(),ids.end()));
 }
 {
  Session s(argv[1]);auto*e=s.instance.value;e->dispatcher(e,10,0,0,nullptr,48000.0f);e->dispatcher(e,11,0,64,nullptr,0);e->dispatcher(e,12,0,1,nullptr,0);s.instance.powered=true;e->dispatcher(e,71,0,0,nullptr,0);s.instance.started=true;
  require(e->replacing&&e->inputs>=0&&e->inputs<=64&&e->outputs>0&&e->outputs<=64,"Audio ABI");std::vector<std::vector<float>>in(size_t(e->inputs),std::vector<float>(66)),out(size_t(e->outputs),std::vector<float>(66));std::vector<float*>inputs,outputs;for(auto&x:in)inputs.push_back(x.data()+1);for(auto&x:out){x.front()=x.back()=1234.5f;outputs.push_back(x.data()+1);}
  const auto render=[&]{Snapshot before(s);const auto result=expectedStep(before);e->replacing(e,inputs.data(),outputs.data(),64);compare(s,before,result,false);for(const auto&x:out){require(x.front()==1234.5f&&x.back()==1234.5f,"Render guards");for(size_t j=1;j<=64;++j)require(std::isfinite(x[j]),"Original finite output");}++ordinaryCalls;{std::lock_guard<std::mutex>lock(transportMutex);transport.samplePos+=64;}};
  render();
  for(int32_t publicIndex=0;publicIndex<s.publicCount;++publicIndex){const int32_t id=field<int32_t>(s.publicMap,size_t(publicIndex)*4);auto*d=static_cast<char*>(s.descriptors)+size_t(id)*116;if(field<int32_t>(d,72)!=1||!(field<uint32_t>(d,92)&2))continue;
   const int32_t slot=field<int32_t>(s.specialMap,size_t(id)*4);
   for(float value:{.125f,.875f}){e->setParameter(e,publicIndex,value);for(unsigned i=0;i<56;++i)render();require(field<int32_t>(s.records,size_t(slot)*16+8)==-1&&field<int32_t>(s.config,0x20)==0,"Original target completion");require(field<uint32_t>(s.raw,size_t(id)*4)==field<uint32_t>(s.records,size_t(slot)*16+12),"Exact target completion bits");++completionChecks;}
  }
 }
 std::cout<<"{\"status\":\"passed_original_queue_consumer\",\"direct_calls\":"<<directCalls<<",\"captured_restores\":"<<restores<<",\"ordinary_render_calls\":"<<ordinaryCalls<<",\"ordinary_render_frames\":"<<ordinaryCalls*64<<",\"completion_checks\":"<<completionChecks<<",\"compared_words\":"<<comparedWords<<",\"outside_visited_pointee_change_observations\":"<<otherPointeeObservations<<",\"outside_word_representative_IDs\":[";
 bool comma=false;for(auto[id,count]:otherPointeeByRepresentativeID){if(comma)std::cout<<',';std::cout<<"{\"ID\":"<<id<<",\"observations\":"<<count<<'}';comma=true;}
 std::cout<<"],\"substituted_unit_callbacks\":false,\"actual_audio_effect_parity\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}
