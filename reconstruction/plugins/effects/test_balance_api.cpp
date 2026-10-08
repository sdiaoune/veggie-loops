#include "balance_plugin.h"
#include <array>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>

int main(){
  auto check=[](bool ok){if(!ok)throw std::runtime_error("Balance C ABI check failed");};
  auto*plugin=vl_balance_create();check(plugin!=nullptr);
  int32_t value=0;check(vl_balance_parameter(plugin,1,0,2,&value) && value==256);
  std::array<unsigned char,8>state{};check(vl_balance_save_state(plugin,state.data(),state.size()));
  check(state==std::array<unsigned char,8>{0,0,0,0,0,1,0,0});
  check(vl_balance_parameter(plugin,0,0x40000000,33,&value) && value==128);
  check(vl_balance_parameter(plugin,1,0,1,&value));
  check(vl_balance_restore_state(plugin,state.data(),state.size()));
  check(vl_balance_parameter(plugin,0,0,2,&value) && value==0);
  vl_balance_resume(plugin);
  std::array<float,18>signal{};signal[0]=1;signal[1]=0.5f;signal[16]=-1;signal[17]=-2;
  check(vl_balance_render(plugin,signal.data(),signal.data(),9));
  check(signal[0]==1 && signal[1]==0.5f);
  float left=0,right=0;check(vl_balance_get_meters(plugin,&left,&right) && left==1 && right==0.5f);
  check(vl_balance_set_sample_rate(plugin,48000));check(!vl_balance_set_sample_rate(plugin,0));
  check(!vl_balance_parameter(plugin,0,129,1,&value));
  check(!vl_balance_parameter(plugin,1,321,1,&value));
  check(!vl_balance_parameter(plugin,-1,0,1,&value));
  check(!vl_balance_parameter(plugin,0,0,4,&value));
  check(!vl_balance_render(plugin,signal.data(),signal.data()+1,8));
  signal[0]=std::numeric_limits<float>::infinity();check(!vl_balance_render(plugin,signal.data(),signal.data(),9));
  state.fill(255);check(!vl_balance_restore_state(plugin,state.data(),8));
  vl_balance_destroy(plugin);vl_balance_destroy(nullptr);
  std::cout<<"Balance C ABI lifecycle, state, automation and render checks passed\n";
}
