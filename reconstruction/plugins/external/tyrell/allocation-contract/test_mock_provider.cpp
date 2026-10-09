#include "allocation_provider.hpp"
#include <iostream>
#include <stdexcept>

namespace {
namespace p = vl::tyrell::allocation_provider;
constexpr p::Codes codes{0,4,5}; // Controlled values, not OS observation.
constexpr p::Task task = 42;
constexpr unsigned inUse = 1;
struct NativeRange { std::uint64_t address, size; };
struct Backend {
  std::array<unsigned char,64> bytes{};
  unsigned calls = 0;
  p::Status status = 0;
  bool shortCopy = false;
};
struct Guarded {
  std::array<unsigned char,16> head{};
  std::array<unsigned char,64> payload{};
  std::array<unsigned char,16> tail{};
} scratch;
Backend backend;
p::Snapshot selected, peer;
p::Callbacks callbacks(codes);
p::Status primitive(void *context, std::uint64_t address, std::size_t count,
                    void *destination, std::uint64_t *copied) noexcept {
  auto &b = *static_cast<Backend*>(context); ++b.calls;
  if (b.status) return b.status;
  if (address < 0x1000 || count > b.bytes.size() || address-0x1000 > b.bytes.size()-count)
    return 99;
  std::memcpy(destination,b.bytes.data()+(address-0x1000),count);
  *copied = b.shortCopy ? count-1 : count;
  return codes.success;
}
p::ExactCopier copier(scratch.payload.data(),scratch.payload.size(),primitive,&backend,codes);
void require(bool yes,const char *message) { if(!yes) throw std::runtime_error(message); }
void begin() {
  backend = {}; for(std::size_t i=0;i<backend.bytes.size();++i)backend.bytes[i]=static_cast<unsigned char>(i+1);
  scratch.head.fill(0xa5);scratch.tail.fill(0x5a);scratch.payload.fill(0xcc);
  selected.reset(codes.success); selected.rows[1]={0xabcdef,0x123456};
  callbacks.activate(&copier,&selected,task,inUse);
  const NativeRange range{0x1000,64};callbacks.recorder(task,inUse,&range,1);
  require(selected.used==1&&!selected.failed,"Initial owned record rejected");
}
void guards() {
  for(auto b:scratch.head)require(b==0xa5,"Leading scratch guard changed");
  for(auto b:scratch.tail)require(b==0x5a,"Trailing scratch guard changed");
}
void failed(p::Status expected,void *out) {
  require(out==nullptr&&selected.readerFailed&&selected.firstReaderFailure==expected,
          "Failure output/sticky status differs");
  require(!p::finish(selected,true,true)&&!selected.complete,
          "Successful provider admitted failed reader");
}
unsigned cases=0;
template<class F> void case_(const char *name,F body) {
  begin();try{body();guards();callbacks.deactivate();++cases;}
  catch(const std::exception &error){throw std::runtime_error(std::string(name)+": "+error.what());}
}
}
int main(){try{
  case_("wrong-task",[]{void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task+1,0x1000,8,&out)==codes.invalid,"Wrong task accepted");failed(codes.invalid,out);require(!backend.calls,"Wrong task reached primitive");});
  case_("zero",[]{void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task,0x1000,0,&out)==codes.invalid,"Zero read accepted");failed(codes.invalid,out);require(!backend.calls,"Zero reached primitive");});
  case_("oversize",[]{void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task,0x1000,p::maxCopyBytes+1,&out)==codes.invalid,"Oversize accepted");failed(codes.invalid,out);require(!backend.calls,"Oversize reached primitive");});
  case_("wrapping-address",[]{void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task,UINT64_MAX-3,8,&out)==codes.invalid,"Wrap accepted");failed(codes.invalid,out);require(!backend.calls,"Wrap reached primitive");});
  case_("OS-failure",[]{backend.status=99;void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task,0x1000,8,&out)==codes.failure,"OS failure accepted");failed(codes.failure,out);require(backend.calls==1,"OS primitive call differs");});
  case_("short-copy",[]{backend.shortCopy=true;void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task,0x1000,8,&out)==codes.failure,"Short copy accepted");failed(codes.failure,out);});
  case_("null-output",[]{require(callbacks.reader(task,0x1000,8,nullptr)==codes.invalid,"Null output accepted");failed(codes.invalid,nullptr);require(!backend.calls,"Null output reached primitive");});
  case_("fail-then-success-first-sticky",[]{void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task+1,0x1000,8,&out)==codes.invalid,"Initial failure missing");backend.status=99;require(callbacks.reader(task,0x1000,8,&out)==codes.failure,"Second failure missing");backend.status=0;require(callbacks.reader(task,0x1000,8,&out)==codes.success&&out==scratch.payload.data(),"Later valid read failed");require(selected.readerFailed&&selected.firstReaderFailure==codes.invalid,"Success cleared/changed first failure");require(!p::finish(selected,true,true),"Sticky failure admitted inventory");});
  case_("provider-success-despite-error",[]{backend.status=99;void *out=nullptr;(void)callbacks.reader(task,0x1000,8,&out);const bool providerReturnedSuccess=true;require(!p::finish(selected,providerReturnedSuccess,true),"Provider swallowed reader failure");});
  case_("recorder-after-error",[]{void *out=nullptr;(void)callbacks.reader(task+1,0x1000,8,&out);callbacks.recorder<NativeRange>(task,inUse,nullptr,1);require(selected.failed&&selected.used==1&&selected.rows[1].base==0xabcdef&&selected.rows[1].extent==0x123456,"Recorder copied after reader error");require(!p::finish(selected,true,true),"Recorder error admitted inventory");});
  case_("reset-isolated",[]{peer.reset(codes.success);peer.used=1;peer.rows[0]={0x3000,32};peer.readerFailed=peer.failed=true;peer.firstReaderFailure=77;void *out=nullptr;(void)callbacks.reader(task+1,0x1000,8,&out);selected.reset(codes.success);const NativeRange range{0x1000,64};callbacks.recorder(task,inUse,&range,1);require(callbacks.reader(task,0x1000,8,&out)==codes.success&&p::finish(selected,true,true),"Fresh capture remained failed");require(peer.used==1&&peer.rows[0].base==0x3000&&peer.rows[0].extent==32&&peer.readerFailed&&peer.failed&&peer.firstReaderFailure==77&&!peer.complete,"Reset changed peer capture");});
  case_("missing-copier",[]{callbacks.activate(nullptr,&selected,task,inUse);void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task,0x1000,8,&out)==codes.invalid,"Missing copier accepted");failed(codes.invalid,out);});
  case_("missing-snapshot",[]{callbacks.activate(&copier,nullptr,task,inUse);void *out=reinterpret_cast<void*>(1);require(callbacks.reader(task,0x1000,8,&out)==codes.invalid&&out==nullptr&&!selected.complete&&!backend.calls,"Unbound callback accepted");});
  case_("provider-failure",[]{require(!p::finish(selected,false,true)&&!selected.complete,"Failed provider accepted");});
  case_("thread-refusal",[]{require(!p::finish(selected,true,false)&&!selected.complete,"Thread refusal accepted");});
  case_("wrong-range-type",[]{const NativeRange range{0x2000,8};callbacks.recorder(task,inUse+1,&range,1);require(selected.failed&&selected.used==1&&!p::finish(selected,true,true),"Wrong type accepted");});
  case_("wrong-recorder-task",[]{const NativeRange range{0x2000,8};callbacks.recorder(task+1,inUse,&range,1);require(selected.failed&&selected.used==1&&!p::finish(selected,true,true),"Wrong recorder task accepted");});
  case_("null-ranges",[]{callbacks.recorder<NativeRange>(task,inUse,nullptr,1);require(selected.failed&&selected.used==1&&!p::finish(selected,true,true),"Null range accepted");});
  case_("capacity-overflow",[]{selected.used=p::maxRanges;const NativeRange range{0x2000,8};callbacks.recorder(task,inUse,&range,1);require(selected.failed&&selected.used==p::maxRanges&&!p::finish(selected,true,true),"Capacity overflow accepted");});
  case_("zero-base",[]{const NativeRange range{0,8};callbacks.recorder(task,inUse,&range,1);require(selected.failed&&selected.used==1&&!p::finish(selected,true,true),"Zero base accepted");});
  case_("zero-extent",[]{const NativeRange range{0x2000,0};callbacks.recorder(task,inUse,&range,1);require(selected.failed&&selected.used==1&&!p::finish(selected,true,true),"Zero extent accepted");});
  case_("wrapping-range",[]{const NativeRange range{UINT64_MAX-3,8};callbacks.recorder(task,inUse,&range,1);require(selected.failed&&selected.used==1&&!p::finish(selected,true,true),"Wrapping range accepted");});
  case_("overlapping-range",[]{const NativeRange range{0x1008,8};callbacks.recorder(task,inUse,&range,1);require(!p::finish(selected,true,true)&&!selected.complete,"Overlap accepted");});
  case_("valid-inventory",[]{void *out=nullptr;require(callbacks.reader(task,0x1000,8,&out)==codes.success&&out==scratch.payload.data()&&backend.calls==1&&!std::memcmp(out,backend.bytes.data(),8),"Valid copy differs");require(p::finish(selected,true,true)&&selected.complete&&!selected.readerFailed,"Valid synthetic inventory rejected");});
  case_("null-destination",[]{require(copier.read(0x1000,8,nullptr)==codes.invalid&&!backend.calls,"Null direct destination reached primitive");});
  require(cases==25,"Provider case count differs");
  std::cout<<"{\"status\":\"passed_controlled_provider_callbacks_only\",\"cases\":25,\"shared_production_callback_helper\":true,\"live_allocator_or_original_called\":false,\"live_bounds_certified\":false,\"full_plugin_equivalence\":false}\n";
  return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
