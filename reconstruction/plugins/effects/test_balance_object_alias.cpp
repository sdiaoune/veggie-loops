#include "balance_plugin.cpp"
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static void require(bool value,const char* label) {
  if(!value){std::fprintf(stderr,"FAILED: %s\n",label);std::exit(1);}
}
using Image=std::array<unsigned char,sizeof(VLBalancePlugin)>;
static Image image(const VLBalancePlugin* p) {
  Image out{};std::memcpy(out.data(),p,out.size());return out;
}
[[maybe_unused]] static void unchanged(const VLBalancePlugin* p,const Image& before,const char* label) {
  require(std::memcmp(before.data(),p,before.size())==0,label);
}
int main() {
  auto* p=vl_balance_create();require(p!=nullptr,"create");
#ifdef VL_BASELINE_EXPECT_ALIAS_BUG
  const auto before=image(p);
  const int accepted=vl_balance_parameter(p,1,0,2,&p->controls.raw[0]);
  require(accepted==1 && p->controls.raw[0]==256,"baseline writes volume into pan");
  require(std::memcmp(before.data(),p,before.size())!=0,"baseline instance changed");
  std::puts("baseline legal-live-member alias bug reproduced: volume getter overwrites pan=256");
#else
  int negatives=0;
  auto before=image(p);
  require(vl_balance_parameter(p,1,0,2,&p->controls.raw[0])==0,"get instance alias rejects");
  unchanged(p,before,"get instance alias atomic");++negatives;
  require(vl_balance_parameter(p,0,64,1,&p->controls.raw[1])==0,"set instance alias rejects");
  unchanged(p,before,"set instance alias atomic");++negatives;
  float left=17.0f,right=19.0f;
  require(vl_balance_get_meters(p,&p->state.meters[0],&right)==0,"left instance alias rejects");
  unchanged(p,before,"left meter atomic");require(right==19.0f,"right meter output preserved");++negatives;
  require(vl_balance_get_meters(p,&left,&p->state.meters[1])==0,"right instance alias rejects");
  unchanged(p,before,"right meter atomic");require(left==17.0f,"left meter output preserved");++negatives;
  require(vl_balance_get_meters(p,&left,&left)==0,"same meter output rejects");
  unchanged(p,before,"same meter atomic");require(left==17.0f,"same meter output preserved");++negatives;
  require(vl_balance_save_state(p,p->controls.raw.data(),8)==0,"save instance alias rejects");
  unchanged(p,before,"save instance alias atomic");++negatives;
  require(vl_balance_restore_state(p,p->controls.raw.data(),8)==0,"restore instance alias rejects");
  unchanged(p,before,"restore instance alias atomic");++negatives;
  std::array<float,4> input{0.25f,-0.5f,0.75f,1.0f},output{31.0f,37.0f,41.0f,43.0f};
  const auto outputBefore=output;
  require(vl_balance_render(p,p->state.current.data(),output.data(),2)==0,"render source instance alias rejects");
  unchanged(p,before,"source alias atomic");require(output==outputBefore,"render output preserved");++negatives;
  require(vl_balance_render(p,input.data(),p->state.current.data(),2)==0,"render destination instance alias rejects");
  unchanged(p,before,"destination alias atomic");++negatives;
  // A separate live member directly following an embedded instance is accepted.
  struct Adjacent {VLBalancePlugin plugin;int32_t result=71;};
  Adjacent adjacent;
  require(reinterpret_cast<uintptr_t>(&adjacent.result)>=reinterpret_cast<uintptr_t>(&adjacent.plugin)+sizeof(adjacent.plugin),"adjacent live output outside instance");
  require(vl_balance_parameter(&adjacent.plugin,1,0,2,&adjacent.result)==1 && adjacent.result==256,"adjacent output accepted");
  int32_t result=0;
  require(vl_balance_parameter(p,0,-64,1,&result)==1 && result==-64,"external pan set");
  require(vl_balance_parameter(p,1,200,1,&result)==1 && result==200,"external volume set");
  std::array<unsigned char,8> state{};
  require(vl_balance_save_state(p,state.data(),state.size())==1,"external state save");
  require(vl_balance_parameter(p,0,100,1,&result)==1,"temporary set");
  require(vl_balance_restore_state(p,state.data(),state.size())==1 && p->controls.raw[0]==-64 && p->controls.raw[1]==200,"external state restore");
  vl_balance_resume(p);
  auto expected=p->state;
  std::array<float,4> reference{};
  veggie_loops::balance::process(expected,input.data(),reference.data(),2,p->maximumStep,0x1p-24f);
  require(vl_balance_render(p,input.data(),output.data(),2)==1 && output==reference,"external render unchanged math");
  require(p->state.current==expected.current && p->state.target==expected.target && p->state.blockStart==expected.blockStart && p->state.increment==expected.increment && p->state.meters==expected.meters,"external render full named state");
  require(vl_balance_get_meters(p,&left,&right)==1 && left==p->state.meters[0] && right==p->state.meters[1],"external meters");
  auto inPlace=input;expected=p->state;
  veggie_loops::balance::process(expected,input.data(),reference.data(),2,p->maximumStep,0x1p-24f);
  require(vl_balance_render(p,inPlace.data(),inPlace.data(),2)==1 && inPlace==reference,"exact render in-place preserved");
  std::printf("repaired live-buffer contract: %d atomic alias rejections; external state, parameters, meters, adjacent output, separate/in-place render passed\n",negatives);
#endif
  vl_balance_destroy(p);return 0;
}
