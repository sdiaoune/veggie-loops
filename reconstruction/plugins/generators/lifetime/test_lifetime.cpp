// Prepared source-only fixture. No installed original image is loaded here.
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "This source lifetime fixture is prepared for macOS arm64"
#endif
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <new>
#include <stdexcept>
namespace vl_lifetime_probe {
struct Allocation {void*pointer=nullptr;std::size_t size=0;};
std::array<Allocation,8192> allocations{};
std::size_t liveAllocations=0,peakAllocations=0;
unsigned trackerOverflow=0,unknownDeletes=0;
int allocationBudget=-1;
struct Watch {void*pointer=nullptr;unsigned deletions=0;};
// Three live sources: subject, peer, and independently initialized peer control.
std::array<std::array<Watch,7>,3>watches{};
void record(void*p,std::size_t size) {
 for(auto&r:allocations)if(!r.pointer){r={p,size};++liveAllocations;if(liveAllocations>peakAllocations)peakAllocations=liveAllocations;return;}
 ++trackerOverflow;
}
void* allocate(std::size_t size,std::size_t alignment=alignof(std::max_align_t)) {
 if(allocationBudget==0)throw std::bad_alloc();if(allocationBudget>0)--allocationBudget;
 void*p=nullptr;
 if(alignment<=alignof(std::max_align_t))p=std::malloc(size?size:1);
 else if(posix_memalign(&p,alignment,size?size:1)!=0)p=nullptr;
 if(!p)throw std::bad_alloc();record(p,size);return p;
}
void deallocate(void*p)noexcept {
 if(!p)return;
 for(auto&group:watches)for(auto&w:group)if(w.pointer==p)++w.deletions;
 bool found=false;for(auto&r:allocations)if(r.pointer==p){r={};--liveAllocations;found=true;break;}
 if(!found)++unknownDeletes;
 std::free(p);
}
}
void*operator new(std::size_t n){return vl_lifetime_probe::allocate(n);}
void*operator new[](std::size_t n){return vl_lifetime_probe::allocate(n);}
void*operator new(std::size_t n,const std::nothrow_t&)noexcept{try{return ::operator new(n);}catch(...){return nullptr;}}
void*operator new[](std::size_t n,const std::nothrow_t&)noexcept{try{return ::operator new[](n);}catch(...){return nullptr;}}
void*operator new(std::size_t n,std::align_val_t a){return vl_lifetime_probe::allocate(n,std::size_t(a));}
void*operator new[](std::size_t n,std::align_val_t a){return vl_lifetime_probe::allocate(n,std::size_t(a));}
void operator delete(void*p)noexcept{vl_lifetime_probe::deallocate(p);}
void operator delete[](void*p)noexcept{vl_lifetime_probe::deallocate(p);}
void operator delete(void*p,std::size_t)noexcept{::operator delete(p);}
void operator delete[](void*p,std::size_t)noexcept{::operator delete[](p);}
void operator delete(void*p,const std::nothrow_t&)noexcept{::operator delete(p);}
void operator delete[](void*p,const std::nothrow_t&)noexcept{::operator delete[](p);}
void operator delete(void*p,std::align_val_t)noexcept{::operator delete(p);}
void operator delete[](void*p,std::align_val_t)noexcept{::operator delete[](p);}
void operator delete(void*p,std::size_t,std::align_val_t)noexcept{::operator delete(p);}
void operator delete[](void*p,std::size_t,std::align_val_t)noexcept{::operator delete[](p);}
#if VL_LIFETIME_VARIANT==0
#include "stock_factory.cpp"
#elif VL_LIFETIME_VARIANT==1
#include "immediate_factory.cpp"
#elif VL_LIFETIME_VARIANT==2
#include "prevoice_factory.cpp"
#else
#error "Select exactly one copied factory"
#endif
namespace vl_lifetime_probe {
using vl_private_osc::Plugin;
void require(bool okay,const char*message){if(!okay)throw std::runtime_error(message);}
struct Host {
 void**vtable=nullptr;std::array<void*,43>methods{};
 bool alive=true;unsigned computes=0,notices=0;
 Host(){vtable=methods.data();}
};
void lr(void*context,float*l,float*r,float pan,float volume){auto&h=*static_cast<Host*>(context);require(h.alive,"Callback reached ended host");++h.computes;*l=volume*std::sqrt((1-pan)*.5f);*r=volume*std::sqrt((1+pan)*.5f);}
void notice(void*context,intptr_t,int32_t){auto&h=*static_cast<Host*>(context);require(h.alive,"Notification reached ended host");++h.notices;}
void initialize(Host&h){h.methods[31]=reinterpret_cast<void*>(&lr);h.methods[5]=reinterpret_cast<void*>(&notice);}
struct alignas(16) Note {
 std::array<uint32_t,4>leading{0x13579bdf,0xa5a5a5a5,0x2468ace0,0xdeadbeef};
 vl_osc_multimode_channel_parameters values{};
 std::array<uint32_t,4>trailing{0xcafebabe,0x55aa55aa,0xaa55aa55,0x01234567};
};
static_assert(offsetof(Note,values)==16);
struct Stream {void**functions;std::array<uint8_t,460>bytes{};uint32_t cursor=0;};
int32_t write(void*context,const void*input,uint32_t count,uint32_t*done){auto&s=*static_cast<Stream*>(context);if(count>s.bytes.size()-s.cursor)return int32_t(0x8003001e);std::memcpy(s.bytes.data()+s.cursor,input,count);s.cursor+=count;if(done)*done=count;return 0;}
std::array<uint8_t,460> saved(Plugin*p){std::array<void*,5>f{};f[4]=reinterpret_cast<void*>(&write);Stream s{f.data()};p->functions->state(p,&s,1);require(s.cursor==460,"Source state framing changed");return s.bytes;}
void fillNote(Note&n,float pitch,float pan){n.values.initial={pan,.8f,pitch,0,0};n.values.final=n.values.initial;}
intptr_t start(Plugin*p,Note&n,intptr_t tag){const auto handle=p->functions->trigger(p,&n.values,tag);require(handle!=-1&&handle!=0,"Prepared source trigger failed");return handle;}
void setup(Plugin*p){require(vl_private_osc_prepare(p,44100,120,240),"Prepared source context failed");for(int i:{1,8,15})p->functions->parameter(p,i,0,1);p->functions->parameter(p,6,80,1);p->functions->parameter(p,13,60,1);p->functions->parameter(p,20,0,1);p->functions->parameter(p,113,0,1);}
void capture(int index,Plugin*p,Host*h,const std::array<intptr_t,2>&voices){
 auto&o=instance(p);auto&g=watches[std::size_t(index)];g={};
 g[0].pointer=p;g[1].pointer=o.storage;g[2].pointer=o.channel;
 g[3].pointer=o.tables.empty()?nullptr:o.tables.data();
 g[4].pointer=reinterpret_cast<void*>(voices[0]);g[5].pointer=reinterpret_cast<void*>(voices[1]);g[6].pointer=h;
}
void clearWatch(int index){watches[std::size_t(index)]={};}
void close(int index,Plugin*p,int route){
 const auto fn=route==0?p->functions->destroy:route==1?p->functions->complete_destructor:p->functions->deleting_destructor;
 auto&g=watches[std::size_t(index)];fn(p);
 require(g[1].deletions==1,"Owned storage core was not cleaned exactly once");
 for(int i:{2,3,4,5})if(g[std::size_t(i)].pointer)require(g[std::size_t(i)].deletions==1,"Owned channel table or voice was not cleaned exactly once");
 require(g[6].deletions==0,"Cleanup freed caller host memory");
 if(route==1){require(g[0].deletions==0,"Complete destructor deallocated caller storage");::operator delete(static_cast<void*>(p));}
 require(g[0].deletions==1,route==2?"Deleting destructor did not deallocate storage":"Ordinary or caller deallocation count differs");
 clearWatch(index); // Ended pointer addresses may subsequently be reused legally.
}
size_t renderPair(Plugin*peer,Plugin*control,Note&pn,Note&cn,bool afterCleanup){
 pn.values.final.pitch=cn.values.final.pitch=300;
 std::array<float,144>a{},b{};a.fill(1234.5f);b=a;for(size_t i=8;i<136;++i)a[i]=b[i]=.25f;
 peer->functions->tick(peer);control->functions->tick(control);int32_t al=64,bl=64;
 peer->functions->generator(peer,a.data()+8,al);control->functions->generator(control,b.data()+8,bl);
 require(al==64&&bl==64,"Source render changed frame count");
 for(size_t i=0;i<8;++i)require(a[i]==1234.5f&&b[i]==1234.5f&&a[136+i]==1234.5f&&b[136+i]==1234.5f,"Render guards changed");
 require(!std::memcmp(a.data()+8,b.data()+8,128*sizeof(float)),afterCleanup?"Peer reference audio differs AFTER subject cleanup":"Initial peer/reference audio differs BEFORE subject cleanup");
 return 128;
}
}
int main(){using namespace vl_lifetime_probe;try{
 require(std::fegetround()==FE_TONEAREST,"Nearest-even required");
 uint64_t fpcr;asm volatile("mrs %0, fpcr":"=r"(fpcr));require((fpcr&((1ull<<24)|(0x1full<<8)))==0,"Gradual nontrapping source domain required");
 Host warmHost;initialize(warmHost);auto*warm=CreatePlugInstance(&warmHost,1);require(warm,"Metadata warmup factory failed");warm->functions->destroy(warm);
 const auto firstBaseline=liveAllocations;const auto firstUnknown=unknownDeletes;
 unsigned allocationFailures=0;
 for(int budget:{0,1}){allocationBudget=budget;auto*p=CreatePlugInstance(&warmHost,2);allocationBudget=-1;require(!p,"Deterministic factory allocation failure not returned");require(liveAllocations==firstBaseline,"Failed factory leaked owned allocation");++allocationFailures;}
 require(unknownDeletes==firstUnknown&&!trackerOverflow,"Allocation tracking overflow or unmatched source free");
 unsigned pairs=0,complete=0,deleting=0,ordinary=0,liveSubjects=0;size_t audioFloats=0;
 for(int shape=0;shape<2;++shape)for(int route=0;route<3;++route){
  auto*subjectHost=new Host;auto*peerHost=new Host;auto*controlHost=new Host;initialize(*subjectHost);initialize(*peerHost);initialize(*controlHost);
  const auto baseline=liveAllocations;const auto unknown=unknownDeletes;
  auto*subject=CreatePlugInstance(subjectHost,0x123456789abcdef);auto*peer=CreatePlugInstance(peerHost,42);auto*control=CreatePlugInstance(controlHost,43);require(subject&&peer&&control,"Three live source factory setup failed");
  setup(peer);setup(control);Note pn{},cn{};fillNote(pn,300,.15f);fillNote(cn,300,.15f);std::array<intptr_t,2>pv{start(peer,pn,100),0},cv{start(control,cn,100),0};
  std::array<Note,2>sn{};std::array<intptr_t,2>sv{};
  if(shape){setup(subject);for(int i=0;i<2;++i){fillNote(sn[std::size_t(i)],float(i?400:-400),i?.25f:-.25f);sv[std::size_t(i)]=start(subject,sn[std::size_t(i)],200+i);}++liveSubjects;}
  capture(0,subject,subjectHost,sv);capture(1,peer,peerHost,pv);capture(2,control,controlHost,cv);
  audioFloats+=renderPair(peer,control,pn,cn,false);
  const auto peerState=saved(peer);
  std::array<uint8_t,sizeof(Plugin)>header{};std::memcpy(header.data(),peer,sizeof(Plugin));
  const auto info=peer->info;std::array<uint8_t,sizeof(vl_private_osc::Info)>metadata{};std::memcpy(metadata.data(),info,metadata.size());
  std::array<uint8_t,sizeof(sn)>subjectNotes{};std::array<uint8_t,sizeof(Note)>peerNote{},controlNote{};
  std::memcpy(subjectNotes.data(),sn.data(),sizeof sn);std::memcpy(peerNote.data(),&pn,sizeof pn);std::memcpy(controlNote.data(),&cn,sizeof cn);
  const unsigned computations=peerHost->computes,notifications=peerHost->notices;
  close(0,subject,route);require(subjectHost->alive,"Cleanup ended caller host lifetime");
  require(!std::memcmp(subjectNotes.data(),sn.data(),sizeof sn)&&!std::memcmp(peerNote.data(),&pn,sizeof pn)&&!std::memcmp(controlNote.data(),&cn,sizeof cn),"Cleanup modified borrowed note storage");
  require(peerState==saved(peer)&&!std::memcmp(header.data(),peer,sizeof(Plugin))&&!std::memcmp(metadata.data(),info,metadata.size()),"Cleanup changed live peer raw/header/shared metadata");
  require(peerHost->computes==computations&&peerHost->notices==notifications,"Cleanup delivered an unexpected peer callback");
  for(int block=0;block<3;++block)audioFloats+=renderPair(peer,control,pn,cn,true);
  close(1,peer,(route+1)%3);close(2,control,(route+2)%3);
  require(liveAllocations==baseline&&unknownDeletes==unknown&&!trackerOverflow,"Owned C++ allocation graph did not return to baseline");
  delete subjectHost;delete peerHost;delete controlHost;
  ++pairs;if(route==1)++complete;else if(route==2)++deleting;else ++ordinary;
 }
 std::cout<<"{\"status\":\"passed_own_three_osc_factory_lifetime\",\"variant\":"<<VL_LIFETIME_VARIANT<<",\"pairs\":"<<pairs<<",\"source_instances\":"<<pairs*3<<",\"complete_caller_free\":"<<complete<<",\"deleting\":"<<deleting<<",\"DestroyObject\":"<<ordinary<<",\"live_subjects\":"<<liveSubjects<<",\"allocation_failures\":"<<allocationFailures<<",\"exact_peer_reference_audio_floats\":"<<audioFloats<<",\"Cxx_allocation_graph_restored\":true,\"original_images_loaded\":false,\"original_extra_destructor_equivalence\":false,\"full_plugin_equivalence\":false}\n";return 0;
 }catch(const std::exception&e){allocationBudget=-1;std::cerr<<e.what()<<'\n';return 1;}}
