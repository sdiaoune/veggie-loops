#pragma once
// Independently generated legacy waveform bank, from the reviewed native
// math/PRNG procedure. No shipped table bytes are embedded. The local noise
// generator has a nonstandard MT twist boundary that must be preserved.
#include <array>
#include <cmath>
#include <cstdint>
#include <span>

namespace veggie_loops::three_osc::legacy {
class NoiseGenerator {
  std::array<std::uint32_t,624> words_{};
  std::uint32_t index_=624;
public:
  explicit NoiseGenerator(std::uint32_t seed) {
    words_[0]=seed;
    for(std::uint32_t i=1;i<624;++i) words_[i]=i+(words_[i-1]^(words_[i-1]>>30))*1812433253u;
  }
  std::uint32_t next() {
    if(index_>=624) {
      const auto twist=[](std::uint32_t high,std::uint32_t low,std::uint32_t source) {
        const auto joined=(high&0x80000000u)|(low&0x7fffffffu);
        return source^(joined>>1)^((joined&1) ? 0x9908b0dfu : 0u);
      };
      for(std::uint32_t i=0;i<=226;++i) words_[i]=twist(words_[i],words_[i+1],words_[i+397]);
      // Native resumes at226, not227: that word is overwritten a second time
      // with the object index field (624) as the preceding source word.
      for(std::uint32_t i=226;i<623;++i)
        words_[i]=twist(words_[i],words_[i+1],i==226 ? index_ : words_[i-227]);
      words_[623]=twist(words_[623],words_[0],words_[396]);index_=0;
    }
    auto result=words_[index_++];result^=result>>11;result^=(result<<7)&0x9d2c5680u;
    result^=(result<<15)&0xefc60000u;return result^(result>>18);
  }
};
inline void generateTables(std::span<float,6*16384> output) {
  constexpr double step=0x1p-14;
  for(int i=0;i<16384;++i) {
    output[i]=static_cast<float>(std::sin((static_cast<double>(i*2)*3.141592653589793)*step));
    output[2*16384+i]=i<8192 ? 1.0f : -1.0f;
    output[3*16384+i]=static_cast<float>(static_cast<double>(i*2)*step-1.0);
  }
  for(int i=0;i<8192;++i)
    output[16384+((i+12288)%16384)]=static_cast<float>(static_cast<double>(i*4)*step-1.0);
  for(int i=8192;i<16384;++i)
    output[16384+((i+12288)%16384)]=static_cast<float>(1.0-static_cast<double>((i-8192)*4)*step);
  float decay=32767.0f;
  for(int i=0;i<7600;++i) {
    const float value=32767.0f-decay*2.0f;
    const auto quantized=static_cast<std::int32_t>(value);
    output[4*16384+i]=static_cast<float>(static_cast<double>(quantized)/32767.0);
    decay=static_cast<float>(static_cast<double>(decay)*0.997);
  }
  for(int i=7600;i<13653;++i) output[4*16384+i]=1.0f;
  for(int i=13653;i<16384;++i) output[4*16384+i]=-1.0f;
  NoiseGenerator random(19650218u);
  for(int i=0;i<16384;++i)
    output[5*16384+i]=static_cast<float>((static_cast<double>(random.next())*2.3283064370807974e-10)*2.0-1.0);
}
}
