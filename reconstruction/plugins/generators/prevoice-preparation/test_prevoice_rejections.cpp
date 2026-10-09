#include "prevoice_channel.hpp"
#include <dlfcn.h>
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <vector>
using namespace vl_private_osc;
namespace pv=veggie_loops::three_osc::prevoice;
namespace {
void require(bool b,const char*m){if(!b)throw std::runtime_error(m);}
template<class T>T sym(void*l,const char*n){auto p=reinterpret_cast<T>(dlsym(l,n));require(p,"Missing test symbol");return p;}
void lr(void*,float*l,float*r,float p,float v){*l=v*std::sqrt((1-p)*.5f);*r=v*std::sqrt((1+p)*.5f);}
struct Host{void**methods;};
struct Stream{void**methods;std::vector<uint8_t>bytes;size_t cursor=0,calls=0;int badCall=0;bool shortCount=false;};
int32_t read(Stream*s,void*v,uint32_t n,uint32_t*c){++s->calls;if(n>s->bytes.size()-s->cursor)return int32_t(0x8003001e);std::memcpy(v,s->bytes.data()+s->cursor,n);s->cursor+=n;if(c)*c=(int(s->calls)==s->badCall&&s->shortCount)?n-1:n;return int(s->calls)==s->badCall&&!s->shortCount?int32_t(0x80030009):0;}
int32_t write(Stream*s,const void*v,uint32_t n,uint32_t*c){auto*b=static_cast<const uint8_t*>(v);s->bytes.insert(s->bytes.end(),b,b+n);if(c)*c=n;return 0;}
}
int main(int argc,char**argv){try{
 require(argc==2,"Usage: rejections <new source DLL>");require(std::fegetround()==FE_TONEAREST,"Nearest-even required");void*l=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(l,"Source DLL load failed");
 auto create=sym<Plugin*(*)(void*,intptr_t)>(l,"CreatePlugInstance");auto cache=sym<int(*)(Plugin*,void*,size_t)>(l,"vl_private_prevoice_cache_snapshot");auto prepare=sym<int(*)(Plugin*,int32_t,double,uint32_t)>(l,"vl_private_osc_prepare");auto channel=sym<vl_osc_multimode_channel*(*)(Plugin*)>(l,"vl_private_osc_channel");auto phase=sym<int(*)(Plugin*,float,uint32_t*)>(l,"vl_private_prevoice_phase");
 std::array<void*,96>hm{};hm[31]=reinterpret_cast<void*>(&lr);Host host{hm.data()};std::array<void*,5>sm{};sm[3]=reinterpret_cast<void*>(&read);sm[4]=reinterpret_cast<void*>(&write);size_t rejects=0,successes=0;
 for(int live=0;live<2;++live){auto*p=create(&host,42);require(p,"Source factory failed");const auto f=p->functions;vl_osc_multimode_channel_parameters note{};note.initial.volume=.8f;note.final=note.initial;intptr_t voice=-1;
 if(live){require(prepare(p,44100,120,240),"Prepared source context failed");voice=f->trigger(p,&note,100);require(voice!=-1,"Prepared source trigger failed");++successes;}
 const auto snap=[&](){pv::Snapshot v{};require(cache(p,&v,sizeof v),"Snapshot failed");return v;};
 const auto state=[&](){Stream s{sm.data(),{}};f->state(p,&s,1);require(s.bytes.size()==460,"State save failed");return s.bytes;};
 const auto reject=[&](auto call){const auto before=snap();const auto saved=state();std::array<uint8_t,sizeof(Plugin)>header{};std::memcpy(header.data(),p,sizeof(Plugin));const auto oldNote=note;auto*c=channel(p);std::fenv_t env{},after{};require(std::fegetenv(&env)==0,"Reject caller fenv capture failed");require(std::feclearexcept(FE_ALL_EXCEPT)==0,"Reject clear failed");call();require(std::fetestexcept(FE_ALL_EXCEPT)==0,"Rejected input raised FP flags");require(std::fesetenv(&env)==0&&std::fegetenv(&after)==0&&!std::memcmp(&env,&after,sizeof env),"Reject caller fenv restore failed");const auto now=snap();require(!std::memcmp(&before,&now,sizeof before)&&saved==state()&&!std::memcmp(header.data(),p,sizeof(Plugin))&&!std::memcmp(&oldNote,&note,sizeof note)&&c==channel(p),"Rejected call changed cache/raw/note/header/channel");++rejects;};
 for(uint64_t bits:{0ull,0x8000000000000000ull,0x7ff0000000000000ull,0xfff0000000000000ull,0x7ff0000000000001ull,0x7ff8000000000001ull,0xbff0000000000000ull,std::bit_cast<uint64_t>(1001.)})reject([&]{require(!prepare(p,44100,std::bit_cast<double>(bits),240),"Invalid context accepted");});
 for(int rate:{-1,0,7999,384001,INT32_MAX})reject([&]{require(!prepare(p,rate,120,240),"Invalid rate accepted");});
 for(uint32_t ppq:{0u,1u,3u,(1u<<20)+1,UINT32_MAX})reject([&]{require(!prepare(p,44100,120,ppq),"Invalid PPQ accepted");});
 for(uint32_t bits:{0u,0x80000000u,0x7f800000u,0xff800000u,0x7f800001u,0x7fc00001u,0xbf800000u,std::bit_cast<uint32_t>(1001.f)})reject([&]{f->event(p,0,std::bit_cast<int32_t>(bits),0);});
 for(int rate:{-1,0,7999,384001,INT32_MAX})reject([&]{f->dispatch(p,4,0,rate);});
 for(uint32_t ppq:{0u,1u,3u,(1u<<20)+1,UINT32_MAX})reject([&]{std::array<uint32_t,3>sig{16,4,ppq};f->dispatch(p,14,0,reinterpret_cast<intptr_t>(sig.data()));});
 for(int g=0;g<5;++g){for(int j=0;j<17;++j){const std::array<int32_t,17>bad{64,2,-1,65537,-1,65537,129,-1,129,65537,-1,-129,65537,3,129,-129,129};reject([&]{f->parameter(p,23+g*17+j,bad[j],1);});}for(int j=1;j<17;++j)for(int v:{-1,1073741825})reject([&]{f->parameter(p,23+g*17+j,v,33);});}
 for(int index:{-1,114,INT32_MAX})reject([&]{f->parameter(p,index,1,1);});
 for(int index:{110,111,113})for(int v:{-1,index==113?8:257})reject([&]{f->parameter(p,index,v,1);});
 const auto valid=state();for(size_t offset:{size_t(0),size_t(4),size_t(91),size_t(96),size_t(440+4),size_t(444+4),size_t(452+4)}){auto bytes=valid;if(offset==0){uint32_t v=13;std::memcpy(bytes.data(),&v,4);}else if(offset==91)bytes[offset]=3;else{int32_t v=INT32_MAX;std::memcpy(bytes.data()+offset,&v,4);}reject([&]{Stream s{sm.data(),bytes};f->state(p,&s,0);});}
 for(int failure:{1,2})for(bool shortRead:{false,true})reject([&]{Stream s{sm.data(),valid,0,0,failure,shortRead};f->state(p,&s,0);});
 for(int i=0;i<10;++i)for(uint32_t bits:{0x7f800001u,0x7fc00001u,0x7f800000u,0xff800000u})reject([&]{auto bad=note;std::memcpy(reinterpret_cast<char*>(&bad)+i*4,&bits,4);const auto saved=bad;require(f->trigger(p,&bad,500)==-1&&!std::memcmp(&bad,&saved,sizeof bad),"Invalid note accepted/mutated");});
 reject([&]{require(f->trigger(p,nullptr,0)==-1,"Null note accepted");});
 std::array<uint8_t,sizeof(pv::Snapshot)+16>guard{};guard.fill(0xa5);for(size_t n:{size_t(0),sizeof(pv::Snapshot)-1,sizeof(pv::Snapshot)+1})reject([&]{auto old=guard;require(!cache(p,guard.data()+8,n)&&guard==old,"Invalid inspection size accepted/mutated");});
 reject([&]{require(!cache(p,nullptr,sizeof(pv::Snapshot)),"Null output accepted");});reject([&]{require(!cache(p,p,sizeof(pv::Snapshot)),"Instance/output alias accepted");});
 for(uint32_t bits:{0x7f800001u,0x7fc00001u,0x7f800000u,0xff800000u,std::bit_cast<uint32_t>(2401.f)})reject([&]{uint32_t out=0xa5a5a5a5;require(!phase(p,std::bit_cast<float>(bits),&out)&&out==0xa5a5a5a5,"Invalid phase diagnostic accepted/mutated");});
 if(live)reject([&]{require(!prepare(p,48000,140,96),"Explicit prepare accepted live voices");});
 if(live)f->kill(p,voice);f->destroy(p);
 }
 dlclose(l);std::cout<<"{\"status\":\"passed_prevoice_source_rejection_atomics\",\"atomic_rejections\":"<<rejects<<",\"positive_setup_checks\":"<<successes<<",\"states\":2,\"original_malformed_inputs_executed\":false,\"full_plugin_equivalence\":false}\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
