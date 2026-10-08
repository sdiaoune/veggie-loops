#pragma once

#include "three_osc.hpp"

#include <array>
#include <cmath>
#include <memory>
#include <stdexcept>
#include <vector>

namespace veggie_loops::three_osc {

struct alignas(16) FourLaneComplex {
  std::array<float, 4> real{};
  std::array<float, 4> imaginary{};
};
static_assert(sizeof(FourLaneComplex) == 32);

inline FourLaneComplex plus(const FourLaneComplex& a, const FourLaneComplex& b) {
  FourLaneComplex result;
  for (std::size_t i = 0; i < 4; ++i) {
    result.real[i] = a.real[i] + b.real[i];
    result.imaginary[i] = a.imaginary[i] + b.imaginary[i];
  }
  return result;
}
inline FourLaneComplex minus(const FourLaneComplex& a, const FourLaneComplex& b) {
  FourLaneComplex result;
  for (std::size_t i = 0; i < 4; ++i) {
    result.real[i] = a.real[i] - b.real[i];
    result.imaginary[i] = a.imaginary[i] - b.imaginary[i];
  }
  return result;
}
inline FourLaneComplex complexProduct(const FourLaneComplex& a,
                                      const FourLaneComplex& twiddle) {
  FourLaneComplex result;
  for (std::size_t i = 0; i < 4; ++i) {
    result.real[i] = std::fma(twiddle.real[i], a.real[i],
                             twiddle.imaginary[i] * -a.imaginary[i]);
    result.imaginary[i] = std::fma(twiddle.imaginary[i], a.real[i],
                                  twiddle.real[i] * a.imaginary[i]);
  }
  return result;
}

// Independent mixed-radix FFT implementation derived from the observed native
// factorization, recursion and butterfly arithmetic. Four independent scalar
// lanes reproduce the engine's SIMD data layout without embedding its code.
class FFTPlan {
 public:
  FFTPlan(int size, bool inverse)
      : size_(validatedSize(size)), inverse_(inverse), twiddles_(size_) {
    for (int i = 0; i < size; ++i) {
      double angle = (static_cast<double>(i) * -6.283185307179586) / size;
      if (inverse) angle = -angle;
      double sine, cosine;
#if defined(__APPLE__)
      __sincos(angle, &sine, &cosine);
#else
      sine = std::sin(angle); cosine = std::cos(angle);
#endif
      twiddles_[i].real.fill(static_cast<float>(cosine));
      twiddles_[i].imaginary.fill(static_cast<float>(sine));
    }
    int remaining = size, factor = 4;
    do {
      while (remaining % factor != 0) {
        factor = factor == 4 ? 2 : factor == 2 ? 3 : factor + 2;
        if (factor > static_cast<int>(std::sqrt(static_cast<double>(size)))) factor = remaining;
      }
      remaining /= factor;
      factors_.push_back({factor, remaining});
    } while (remaining > 1);
  }
  int size() const { return size_; }
  const std::vector<FourLaneComplex>& twiddles() const { return twiddles_; }
  const std::vector<std::array<int, 2>>& factors() const { return factors_; }
  void transform(const FourLaneComplex* input, FourLaneComplex* output, int inputStride = 1) const {
    if (input == output) {
      std::vector<FourLaneComplex> temporary(size_);
      work(temporary.data(), input, 1, inputStride, 0);
      std::copy(temporary.begin(), temporary.end(), output);
    } else work(output, input, 1, inputStride, 0);
  }

