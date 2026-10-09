#pragma once
#include <cstddef>
#include <span>

namespace vl::labs::prepared_lookup {
// Independent caller-owned interpolation API for a prepared immutable table.
// No installed plugin ABI, native initializer, or global table object is declared.
// Caller supplies valid live storage and serializes all table/output access.
// Prepared domain: 1..2^24 floats in [0,1], signed zeros allowed; input finite
// [-2,2]. These are defensive new-API limits, not recovered native table bounds
// or contents. Output may not overlap the table; rejection preserves output.
// Numeric environment: IEEE binary32, nearest-even, gradual underflow, masked
// traps, no fast-math or excess precision, contraction disabled outside explicit
// std::fma. Original exception flags, FP modes, NaNs, traps, ABI, lazy paths and
// initialized native storage remain unverified. The accompanying own-source
// numerical test targets macOS arm64; it does not call an installed plugin.
inline constexpr std::size_t maximum_prepared_count = std::size_t{1} << 24;
bool lookup_prepared(float input, std::span<const float> table,
                     float &output) noexcept;
} // namespace vl::labs::prepared_lookup
