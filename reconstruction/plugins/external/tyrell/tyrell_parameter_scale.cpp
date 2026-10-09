// Independently written bounded TyrellN6 parameter conversion. MIT.
#include "tyrell_parameter_scale.h"
#include <cmath>

namespace {
constexpr VLTyrellParameterRange ranges[] = {
    {0, 0, 0.0f, 200.0f},
    {1, 7, 0.0f, 16.0f},
    {2, 8, -100.0f, 100.0f},
    {3, 9, 0.0f, 16.0f},
    {4, 10, -100.0f, 100.0f},
    {5, 12, 0.0f, 16.0f},
    {6, 13, -100.0f, 100.0f},
    {7, 14, 0.0f, 16.0f},
    {8, 15, -100.0f, 100.0f},
    {9, 59, 1.0f, 8.0f},
    {10, 60, 0.0f, 3.0f},
    {11, 61, 0.0f, 1.0f},
    {12, 62, 0.0f, 100.0f},
    {13, 63, -100.0f, 100.0f},
    {14, 64, 0.0f, 100.0f},
    {15, 65, 0.0f, 24.0f},
    {16, 66, 0.0f, 24.0f},
    {17, 71, -24.0f, 24.0f},
    {18, 87, 0.0f, 100.0f},
    {19, 88, 0.0f, 100.0f},
    {20, 89, 0.0f, 100.0f},
    {21, 90, -100.0f, 100.0f},
    {22, 91, 0.0f, 100.0f},
    {23, 92, 0.0f, 100.0f},
    {24, 94, -100.0f, 100.0f},
    {25, 104, 0.0f, 3.0f},
    {26, 105, 0.0f, 100.0f},
    {27, 106, 0.0f, 100.0f},
    {28, 107, 0.0f, 100.0f},
    {29, 108, -100.0f, 100.0f},
    {30, 109, 0.0f, 100.0f},
    {31, 110, 0.0f, 100.0f},
    {32, 112, -100.0f, 100.0f},
    {33, 122, 0.0f, 4.0f},
    {34, 123, -3.0f, 23.0f},
    {35, 129, 0.0f, 100.0f},
    {36, 135, -3.0f, 23.0f},
    {37, 141, 0.0f, 100.0f},
    {38, 147, 1.0f, 4.0f},
    {39, 148, 0.0f, 16.0f},
    {40, 149, -24.0f, 24.0f},
    {41, 150, 1.0f, 2.0f},
    {42, 151, 0.0f, 24.0f},
    {43, 152, -50.0f, 50.0f},
    {44, 153, 0.0f, 16.0f},
    {45, 154, -24.0f, 24.0f},
    {46, 155, 0.0f, 50.0f},
    {47, 156, 0.0f, 16.0f},
    {48, 157, -50.0f, 50.0f},
    {49, 158, 0.0f, 100.0f},
    {50, 160, 0.0f, 100.0f},
    {51, 163, 0.0f, 5.0f},
    {52, 164, 0.0f, 2.0f},
    {53, 166, 1.0f, 3.0f},
    {54, 167, -100.0f, 25.0f},
    {55, 168, -100.0f, 25.0f},
    {56, 169, -100.0f, 25.0f},
    {57, 170, -100.0f, 25.0f},
    {58, 171, -100.0f, 25.0f},
    {59, 172, -100.0f, 25.0f},
    {60, 173, 0.0f, 1.0f},
    {61, 174, 0.0f, 2.0f},
    {62, 175, 30.0f, 150.0f},
    {63, 176, 0.0f, 16.0f},
    {64, 177, -120.0f, 120.0f},
    {65, 178, 0.0f, 16.0f},
    {66, 179, -120.0f, 120.0f},
    {67, 180, 0.0f, 100.0f},
    {68, 181, 0.0f, 100.0f},
    {69, 183, 0.0f, 100.0f},
    {70, 185, 0.0f, 0.0f},
    {71, 186, 0.0f, 2.0f},
    {72, 187, 0.0f, 100.0f},
    {73, 188, 0.0f, 16.0f},
    {74, 209, 0.0f, 2.0f},
    {75, 210, 0.0f, 100.0f},
    {76, 211, 0.0f, 100.0f},
    {77, 212, 0.0f, 100.0f},
    {78, 124, 0.0f, 3.0f},
    {79, 125, 0.0f, 7.0f},
    {80, 126, 0.0f, 100.0f},
    {81, 128, 0.0f, 1.0f},
    {82, 131, 0.0f, 100.0f},
    {83, 132, -5.0f, 5.0f},
    {84, 134, -5.0f, 5.0f},
    {85, 136, 0.0f, 3.0f},
    {86, 137, 0.0f, 7.0f},
    {87, 138, 0.0f, 100.0f},
    {88, 140, 0.0f, 1.0f},
    {89, 143, 0.0f, 100.0f},
    {90, 144, -5.0f, 5.0f},
    {91, 146, -5.0f, 5.0f},
};
bool supported(float minimum, float maximum) noexcept {
    return std::isfinite(minimum) && std::isfinite(maximum) &&
           std::fabs(minimum) <= 512.0f && std::fabs(maximum) <= 512.0f &&
           minimum <= maximum;
}
}
extern "C" const VLTyrellParameterRange* vl_tyrell_parameter_range(int32_t index) {
    if (index < 0) return nullptr;
    if (index < 10000) {
        return index < 92 ? &ranges[index] : nullptr;
    }
    const int32_t identifier = index - 10000;
    for (const auto& range : ranges) if (range.identifier == identifier) return &range;
    return nullptr;
}
extern "C" int vl_tyrell_parameter_denormalize(float minimum, float maximum,
                                                float normalized, float* output) {
    if (!output || !supported(minimum, maximum) || !std::isfinite(normalized) ||
        normalized < -2.0f || normalized > 2.0f) return 0;
    const float extent = maximum - minimum;
    const float scaled = extent * normalized;
    const float result = scaled + minimum;
    if (!std::isfinite(result)) return 0;
    *output = result;
    return 1;
}
extern "C" int vl_tyrell_parameter_normalize(float minimum, float maximum,
                                              float raw, float* output) {
    if (!output || !supported(minimum, maximum) || !std::isfinite(raw) ||
        std::fabs(raw) > 4096.0f) return 0;
    const float extent = maximum - minimum;
    const float shifted = raw - minimum;
    const float result = extent == 0.0f ? minimum : shifted / extent;
    if (!std::isfinite(result)) return 0;
    *output = result;
    return 1;
}