 private:
  static int validatedSize(int size) {
    if (size < 1 || size > 1 << 20) throw std::invalid_argument("FFT size out of bounds");
    return size;
  }
  void work(FourLaneComplex* output, const FourLaneComplex* input,
            int stride, int inputStride, std::size_t stage) const {
    const auto [radix, m] = factors_[stage];
    if (m == 1) {
      for (int i = 0; i < radix; ++i) output[i] = input[i * stride * inputStride];
    } else {
      for (int i = 0; i < radix; ++i)
        work(output + i * m, input + i * stride * inputStride,
              stride * radix, inputStride, stage + 1);
    }
    if (radix == 2) {
      for (int k = 0; k < m; ++k) {
        const auto t = complexProduct(output[k + m], twiddles_[k * stride]);
        const auto base = output[k];
        output[k + m] = minus(base, t); output[k] = plus(base, t);
      }
    } else if (radix == 3) {
      const auto& root = twiddles_[m * stride];
      for (int k = 0; k < m; ++k) {
        const auto a = complexProduct(output[k + m], twiddles_[k * stride]);
        const auto b = complexProduct(output[k + 2 * m], twiddles_[2 * k * stride]);
        const auto sum = plus(a, b), difference = minus(a, b), base = output[k];
        output[k] = plus(base, sum);
        for (std::size_t lane = 0; lane < 4; ++lane) {
          const float centerReal = std::fma(-0.5f, sum.real[lane], base.real[lane]);
          const float centerImaginary = std::fma(-0.5f, sum.imaginary[lane], base.imaginary[lane]);
          const float crossReal = root.imaginary[lane] * difference.real[lane];
          const float crossImaginary = root.imaginary[lane] * difference.imaginary[lane];
          output[k + m].real[lane] = centerReal - crossImaginary;
          output[k + m].imaginary[lane] = crossReal + centerImaginary;
          output[k + 2 * m].real[lane] = crossImaginary + centerReal;
          output[k + 2 * m].imaginary[lane] = centerImaginary - crossReal;
        }
      }
    } else if (radix == 4) {
      for (int k = 0; k < m; ++k) {
        const auto a = complexProduct(output[k + m], twiddles_[k * stride]);
        const auto b = complexProduct(output[k + 2 * m], twiddles_[2 * k * stride]);
        const auto c = complexProduct(output[k + 3 * m], twiddles_[3 * k * stride]);
        const auto difference = minus(output[k], b);
        const auto base = plus(output[k], b);
        const auto sum = plus(a, c), cross = minus(a, c);
        output[k] = plus(base, sum); output[k + 2 * m] = minus(base, sum);
        for (std::size_t lane = 0; lane < 4; ++lane) {
          if (inverse_) {
            output[k + m].real[lane] = difference.real[lane] - cross.imaginary[lane];
            output[k + m].imaginary[lane] = difference.imaginary[lane] + cross.real[lane];
            output[k + 3 * m].real[lane] = difference.real[lane] + cross.imaginary[lane];
            output[k + 3 * m].imaginary[lane] = difference.imaginary[lane] - cross.real[lane];
          } else {
            output[k + m].real[lane] = difference.real[lane] + cross.imaginary[lane];
            output[k + m].imaginary[lane] = difference.imaginary[lane] - cross.real[lane];
            output[k + 3 * m].real[lane] = difference.real[lane] - cross.imaginary[lane];
            output[k + 3 * m].imaginary[lane] = difference.imaginary[lane] + cross.real[lane];
          }
        }
      }
    } else if (radix == 5) {
      const auto& ya = twiddles_[m * stride];
      const auto& yb = twiddles_[2 * m * stride];
      for (int k = 0; k < m; ++k) {
        const auto a = complexProduct(output[k + m], twiddles_[k * stride]);
        const auto b = complexProduct(output[k + 2 * m], twiddles_[2 * k * stride]);
        const auto c = complexProduct(output[k + 3 * m], twiddles_[3 * k * stride]);
        const auto d = complexProduct(output[k + 4 * m], twiddles_[4 * k * stride]);
        const auto outside = plus(a, d), inside = plus(b, c);
        const auto outsideDifference = minus(a, d), insideDifference = minus(b, c);
        const auto base = output[k];
        output[k] = plus(plus(base, outside), inside);
        for (std::size_t lane = 0; lane < 4; ++lane) {
          const float centerReal = std::fma(yb.real[lane], inside.real[lane],
              std::fma(ya.real[lane], outside.real[lane], base.real[lane]));
          const float centerImaginary = std::fma(yb.real[lane], inside.imaginary[lane],
              std::fma(ya.real[lane], outside.imaginary[lane], base.imaginary[lane]));
          const float crossReal = std::fma(ya.imaginary[lane], outsideDifference.imaginary[lane],
              yb.imaginary[lane] * insideDifference.imaginary[lane]);
          const float crossImaginary = std::fma(-yb.imaginary[lane], insideDifference.real[lane],
              ya.imaginary[lane] * -outsideDifference.real[lane]);
          output[k + m].real[lane] = centerReal - crossReal;
          output[k + m].imaginary[lane] = centerImaginary - crossImaginary;
          output[k + 4 * m].real[lane] = crossReal + centerReal;
          output[k + 4 * m].imaginary[lane] = centerImaginary + crossImaginary;
          const float center2Real = std::fma(ya.real[lane], inside.real[lane],
              std::fma(yb.real[lane], outside.real[lane], base.real[lane]));
          const float center2Imaginary = std::fma(ya.real[lane], inside.imaginary[lane],
              std::fma(yb.real[lane], outside.imaginary[lane], base.imaginary[lane]));
          const float cross2Real = std::fma(ya.imaginary[lane], insideDifference.imaginary[lane],
              yb.imaginary[lane] * -outsideDifference.imaginary[lane]);
          const float cross2Imaginary = std::fma(yb.imaginary[lane], outsideDifference.real[lane],
              ya.imaginary[lane] * -insideDifference.real[lane]);
          output[k + 2 * m].real[lane] = cross2Real + center2Real;
          output[k + 2 * m].imaginary[lane] = center2Imaginary + cross2Imaginary;
          output[k + 3 * m].real[lane] = center2Real - cross2Real;
          output[k + 3 * m].imaginary[lane] = center2Imaginary - cross2Imaginary;
        }
      }
    } else {
      // Generic prime radix uses the observed modular twiddle accumulation.
      std::vector<FourLaneComplex> scratch(radix);
      for (int k = 0; k < m; ++k) {
        for (int r = 0; r < radix; ++r) scratch[r] = output[k + r * m];
        for (int r = 0; r < radix; ++r) {
          FourLaneComplex sum = scratch[0];
          const int frequency = k + r * m;
          for (int q = 1; q < radix; ++q)
            sum = plus(sum, complexProduct(scratch[q], twiddles_[
                (static_cast<std::int64_t>(q) * frequency * stride) % size_]));
          output[k + r * m] = sum;
        }
      }
    }
  }
  int size_;
  bool inverse_;
  std::vector<FourLaneComplex> twiddles_;
  std::vector<std::array<int, 2>> factors_;
};

inline int nextFastSize(int value) {
  if (value < 1 || value > 1 << 20) throw std::invalid_argument("FFT size out of bounds");
  for (;; ++value) {
    int remaining = value;
    for (int factor : {2, 3, 5}) while (remaining % factor == 0) remaining /= factor;
    if (remaining == 1) return value;
  }
}

class FFTFilter {
 public:
  explicit FFTFilter(int size)
      : size_(size), forward_(size, false), inverse_(size, true), spectrum_(size), temporary_(size) {
    previous_.fill(size / 2);
  }
  void prepare(const std::vector<std::array<float, 4>>& input) {
    if (input.size() != static_cast<std::size_t>(size_)) throw std::invalid_argument("FFT input length mismatch");
    previous_.fill(size_ / 2);
    for (int i = 0; i < size_; ++i) {
      temporary_[i].real = input[i]; temporary_[i].imaginary.fill(0);
    }
    forward_.transform(temporary_.data(), spectrum_.data());
  }
  std::vector<std::array<float, 4>> filter(const std::array<int, 4>& cutoffs) {
    for (std::size_t lane = 0; lane < 4; ++lane) {
      if (cutoffs[lane] < 0 || cutoffs[lane] > size_ / 2)
        throw std::invalid_argument("FFT cutoff out of bounds");
      for (int j = cutoffs[lane]; j < previous_[lane]; ++j) {
        spectrum_[j + 1].real[lane] = spectrum_[j + 1].imaginary[lane] = 0;
        spectrum_[size_ - j - 1].real[lane] = spectrum_[size_ - j - 1].imaginary[lane] = 0;
      }
      previous_[lane] = cutoffs[lane];
    }
    inverse_.transform(spectrum_.data(), temporary_.data());
    const float scale = 1.0f / static_cast<float>(size_);
    std::vector<std::array<float, 4>> output(size_);
    for (int i = 0; i < size_; ++i)
      for (std::size_t lane = 0; lane < 4; ++lane) output[i][lane] = temporary_[i].real[lane] * scale;
    return output;
  }
 private:
  int size_;
  FFTPlan forward_, inverse_;
  std::array<int, 4> previous_;
  std::vector<FourLaneComplex> spectrum_, temporary_;
};

class OwnedMipMap {
 public:
  OwnedMipMap(const float* waveform, int length, int levelsPerOctave = 4, int oversampling = 16) {
    if (length < 2 || length > 16384 || levelsPerOctave < 1 || levelsPerOctave > 16 ||
        oversampling < 1 || oversampling > 64 || length * oversampling > (1 << 20))
      throw std::invalid_argument("Unverified mipmap configuration");
    const int levels = static_cast<int>(binaryLog(length) * levelsPerOctave);
    if (levels % 4 != 0) throw std::invalid_argument("Mipmap requires complete four-lane batches");
    const int size = length * oversampling;
    std::vector<std::array<float, 4>> input(size);
    double position = 0;
    const double advance = 1.0 / oversampling;
    for (int i = 0; i < size; ++i) {
      const float p = static_cast<float>(position);
      const int index = static_cast<int>(p), next = index + 1 < length ? index + 1 : 0;
      const float fraction = p - static_cast<float>(index);
      input[i].fill(std::fma(waveform[index], 1.0f - fraction, fraction * waveform[next]));
      position += advance;
    }
    FFTFilter filter(size); filter.prepare(input);
    const double step = std::exp2(1.0 / levelsPerOctave);
    double harmonics = length * 0.5;
    data_.resize(levels); pointers_.resize(levels); sizes_.assign(levels, size);
    for (int level = 0; level < levels; level += 4) {
      std::array<int, 4> cutoffs;
      for (auto& cutoff : cutoffs) {
        cutoff = std::max(1, static_cast<int>(harmonics)); harmonics /= step;
      }
      const auto result = filter.filter(cutoffs);
      for (int lane = 0; lane < 4; ++lane) {
        auto& wave = data_[level + lane]; wave.assign(size + 10, 0);
        for (int i = 0; i < size; ++i) wave[i] = result[i][lane];
        wave[size] = wave[0]; wave[size + 1] = wave[1];
        pointers_[level + lane] = wave.data();
      }
    }
    view_ = {levels, 0, pointers_.data(), sizes_.data()};
  }
  MipMap* view() { return &view_; }
 private:
  MipMap view_;
  std::vector<std::vector<float>> data_;
  std::vector<float*> pointers_;
  std::vector<int> sizes_;
};

class OwnedWaveTable {
 public:
  OwnedWaveTable(const float* waveforms, int length, int count,
                 int levelsPerOctave = 4, int oversampling = 16) {
    if (count < 1 || count > 4) throw std::invalid_argument("Waveform count out of bounds");
    for (int i = 0; i < count; ++i) {
      maps_.push_back(std::make_unique<OwnedMipMap>(waveforms + i * length, length,
                                                  levelsPerOctave, oversampling));
      pointers_.push_back(maps_.back()->view());
    }
    pointers_.push_back(pointers_.back()); pointers_.push_back(pointers_.back());
    view_ = {count, 0, pointers_.data()};
  }
  WaveTable* view() { return &view_; }
 private:
  WaveTable view_;
  std::vector<std::unique_ptr<OwnedMipMap>> maps_;
  std::vector<MipMap*> pointers_;
};

inline std::vector<float> factoryWaveforms() {
  std::vector<float> waveforms(4 * 2048);
  OscState state; state.phaseIncrement = 0;
  for (int waveform = 1; waveform <= 4; ++waveform) {
    state.waveform = waveform;
    for (int i = 0; i < 2048; ++i)
      waveforms[(waveform - 1) * 2048 + i] = processWave(state, i * 0.00048828125f);
  }
  return waveforms;
}

inline std::vector<float> downsampleCustom(const float* input, int length) {
  if (length < 2048 || length > 1 << 20) throw std::invalid_argument("Custom wave length out of bounds");
  const int stride = length / 2048;
  std::vector<float> result(2048);
  for (int i = 0; i < 2048; ++i) {
    float sum = 0;
    for (int j = 0; j < stride; ++j) sum += input[i * stride + j];
    result[i] = sum / static_cast<float>(stride);
  }
  return result;
}

}  // namespace veggie_loops::three_osc
