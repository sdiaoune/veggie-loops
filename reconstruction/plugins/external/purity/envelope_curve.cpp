#include "envelope_curve.h"
#include <array>
#include <cmath>
#include <algorithm>

extern "C" int vl_purity_envelope_curve(double amount, float* output) {
    if (!output || !std::isfinite(amount) || amount < -16 || amount > 16) return 0;
    std::array<float, 259> curve{};
    const double exponent = std::exp(amount * 0.5);
    // Two leading zeros and three trailing ones provide the interpolation
    // boundary padding. No target table or preset bytes are embedded.
    for (int point = 1; point <= 254; ++point)
        curve[point + 1] = static_cast<float>(std::pow(double(point) / 256, exponent));
    std::fill(curve.begin() + 256, curve.end(), 1.0f);
    std::copy(curve.begin(), curve.end(), output);
    return 1;
}
