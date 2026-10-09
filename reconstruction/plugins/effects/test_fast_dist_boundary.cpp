#include "fast_dist_plugin.cpp"
#include <array>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("Fast Dist atomic boundary check");
}
} // namespace
int main() {
  try {
    require(!vl_fast_dist_create(-1) && !vl_fast_dist_create(2));
    auto *p = vl_fast_dist_create(1);
    require(p);
    int32_t result = -1;
    for (int32_t index = 0; index < 5; ++index)
      require(
          vl_fast_dist_parameter(p, index, maximum[size_t(index)], 1, &result));
    const auto snapshot = [&] {
      std::array<std::byte, sizeof(*p)> bytes{};
      std::memcpy(bytes.data(), p, bytes.size());
      return bytes;
    };
    size_t rejections = 0;
    const auto reject = [&](auto action) {
      const auto before = snapshot();
      require(action() == 0 && snapshot() == before);
      ++rejections;
    };
    std::array<uint8_t, 20> packet{};
    require(vl_fast_dist_save_state(p, packet.data(), packet.size()));
    std::array<float, 8> audio{}, output{};
    for (float &value : output)
      value = 1234.0f;
    const auto outputBefore = output;
    const int32_t resultBefore = result;
    for (int32_t index = 0; index < 5; ++index) {
      for (int32_t value :
           {minimum[size_t(index)] - 1, maximum[size_t(index)] + 1})
        reject([&] {
          return vl_fast_dist_parameter(p, index, value, 1, &result);
        });
      for (int32_t value : {-1, (1 << 30) + 1})
        reject([&] {
          return vl_fast_dist_parameter(p, index, value, 33, &result);
        });
      auto invalid = packet;
      writeWord(invalid.data() + size_t(index) * 4,
                uint32_t(maximum[size_t(index)] + 1));
      reject([&] {
        return vl_fast_dist_restore_state(p, invalid.data(), invalid.size());
      });
      writeWord(invalid.data() + size_t(index) * 4, 0xffffffffu);
      reject([&] {
        return vl_fast_dist_restore_state(p, invalid.data(), invalid.size());
      });
    }
    for (int32_t index : {-1, 5})
      reject([&] { return vl_fast_dist_parameter(p, index, 0, 2, &result); });
    reject([&] { return vl_fast_dist_parameter(p, 0, 128, 4, &result); });
    reject([&] { return vl_fast_dist_quality(p, -1); });
    reject([&] { return vl_fast_dist_quality(p, 2); });
    require(result == resultBefore);
    for (int32_t frames : {-1, 1025})
      reject([&] {
        return vl_fast_dist_render(p, audio.data(), output.data(), frames);
      });
    reject([&] { return vl_fast_dist_render(p, nullptr, output.data(), 1); });
    reject([&] { return vl_fast_dist_render(p, audio.data(), nullptr, 1); });
    for (float value : {17.0f, -17.0f, std::numeric_limits<float>::infinity(),
                        -std::numeric_limits<float>::infinity(),
                        std::numeric_limits<float>::quiet_NaN()}) {
      audio.back() = value;
      reject([&] {
        return vl_fast_dist_render(p, audio.data(), output.data(), 4);
      });
    }
    require(output == outputBefore);
    for (size_t length : {size_t(0), size_t(19), size_t(21)}) {
      reject([&] { return vl_fast_dist_save_state(p, packet.data(), length); });
      reject(
          [&] { return vl_fast_dist_restore_state(p, packet.data(), length); });
    }
    const auto instance = reinterpret_cast<uintptr_t>(p);
    for (size_t size : {sizeof(int32_t), size_t(20), 3 * sizeof(float)}) {
      for (intptr_t delta = -intptr_t(size) + 1; delta < intptr_t(sizeof(*p));
           ++delta) {
        void *buffer = reinterpret_cast<void *>(instance + uintptr_t(delta));
        if (size == sizeof(int32_t))
          reject([&] {
            return vl_fast_dist_parameter(p, 0, 128, 1,
                                          static_cast<int32_t *>(buffer));
          });
        else if (size == 20) {
          reject([&] {
            return vl_fast_dist_save_state(p, static_cast<uint8_t *>(buffer),
                                           20);
          });
          reject([&] {
            return vl_fast_dist_restore_state(
                p, static_cast<const uint8_t *>(buffer), 20);
          });
        } else
          reject([&] {
            return vl_fast_dist_get_coefficients(p,
                                                 static_cast<float *>(buffer));
          });
      }
    }
    for (intptr_t delta = -7; delta < intptr_t(sizeof(*p)); ++delta) {
      float *buffer = reinterpret_cast<float *>(instance + uintptr_t(delta));
      reject([&] { return vl_fast_dist_render(p, buffer, output.data(), 1); });
      reject([&] { return vl_fast_dist_render(p, output.data(), buffer, 1); });
      if (delta >= 0) {
        reject([&] { return vl_fast_dist_render(p, buffer, nullptr, 0); });
        reject([&] { return vl_fast_dist_render(p, nullptr, buffer, 0); });
      }
    }
    audio = {};
    reject([&] {
      return vl_fast_dist_render(p, audio.data(), audio.data() + 1, 2);
    });
    reject([&] {
      return vl_fast_dist_render(p, audio.data() + 1, audio.data(), 2);
    });
    for (int32_t quality : {0, 1}) {
      require(vl_fast_dist_quality(p, quality));
      for (const float *in : {static_cast<const float *>(nullptr),
                              static_cast<const float *>(audio.data())})
        for (float *out : {static_cast<float *>(nullptr), output.data()})
          require(vl_fast_dist_render(p, in, out, 0));
    }
    vl_fast_dist_destroy(p);
    std::cout << "{\"status\":\"passed\",\"source_only_sanitized\":true,"
                 "\"atomic_rejection_cases\":"
              << rejections
              << ",\"nullable_zero_frame_cases\":8,"
                 "\"original_binaries_loaded\":false}\n";
  } catch (const std::exception &e) {
    std::cerr << e.what() << '\n';
    return 1;
  }
}
