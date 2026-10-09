#include "meter.hpp"
#include <bit>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>

using namespace vl::labs::meter;
#include "contract_boundaries.hpp"
namespace {
void require(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
}
bool same(const State &a, const State &b) { return !std::memcmp(&a, &b, sizeof a); }
}
int main() {
  try {
    // Synthetic caller-owned thresholds, not copied LABS constants/media.
    std::array<double,100> thresholds{};
    for (std::size_t i=0; i<thresholds.size(); ++i) thresholds[i]=double(i)/99.0;
    Transfer table{};
    require(build_transfer(thresholds,table),"Synthetic transfer failed");
    require(table.front()==0.0f && table.back()==1.0f,"Transfer endpoints differ");
    for (std::size_t i=1; i<table.size(); ++i) require(table[i]>=table[i-1],"Transfer is not monotone");
    float result=123.0f;
    require(lookup(-2.0f,table,result) && result==0.0f,"Lower clamp differs");
    require(lookup(2.0f,table,result) && result==1.0f,"Upper clamp differs");
    State state{};
    state.reserved={0x13,0x57,0x9b};
    state.fastLevel=.75f;state.slowLevel=.5f;
    state.fastRate=.25f;state.slowRate=.125f;
    state.fastRemaining=.25f;state.slowRemaining=.25f;
    state.activity=7;state.activityHold=1.0f;state.activityRemaining=.25f;
    require(advance(state,1.0f),"Hold advance failed");
    require(state.fastLevel==.75f && state.slowLevel==.5f && state.fastRemaining==0.0f && state.slowRemaining==0.0f && state.activity==7 && state.activityRemaining==0.0f,"Hold overrun incorrectly decayed or cleared early");
    require(advance(state,1.0f),"Decay advance failed");
    require(state.fastLevel==.5f && state.slowLevel==.375f && !state.activity,"Next-call decay/clear differs");
    require(state.reserved==std::array<std::uint8_t,3>{0x13,0x57,0x9b},"Reserved bytes changed");
    State asymmetry{};asymmetry.fastLevel=1.0f;asymmetry.fastRate=1.0f;asymmetry.slowLevel=-.25f;
    require(advance(asymmetry,.25f) && std::bit_cast<std::uint32_t>(asymmetry.slowLevel)==0,"Inactive channel was incorrectly skipped while peer active");
    State latch{};latch.olderSample=2.0f;latch.previousSample=0.0f;latch.activityHold=-1.0f;
    require(push_sample(latch,.5f,table) && latch.activity==0,"Historical peak incorrectly latched current sample");
    require(push_sample(latch,1.25f,table) && latch.activity==1 && latch.activityRemaining==-1.0f,"Current overshoot latch differs");
    require(advance(latch,64.0f) && latch.activity==1,"Negative activity duration should retain latch");
    State trailing{};trailing.fastLevel=.9f;trailing.slowLevel=.1f;trailing.slowHold=2.0f;
    require(push_sample(trailing,0.0f,table) && trailing.slowLevel==.9f && trailing.slowRemaining==2.0f,"Trailing peak did not follow retained fast level");
    const State before=trailing;
    require(!advance(trailing,-1.0f) && same(before,trailing),"Negative elapsed changed state");
    require(!push_sample(trailing,std::numeric_limits<float>::infinity(),table) && same(before,trailing),"Nonfinite sample changed state");
    auto invalid=table;invalid[9]=std::numeric_limits<float>::quiet_NaN();
    require(!push_sample(trailing,.5f,invalid) && same(before,trailing),"Invalid table changed state");
    const auto prior=table;thresholds.back()=.99;
    require(!build_transfer(thresholds,table) && !std::memcmp(prior.data(),table.data(),sizeof table),"Invalid endpoint changed transfer");
    result=123.0f;require(!lookup(.5f,std::span<const float>(table.data(),999),result) && result==123.0f,"Invalid count changed result");
    require(!lookup(.5f,table,table.front()) && !std::memcmp(prior.data(),table.data(),sizeof table),"Lookup table/output alias accepted");
    const auto counts = meter_contract_v2::run();
    std::cout<<"{\"status\":\"passed_own_meter_source_contract_v2\",\"lookup_boundary_cases\":"<<counts.lookups<<",\"transfer_boundary_cases\":"<<counts.builds<<",\"state_boundary_cases\":"<<counts.states<<",\"atomic_rejections\":"<<counts.atomics<<",\"original_called\":false,\"native_equivalence\":false,\"full_plugin_equivalence\":false}\n";
    return 0;
  } catch(const std::exception &e) { std::cerr<<e.what()<<'\n';return 1; }
}
