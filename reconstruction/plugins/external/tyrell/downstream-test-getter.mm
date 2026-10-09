// Private identity-bound getter replay; scalar words restored before other callbacks.
#if !defined(__APPLE__) || !defined(__x86_64__)
#error Intel Tyrell layout only.
#endif
#define main vl_probe_unused_main
#include "../../../../reconstruction/plugins/common/vst2_probe.mm"
#undef main
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include "downstream-getter.h"
#include <bit>
#include <limits>
template<class T>T field(const void*p,size_t o){T v;std::memcpy(&v,static_cast<const char*>(p)+o,sizeof v);return v;}
static std::string sha(const std::string&path){std::ifstream f(path,std::ios::binary);require(bool(f),"No target");CC_SHA256_CTX c;CC_SHA256_Init(&c);std::array<char,65536>b;while(f.read(b.data(),b.size())||f.gcount())CC_SHA256_Update(&c,b.data(),CC_LONG(f.gcount()));require(f.eof(),"Read failed");std::array<unsigned char,32>d;CC_SHA256_Final(d.data(),&c);std::string h;for(auto x:d){h+="0123456789abcdef"[x>>4];h+="0123456789abcdef"[x&15];}return h;}
int main(int argc,char**argv){std::cout<<std::unitbuf;@autoreleasepool{try{
 require(argc==2,"Expected bundle");require(sha(std::string(argv[1])+"/Contents/MacOS/TyrellN6")=="a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54","Identity mismatch");
 transport.sampleRate=48000;transport.tempo=120;
 Bundle bundle;auto u=CFURLCreateFromFileSystemRepresentation(nullptr,reinterpret_cast<const UInt8*>(argv[1]),std::strlen(argv[1]),true);require(u,"URL");bundle.value=CFBundleCreate(nullptr,u);CFRelease(u);require(bundle.value&&CFBundleLoadExecutable(bundle.value),"Bundle load");
 auto entry=reinterpret_cast<Effect*(*)(Dispatch)>(CFBundleGetFunctionPointerForName(bundle.value,CFSTR("VSTPluginMain")));require(entry,"Entry");Dl_info image{};require(dladdr(reinterpret_cast<void*>(entry),&image)&&image.dli_fbase,"Base");auto base=reinterpret_cast<uintptr_t>(image.dli_fbase);require(reinterpret_cast<uintptr_t>(entry)-base==0x3ddb0,"Entry offset");
 Instance instance;instance.value=entry(host);auto*e=instance.value;require(e&&e->magic==0x56737450,"Factory");e->dispatcher(e,0,0,0,nullptr,0);instance.opened=true;
 void*manager=field<void*>(e->object,0x138);require(manager,"Manager");
 void*audio=field<void*>(manager,0x40),*target=field<void*>(manager,0x48);require(audio&&target,"Receivers");
 require(audio==target,"Receiver identity changed");
 auto** actualVtable=field<void**>(audio,0);
 require(reinterpret_cast<uintptr_t>(actualVtable)-base==0x3173b0&&reinterpret_cast<uintptr_t>(actualVtable[0x2d8/8])-base==0x153620&&reinterpret_cast<uintptr_t>(actualVtable[0x320/8])-base==0x153500&&reinterpret_cast<uintptr_t>(actualVtable[0x298/8])-base==0x154430&&reinterpret_cast<uintptr_t>(actualVtable[0x2c8/8])-base==0x154450,"Receiver ABI changed");
 auto print=[&](const char*name,void*p,std::initializer_list<size_t> slots){auto**vt=field<void**>(p,0);std::cout<<name<<" object="<<std::hex<<reinterpret_cast<uintptr_t>(p)<<" vtable="<<reinterpret_cast<uintptr_t>(vt)-base<<'\n';for(size_t slot:slots){Dl_info f{};require(dladdr(vt[slot/8],&f)&&f.dli_fbase,"Function base");std::cout<<name<<" slot="<<std::hex<<slot<<" method="<<reinterpret_cast<uintptr_t>(vt[slot/8])-reinterpret_cast<uintptr_t>(f.dli_fbase)<<" image="<<f.dli_fname<<'\n';}};
 print("audio",audio,{0x298,0x2d8,0x320});print("target",target,{0x298,0x2c8});std::cout<<"same_receiver="<<(audio==target)<<" clock="<<std::hexfloat<<*field<float*>(manager,0x58)<<'\n';
 void* config=field<void*>(audio,0x428);require(config,"Live configuration missing");
 void* descriptors=field<void*>(config,0);auto* raw=field<float*>(config,0x10);auto** pointers=field<void**>(config,0x18);auto* specialMap=field<int32_t*>(config,0x28);auto* records=field<unsigned char*>(config,0x38);auto* publicMap=field<int32_t*>(config,0x78);
 require(descriptors&&raw&&pointers&&publicMap,"Live storage incomplete");
 std::cout<<"internal_count="<<std::dec<<field<int32_t>(audio,0x4c4)<<" public_count="<<field<int32_t>(audio,0x4c8)<<" special_count="<<field<int32_t>(audio,0x4cc)<<" descriptor_bases_equal="<<(descriptors==field<void*>(audio,0x4e0))<<" public_maps_equal="<<(publicMap==field<void*>(audio,0x4c0))<<" config_queue_count="<<field<int32_t>(config,0x20)<<" audio_immediate="<<unsigned(field<uint8_t>(audio,0x4bc))<<" audio_depth="<<field<int32_t>(audio,0x5a0)<<'\n';
 auto getRaw=reinterpret_cast<float(*)(void*,int32_t,float,int32_t)>(field<void**>(audio,0)[0x2d8/8]);
 for(int32_t i=0;i<92;++i){const int32_t id=publicMap[i];require(id>=0&&id<field<int32_t>(audio,0x4c4),"Map bound");auto* d=static_cast<unsigned char*>(descriptors)+size_t(id)*116;const int32_t type=field<int32_t>(d,0x48);const uint8_t flags=field<uint8_t>(d,0x5c);float prepared=raw[id];const char* route="raw";int32_t special=-1;
  if(flags&2){require(specialMap&&records,"Special storage");special=specialMap[id];require(special>=0,"Special index");prepared=field<float>(records,size_t(special)*16+12);route="special";}
  else if(type==0&&field<void*>(pointers,size_t(id)*8)){prepared=float(field<int32_t>(field<void*>(pointers,size_t(id)*8),0));route="int_pointer";}
  else if(type==3){require(field<void*>(pointers,size_t(id)*8),"Meter pointer");prepared=field<float>(field<void*>(pointers,size_t(id)*8),0);route="float_pointer";}
  const float internal=getRaw(audio,id,1234.5f,0),external=getRaw(audio,i,-987.25f,1);
  uint32_t b0,b1,b2;std::memcpy(&b0,&prepared,4);std::memcpy(&b1,&internal,4);std::memcpy(&b2,&external,4);require(b0==b1&&b1==b2,"Real raw storage route differs");
  std::cout<<"storage public="<<std::dec<<i<<" id="<<id<<" type="<<type<<" flags="<<unsigned(flags)<<" route="<<route<<" special="<<special<<" raw="<<std::hexfloat<<raw[id]<<" value="<<prepared<<" bits="<<std::hex<<b0<<'\n';
 }
 const int32_t internalCount=field<int32_t>(audio,0x4c4),specialCount=field<int32_t>(audio,0x4cc),publicCount=field<int32_t>(audio,0x4c8);
 require(internalCount==213&&publicCount==92&&specialCount>0&&specialCount<=213,"Configuration geometry");
 require(field<int32_t>(config,8)==internalCount&&static_cast<void*>(raw)==static_cast<unsigned char*>(config)+400,"Config allocation geometry");
 VLTyrellRawView view{descriptors,raw,pointers,specialMap,records,publicMap,uint32_t(internalCount),uint32_t(specialCount),uint32_t(publicCount)};
 const std::array<uint32_t,8> fallbacks{0,0x80000000u,0x7f800000u,0xff800000u,0x7fc12345u,0x7f812345u,0x3f800001u,0x00000001u};
 uint64_t comparisons=0,metadataIds=0;std::array<unsigned,4> routes{};
 for(int32_t id=0;id<internalCount;++id){auto*d=static_cast<unsigned char*>(descriptors)+size_t(id)*116;const int32_t type=field<int32_t>(d,72);const uint32_t flags=field<uint32_t>(d,92);
  if(type==3&&!field<void*>(pointers,size_t(id)*8)&&!(flags&2)){std::cout<<"skipped_unconfigured_meter_id="<<std::dec<<id<<'\n';continue;}
  const int route=flags&2?0:type==0&&field<void*>(pointers,size_t(id)*8)?1:type==3?2:3;++routes[size_t(route)];++metadataIds;
  for(uint32_t b: fallbacks){const float fallback=std::bit_cast<float>(b);float out=1234;require(vl_tyrell_raw_get(&view,id,0,fallback,&out),"Compiled real storage getter rejected");const float native=getRaw(audio,id,fallback,0);require(std::bit_cast<uint32_t>(out)==std::bit_cast<uint32_t>(native),"Compiled real storage getter differs");++comparisons;}
 }
 for(int32_t i=0;i<publicCount;++i)for(uint32_t b:fallbacks){const float fallback=std::bit_cast<float>(b);float out=1234;require(vl_tyrell_raw_get(&view,i,1,fallback,&out),"Compiled public getter rejected");require(std::bit_cast<uint32_t>(out)==std::bit_cast<uint32_t>(getRaw(audio,i,fallback,1)),"Compiled public getter differs");++comparisons;}
 uint64_t mutableComparisons=0;std::array<int32_t,4> chosen{-1,-1,-1,-1};
 for(int32_t id=0;id<internalCount;++id){auto*d=static_cast<unsigned char*>(descriptors)+size_t(id)*116;const int32_t type=field<int32_t>(d,72);const uint32_t flags=field<uint32_t>(d,92);const int route=flags&2?0:type==0&&field<void*>(pointers,size_t(id)*8)?1:type==3&&field<void*>(pointers,size_t(id)*8)?2:3;if(chosen[size_t(route)]<0)chosen[size_t(route)]=id;}
 for(size_t route=0;route<4;++route){const int32_t id=chosen[route];require(id>=0,"Representative route missing");
  void* destination=route==0?records+size_t(specialMap[id])*16+12:route==1||route==2?field<void*>(pointers,size_t(id)*8):raw+id;
  const uint32_t initialWord=field<uint32_t>(destination,0);
  {
  struct RestoreWord{void*p;uint32_t original;explicit RestoreWord(void*v):p(v),original(field<uint32_t>(v,0)){}~RestoreWord(){std::memcpy(p,&original,4);}} restore(destination);
  std::array<uint32_t,16> edges{0,0x80000000u,0x7f800000u,0xff800000u,0x7fc12345u,0x7f812345u,0x00000001u,0x007fffffu,0x00800000u,0x7f7fffffu,0xff7fffffu,0x7fffffffu,0x01000000u,0x01000001u,0xff000001u,0xffffffffu};
  uint32_t randomBits=0x941278u;
  for(unsigned n=0;n<1040;++n){randomBits=randomBits*1664525u+1013904223u;const uint32_t bits=n<edges.size()?edges[n]:randomBits;std::memcpy(destination,&bits,4);
   const float native=getRaw(audio,id,0.0f,0);float source=1234;require(vl_tyrell_raw_get(&view,id,0,0,&source),"Getter content route rejected");require(std::bit_cast<uint32_t>(native)==std::bit_cast<uint32_t>(source),"Getter content route differs");++mutableComparisons;
  }
  }
  require(field<uint32_t>(destination,0)==initialWord,"Scalar storage restoration failed");
 }
 std::cout<<"{\"status\":\"passed_actual_factory_storage\",\"actual_internal_ids\":"<<std::dec<<metadataIds<<",\"actual_public_ids\":92,\"comparisons\":"<<comparisons<<",\"special_routes\":"<<routes[0]<<",\"int_pointee_routes\":"<<routes[1]<<",\"meter_routes\":"<<routes[2]<<",\"raw_routes\":"<<routes[3]<<",\"same_receiver\":true,\"fallback_ignored\":true,\"saved_restored_content_comparisons\":"<<mutableComparisons<<",\"native_storage_modified\":true,\"native_storage_restored\":true,\"whole_plugin_equivalence\":false}\n";
 return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}
