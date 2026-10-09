// Caller-owned synthetic XY state; original receiver/configuration stay intact.
#if !defined(__APPLE__) || !defined(__x86_64__)
#error Installed Tyrell Intel callback layout only.
#endif
#define main vl_xy_unused_reference_main
#include "../../../../../reconstruction/plugins/common/vst2_probe.mm"
#undef main
#include "xy-api.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <bit>
#include <cfenv>
#include <map>
#include <limits>
#include <random>
#include <xmmintrin.h>
template<class T>T field(const void* p,size_t o){T v;std::memcpy(&v,static_cast<const char*>(p)+o,sizeof v);return v;}
template<class T>void put(void* p,size_t o,T v){std::memcpy(static_cast<char*>(p)+o,&v,sizeof v);}
static std::string memorySHA(const void* p,size_t n){std::array<unsigned char,32>d;CC_SHA256(p,CC_LONG(n),d.data());std::string h;for(auto v:d){h+="0123456789abcdef"[v>>4];h+="0123456789abcdef"[v&15];}return h;}
static std::string fileSHA(const std::string& path){std::ifstream f(path,std::ios::binary);require(bool(f),"File unavailable");CC_SHA256_CTX c;CC_SHA256_Init(&c);std::array<char,65536>b;while(f.read(b.data(),b.size())||f.gcount())CC_SHA256_Update(&c,b.data(),CC_LONG(f.gcount()));require(f.eof(),"Complete file read");std::array<unsigned char,32>d;CC_SHA256_Final(d.data(),&c);std::string h;for(auto v:d){h+="0123456789abcdef"[v>>4];h+="0123456789abcdef"[v&15];}return h;}
using Consumer=void(*)(void*,void*,void*,void*);
struct Session {
 Bundle bundle;Instance instance;uintptr_t base{};void* manager{};void* receiver{};void* config{};void* descriptors{};Consumer callback{};
 std::vector<uint8_t> originalConfig,originalDescriptors;std::map<void*,uint32_t> originalWords;
 Session(const char* path){
  require(fileSHA(std::string(path)+"/Contents/MacOS/TyrellN6")=="a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54","Installed identity");
  require(std::fegetround()==FE_TONEAREST&&(_mm_getcsr()&0xe040)==0&&(_mm_getcsr()&0x1f80)==0x1f80,"Prepared FP environment");
  transport={};transport.sampleRate=48000;transport.tempo=120;blockSize=64;
  auto url=CFURLCreateFromFileSystemRepresentation(nullptr,reinterpret_cast<const UInt8*>(path),std::strlen(path),true);require(url,"URL");bundle.value=CFBundleCreate(nullptr,url);CFRelease(url);require(bundle.value&&CFBundleLoadExecutable(bundle.value),"Original load");
  auto entry=reinterpret_cast<Effect*(*)(Dispatch)>(CFBundleGetFunctionPointerForName(bundle.value,CFSTR("VSTPluginMain")));Dl_info info{};require(entry&&dladdr(reinterpret_cast<void*>(entry),&info)&&info.dli_fbase,"Entry/base");base=reinterpret_cast<uintptr_t>(info.dli_fbase);require(reinterpret_cast<uintptr_t>(entry)-base==0x3ddb0,"Entry identity");
  instance.value=entry(host);require(instance.value&&instance.value->magic==0x56737450,"Original factory");instance.value->dispatcher(instance.value,0,0,0,nullptr,0);instance.opened=true;
  manager=field<void*>(instance.value->object,0x138);require(manager,"Manager");receiver=field<void*>(manager,0x40);require(receiver&&receiver==field<void*>(manager,0x48),"Receiver");config=field<void*>(receiver,0x428);descriptors=field<void*>(receiver,0x4e0);require(config&&descriptors==field<void*>(config,0),"Native storage");
  require(field<int32_t>(receiver,0x4c4)==213&&field<int32_t>(receiver,0x4cc)==82&&field<int32_t>(config,0x40)==0&&field<int32_t>(config,0x44)==0,"Original zero XY counts");pin();
  originalConfig.resize(7152);std::memcpy(originalConfig.data(),config,originalConfig.size());originalDescriptors.resize(213*116);std::memcpy(originalDescriptors.data(),descriptors,originalDescriptors.size());
  void* pointers=field<void*>(config,0x18);for(size_t i=0;i<213;++i)if(void* p=field<void*>(pointers,i*8))originalWords.emplace(p,field<uint32_t>(p,0));
 }
 void pin(){
  const auto* vt=field<void*>(receiver,0);require(reinterpret_cast<uintptr_t>(vt)-base==0x3173b0,"Live receiver VFT");auto getter=reinterpret_cast<Consumer(*)(void*)>(field<void*>(vt,0x120));require(reinterpret_cast<uintptr_t>(getter)-base==0x153d90,"Getter route");callback=getter(receiver);require(reinterpret_cast<uintptr_t>(callback)-base==0x153da0,"Callback route");require(reinterpret_cast<uintptr_t>(field<void*>(vt,0x50))-base==0x137260,"No-op route");
  require(memorySHA(reinterpret_cast<void*>(base+0x153d90),8)=="1d8aa4e86c0215bff4db689fd35b97a37ce2d8886a02f88fe87ae9649bff4b32","Live getter bytes");
  require(memorySHA(reinterpret_cast<void*>(base+0x153da0),1009)=="98ee504ff900e8ccb27dc77f3282fadab13f6e1edad64061615bdae8ed54c496","Live consumer bytes");
  require(field<uint32_t>(reinterpret_cast<void*>(base+0x137260),0)==0xe5894855u&&field<uint16_t>(reinterpret_cast<void*>(base+0x137260),4)==0xc35du,"Live six-byte no-op");
  require(field<uint32_t>(reinterpret_cast<void*>(base+0x2521c0),0)==0x3c23d70au&&field<uint32_t>(reinterpret_cast<void*>(base+0x253eb4),0)==0xbc23d70au&&field<uint32_t>(reinterpret_cast<void*>(base+0x251660),0)==0x3f000000u,"Live float constants");for(size_t i=0;i<4;++i)require(field<uint32_t>(reinterpret_cast<void*>(base+0x2519e0),i*4)==0x7fffffffu,"Live absolute mask");
 }
 void preserved(){require(field<void*>(instance.value->object,0x138)==manager&&field<void*>(manager,0x40)==receiver&&field<void*>(manager,0x48)==receiver&&field<void*>(receiver,0x428)==config&&field<void*>(receiver,0x4e0)==descriptors,"Original routing changed");require(!std::memcmp(config,originalConfig.data(),originalConfig.size())&&!std::memcmp(descriptors,originalDescriptors.data(),originalDescriptors.size()),"Original selected spans changed");for(auto[p,v]:originalWords)require(field<uint32_t>(p,0)==v,"Original selected pointee changed");require(field<int32_t>(manager,0x128)==0&&field<int32_t>(manager,0x12c)==0&&field<int32_t>(receiver,0x4d0)==0&&field<int32_t>(receiver,0x4d4)==0,"Original XY counts changed");}
};
struct Buffer {
 std::vector<uint8_t> bytes;size_t size;
 explicit Buffer(size_t n):bytes(n+128,0xa5),size(n){}
 void* data(){return bytes.data()+64;}
 void guards()const{for(size_t i=0;i<64;++i)require(bytes[i]==0xa5&&bytes[size+64+i]==0xa5,"Owned buffer guard");}
 std::vector<uint8_t> snapshot(){return {bytes.begin()+64,bytes.begin()+64+size};}
};
struct Clone {
 Buffer cfg,desc,cells;size_t n,x,t,m,raw,pointers,special,targets,marks,changed,aux,xyIDs;uint32_t touches=0;
 Clone(const std::array<VLTyrellXYDescriptor,213>& d,const VLTyrellXYState& s):
  cfg((400+28*s.internal_count+16*s.xy_count*s.targets_per_control+4*s.xy_count+15)&~size_t(15)),desc(size_t(s.internal_count)*116),cells(size_t(s.cell_count)*4),n(s.internal_count),x(s.xy_count),t(s.targets_per_control),m(s.cell_count),raw(400),pointers(raw+4*n),special(pointers+8*n),targets(special+4*n),marks(targets+16*x*t),changed(marks+4*n),aux(changed+4*n),xyIDs(aux+4*n) {
  require(n>=2&&n<=213&&x>=1&&x<=4&&t>=1&&t<=16&&x*t<=64&&m>=1&&m<=n&&!(reinterpret_cast<uintptr_t>(cfg.data())&15),"Safe clone geometry");
  const auto bounded=[](float value,float limit){return std::isfinite(value)&&std::fabs(value)<=limit;};
  uint32_t count=0;for(size_t i=0;i<n;++i){require(s.cell_slots[i]>=0&&size_t(s.cell_slots[i])<m,"Owned pointee index");require(bounded(s.raw[i],1024)&&bounded(d[i].minimum,1024)&&bounded(d[i].maximum,1024)&&d[i].minimum<=d[i].maximum&&(s.marks[i]==-1||s.marks[i]==-3||s.marks[i]==0),"Prepared raw/descriptor/mark domain");if(d[i].full_type==2){require(i>0&&count<x&&bounded(s.raw[i],100),"Scanner geometry/coordinate domain");put<int32_t>(cfg.data(),xyIDs+count*4,int32_t(i));++count;}}
  require(count==x&&(s.queue_count==0||s.queue_count==-1),"Exact full-type count/empty queue");
  for(size_t i=0;i<m;++i)require(bounded(s.cells[i],1024),"Prepared cell domain");
  for(size_t i=0;i<x*t;++i)require(s.records[i].target_id>=-1&&s.records[i].target_id<int32_t(n)&&bounded(s.records[i].negative_depth,100)&&bounded(s.records[i].positive_depth,100),"Prepared record domain");
  put<void*>(cfg.data(),0,desc.data());put<int32_t>(cfg.data(),8,int32_t(n));put<void*>(cfg.data(),0x10,static_cast<char*>(cfg.data())+raw);put<void*>(cfg.data(),0x18,static_cast<char*>(cfg.data())+pointers);put<int32_t>(cfg.data(),0x20,s.queue_count);put<void*>(cfg.data(),0x28,static_cast<char*>(cfg.data())+special);put<void*>(cfg.data(),0x30,static_cast<char*>(cfg.data())+targets);put<void*>(cfg.data(),0x38,static_cast<char*>(cfg.data())+targets);put<int32_t>(cfg.data(),0x40,int32_t(x));put<int32_t>(cfg.data(),0x44,int32_t(t));put<void*>(cfg.data(),0x48,static_cast<char*>(cfg.data())+targets);put<int32_t>(cfg.data(),0x50,s.dirty);put<void*>(cfg.data(),0x58,static_cast<char*>(cfg.data())+marks);put<void*>(cfg.data(),0x60,static_cast<char*>(cfg.data())+changed);put<int32_t>(cfg.data(),0x68,0);put<void*>(cfg.data(),0x70,static_cast<char*>(cfg.data())+aux);put<void*>(cfg.data(),0x78,static_cast<char*>(cfg.data())+aux);put<void*>(cfg.data(),0x80,static_cast<char*>(cfg.data())+xyIDs);
  std::memcpy(static_cast<char*>(cfg.data())+raw,s.raw,n*4);std::memcpy(static_cast<char*>(cfg.data())+targets,s.records,x*t*16);std::memcpy(static_cast<char*>(cfg.data())+marks,s.marks,n*4);std::memcpy(static_cast<char*>(cfg.data())+0x8c,s.touched,64*4);std::memcpy(cells.data(),s.cells,m*4);
  for(size_t i=0;i<n;++i){put<void*>(cfg.data(),pointers+i*8,static_cast<char*>(cells.data())+size_t(s.cell_slots[i])*4);put<int32_t>(cfg.data(),special+i*4,-1);put<int32_t>(desc.data(),i*116+72,d[i].full_type);put<float>(desc.data(),i*116+76,d[i].minimum);put<float>(desc.data(),i*116+80,d[i].maximum);put<uint32_t>(desc.data(),i*116+92,0);}
  for(size_t i=0;i<x*t;++i)touches+=s.records[i].target_id>=0;
 }
 void expected(std::vector<uint8_t>& c,std::vector<uint8_t>& values,const VLTyrellXYState& s){put<int32_t>(c.data(),0x20,s.queue_count);put<int32_t>(c.data(),0x50,s.dirty);std::memcpy(c.data()+targets,s.records,x*t*16);std::memcpy(c.data()+marks,s.marks,n*4);std::memcpy(c.data()+0x8c,s.touched,64*4);std::memcpy(values.data(),s.cells,m*4);}
};
using Descriptors=std::array<VLTyrellXYDescriptor,213>;
uint64_t comparisons=0,comparedBytes=0,fenvRestores=0,originalChecks=0,aliased=0,packed=0,fullScratch=0;
void compare(Session& original,const Descriptors& d,const VLTyrellXYState& input,int fixture){
 struct Environment {std::fenv_t saved{};Environment(){require(std::fegetenv(&saved)==0,"Outer caller fenv capture");}bool restore(){std::fenv_t current{};return std::fesetenv(&saved)==0&&std::fegetenv(&current)==0&&!std::memcmp(&saved,&current,sizeof saved);}~Environment(){std::fesetenv(&saved);}} caller;
 Clone clone(d,input);auto expectedConfig=clone.cfg.snapshot(),expectedCells=clone.cells.snapshot(),oldDescriptors=clone.desc.snapshot();auto sourceState=input;VLTyrellXYResult result{0x51515151};
 alignas(16)std::array<uint64_t,5>context{0x1111222233334444ull,reinterpret_cast<uint64_t>(clone.cfg.data()),0x5566778899aabbccull,reinterpret_cast<uint64_t>(original.receiver),0xddddeeeeffff0000ull};const auto oldContext=context;std::array<uint64_t,8>in{17,19,23,29,31,37,41,43},out{47,53,59,61,67,71,73,79};const auto oldIn=in,oldOut=out;
 original.pin();original.preserved();std::fenv_t env{},restored{};require(std::fegetenv(&env)==0&&std::feclearexcept(FE_ALL_EXCEPT)==0,"Fenv snapshot/clear");
 const int success=vl_tyrell_xy_step(d.data(),input.internal_count,&sourceState,&result);const int sourceMask=std::fetestexcept(FE_ALL_EXCEPT);require(std::feclearexcept(FE_ALL_EXCEPT)==0,"Native clear");
 if(!success){require(std::fesetenv(&env)==0,"Rejected source fenv restore");throw std::runtime_error("XY source rejected prepared native input");}
 original.callback(in.data()+2,out.data()+2,context.data()+1,nullptr);const int nativeMask=std::fetestexcept(FE_ALL_EXCEPT);require(std::fesetenv(&env)==0&&std::fegetenv(&restored)==0&&!std::memcmp(&env,&restored,sizeof env),"Full fenv restore");++fenvRestores;
 if(!success||sourceMask!=nativeMask){std::cerr<<"fixture="<<fixture<<" source="<<sourceMask<<" native="<<nativeMask<<" success="<<success<<'\n';throw std::runtime_error("XY source acceptance/FE mask differs");}
 require(result.touched_count==clone.touches,"XY duplicate-inclusive scratch count differs");clone.expected(expectedConfig,expectedCells,sourceState);
 VLTyrellXYState readonly;std::memcpy(&readonly,&sourceState,sizeof readonly);readonly.queue_count=input.queue_count;readonly.dirty=input.dirty;std::memcpy(readonly.cells,input.cells,clone.m*4);std::memcpy(readonly.marks,input.marks,clone.n*4);std::memcpy(readonly.touched,input.touched,clone.touches*4);for(size_t i=0;i<clone.x*clone.t;++i)if(input.records[i].target_id>=0)std::memcpy(&readonly.records[i].last_contribution,&input.records[i].last_contribution,4);require(!std::memcmp(&readonly,&input,sizeof input),"Source read-only/inactive fields changed");
 if(std::memcmp(clone.cfg.data(),expectedConfig.data(),expectedConfig.size())||std::memcmp(clone.cells.data(),expectedCells.data(),expectedCells.size())){std::cerr<<"fixture="<<fixture<<'\n';throw std::runtime_error("XY scalar/footprint differs");}
 require(!std::memcmp(clone.desc.data(),oldDescriptors.data(),oldDescriptors.size())&&context==oldContext&&in==oldIn&&out==oldOut,"Readonly fields/context/arguments changed");clone.cfg.guards();clone.desc.guards();clone.cells.guards();original.preserved();++originalChecks;++comparisons;comparedBytes+=expectedConfig.size()+expectedCells.size()+oldDescriptors.size();packed+=(clone.pointers&7)!=0;fullScratch+=clone.touches==64;
 std::array<bool,213> slots{};bool alias=false;for(size_t i=0;i<input.internal_count;++i){const size_t slot=size_t(input.cell_slots[i]);alias|=slots[slot];slots[slot]=true;}aliased+=alias;
 require(caller.restore(),"Outer full caller fenv restore/readback");
}
float randomValue(std::mt19937& r,float limit){return float(int32_t(r()%2000001)-1000000)*(limit/1000000.f);}
int main(int argc,char** argv){std::cout<<std::unitbuf;@autoreleasepool{try{
 require(argc==2,"Expected installed original Tyrell VST");Session original(argv[1]);std::mt19937 random(0x58475932u);int fixture=0;
 for(uint32_t n:{2u,3u,7u,17u,64u,213u})for(uint32_t x=1;x<=4;++x){if(x>=n)continue;for(uint32_t t:{1u,2u,3u,8u,16u})for(int variant=0;variant<8;++variant){
  Descriptors d{};VLTyrellXYState s;std::memset(&s,0xa5,sizeof s);s.internal_count=n;s.xy_count=x;s.targets_per_control=t;s.cell_count=variant%2?n:1;s.queue_count=variant%3?0:-1;s.dirty=17;std::array<uint32_t,4>control{};
  for(uint32_t i=0;i<x;++i)control[i]=1+i*(n-2)/(x-1?x-1:1);
  for(uint32_t id=0;id<n;++id){const float a=randomValue(random,900),b=randomValue(random,900);d[id]={id%5==0?0x102:1,std::min(a,b),std::max(a,b)};s.raw[id]=randomValue(random,900);s.cell_slots[id]=int32_t(id%s.cell_count);s.marks[id]=variant%3==0?-3:variant%3==1?-1:0;}
  for(uint32_t group=0;group<x;++group){d[control[group]].full_type=2;s.raw[control[group]]=variant==0?100:variant==1?-100:variant==2?0.f:variant==3?-0.f:variant==4?std::numeric_limits<float>::denorm_min():variant==5?-std::numeric_limits<float>::denorm_min():randomValue(random,100);}
  for(uint32_t i=0;i<s.cell_count;++i)s.cells[i]=randomValue(random,900);
  for(uint32_t i=0;i<x*t;++i){const int32_t target=variant==7?-1:variant==6?(i%3==0?-1:int32_t(random()%n)):int32_t(i%2?n-1:0);s.records[i]={target,randomValue(random,100),randomValue(random,100),std::bit_cast<float>(0x7fc0beefu+i)};}
  compare(original,d,s,fixture++);
 }}
 original.preserved();require(comparisons>500&&aliased&&packed&&fullScratch,"Discriminating corpus coverage missing");
 std::cout<<"{\"status\":\"passed_prepared_XY_original\",\"comparisons\":"<<comparisons<<",\"exact_owned_bytes\":"<<comparedBytes<<",\"full_fenv_restorations\":"<<fenvRestores<<",\"selected_original_preservation_checks\":"<<originalChecks<<",\"aliased_fixtures\":"<<aliased<<",\"packed_pointer_fixtures\":"<<packed<<",\"64_touch_fixtures\":"<<fullScratch<<",\"direct_native_byte_writes\":false,\"callback_or_VFT_replacement\":false,\"natural_active_XY\":false,\"positive_queue\":false,\"audio_rendered\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}}
