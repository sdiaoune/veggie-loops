#include "../balance_native_abi.cpp"
// Own test module only: no installed-original storage is exposed or modified.
extern "C" std::int32_t VLBalanceProtocolMaxPoly(veggie_loops::balance::native::Plugin* p){
  return veggie_loops::balance::native::instance(p).maxPoly;
}
