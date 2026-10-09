#include "live_compressor.h"
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <array>
#include <new>
#include <stdexcept>
namespace {long failAfter=-1;}
void* operator new(std::size_t size){if(failAfter>=0&&failAfter--==0)throw std::bad_alloc();if(void*p=std::malloc(size?size:1))return p;throw std::bad_alloc();}
void operator delete(void*p) noexcept {std::free(p);}
void operator delete(void*p,std::size_t) noexcept {std::free(p);}
void* operator new(std::size_t size,const std::nothrow_t&) noexcept {try{return ::operator new(size);}catch(...){return nullptr;}}
void operator delete(void*p,const std::nothrow_t&) noexcept {std::free(p);}
namespace {
void require(bool ok,const char* text){if(!ok)throw std::runtime_error(text);}
}
int main(){try{
    unsigned faults=0;
    for(int kind:{5,6,7})for(int enabled:{0,1}){
        for(long step:{0L,1L}){
            failAfter=step;auto* failed=vl_purity_live_create(kind,enabled);failAfter=-1;require(!failed,"Creation failure crossed API");++faults;
        }
        auto* h=vl_purity_live_create(kind,1);require(h,"Setup factory");const std::array<float,3> parameters{.2f,.7f,.8f};
        require(vl_purity_live_sample_rate(h,48000)&&vl_purity_live_parameters(h,parameters.data()),"Setup controls");std::array<float,32> left{},right{};left.fill(4);right.fill(-4);
        require(vl_purity_live_process(h,left.data(),right.data(),32),"Setup processing");VLPurityLiveSnapshot before{},after{};require(vl_purity_live_snapshot(h,&before),"Setup snapshot");const void* prior=vl_purity_live_object(h);
        failAfter=0;const int replaced=vl_purity_live_replace(h,kind==7?6:7,enabled);failAfter=-1;
        require(!replaced&&vl_purity_live_object(h)==prior&&vl_purity_live_snapshot(h,&after)&&std::memcmp(&before,&after,sizeof before)==0,"Replacement failure lost old object/history");++faults;
        require(vl_purity_live_replace(h,kind==7?6:7,enabled),"Recovery replacement failed");vl_purity_live_destroy(h);
    }
    std::printf("{\"status\":\"passed\",\"allocation_failure_cases\":%u,\"atomic_replacement_failure_preserves_object_and_history\":true}\n",faults);return 0;
}catch(const std::exception&e){failAfter=-1;std::fprintf(stderr,"%s\n",e.what());return 1;}}
