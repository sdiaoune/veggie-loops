#include "balance_dsp.hpp"
#include <array>
#include <cmath>
#include <iostream>
#include <stdexcept>

int main() {
  using namespace veggie_loops::balance;
  const auto check=[](bool condition) { if(!condition)throw std::runtime_error("Balance model check failed"); };
  State state{};
  state.current={1,1,0,0};
  state.target={1,1,0,0};
  std::array<float,18> input{};
  input[0]=0.25f;input[1]=-0.5f;input[16]=-0.75f;input[17]=-1;
  auto output=input;
  process(state,output.data(),output.data(),9,1,0x1p-24f);
  check(output==input);
  check(state.meters[0]==0.25f && state.meters[1]==0.5f);
  state.target={0,0,1,1};
  process(state,input.data(),output.data(),9,1,0x1p-24f);
  check(state.current==std::array<float,4>{0,0,1,1});
  check(output[0]==input[0] && output[1]==input[1]);
  process(state,input.data(),output.data(),9,1,0x1p-24f);
  check(output[0]==input[1] && output[1]==input[0]);
  float current=0.5f,start=0,step=0;
  slew(1,0.01f,10,0x1p-24f,current,start,step);
  check(start==0.5f && step==0.01f && std::fabs(current-0.6f)<0.000001f);
  current=0.01f;
  slew(0,0.0001f,128,0.02f,current,start,step);
  check(current==0 && start==0.01f);
  std::cout<<"Balance portable model checks passed\n";
}
