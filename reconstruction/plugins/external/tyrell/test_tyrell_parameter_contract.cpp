// Independent source-only bounded-contract checks. MIT.
#include "tyrell_parameter_scale.h"
#include <bit>
#include <cstdint>
#include <iostream>
#include <limits>
#include <stdexcept>

static void require(bool condition) {
    if (!condition) throw std::runtime_error("Parameter contract failed");
}
int main() {
    unsigned rejections = 0;
    for (int index : {-1, -2147483647, 92, 9999, 10213, 2147483647}) {
        require(!vl_tyrell_parameter_range(index)); ++rejections;
    }
    const float nan = std::numeric_limits<float>::quiet_NaN();
    const float inf = std::numeric_limits<float>::infinity();
    struct Case { float minimum, maximum, value; };
    for (const Case c : {Case{nan, 1, 0}, {0, nan, 0}, {-inf, 1, 0}, {0, inf, 0},
                         {-513, 1, 0}, {0, 513, 0}, {1, 0, 0}, {0, 1, nan}, {0, 1, inf},
                         {0, 1, -2.001f}, {0, 1, 2.001f}}) {
        float output = -123.25f;
        require(!vl_tyrell_parameter_denormalize(c.minimum, c.maximum, c.value, &output));
        require(std::bit_cast<uint32_t>(output) == std::bit_cast<uint32_t>(-123.25f)); ++rejections;
    }
    for (const Case c : {Case{nan, 1, 0}, {0, nan, 0}, {-inf, 1, 0}, {0, inf, 0},
                         {-513, 1, 0}, {0, 513, 0}, {1, 0, 0}, {0, 1, nan}, {0, 1, inf},
                         {0, 1, -4097}, {0, 1, 4097},
                         {0, std::numeric_limits<float>::denorm_min(), 4096}}) {
        float output = -123.25f;
        require(!vl_tyrell_parameter_normalize(c.minimum, c.maximum, c.value, &output));
        require(std::bit_cast<uint32_t>(output) == std::bit_cast<uint32_t>(-123.25f)); ++rejections;
    }
    require(!vl_tyrell_parameter_normalize(0, 1, 0, nullptr)); ++rejections;
    require(!vl_tyrell_parameter_denormalize(0, 1, 0, nullptr)); ++rejections;
    float output = 0;
    require(vl_tyrell_parameter_denormalize(-512, 512, -2, &output) && output == -2560);
    require(vl_tyrell_parameter_denormalize(-512, 512, 2, &output) && output == 1536);
    require(vl_tyrell_parameter_normalize(7, 7, 4096, &output) && output == 7);
    std::cout << "{\"status\":\"passed\",\"source_only_contract\":true,\"atomic_rejections\":"
              << rejections << ",\"sanitized_source\":true,\"full_plugin_equivalence\":false}\n";
}
