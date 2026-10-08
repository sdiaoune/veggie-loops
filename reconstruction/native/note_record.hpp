#pragma once

// Original structural reconstruction from local RTTI evidence only.
// See analysis/NOTE_RTTI.md. Native event-224 note-buffer serialization now
// corroborates this neutral layout; musical field meanings remain incomplete.

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <type_traits>

namespace vlstudio::native {

using NoteRecordBytes = std::array<std::uint8_t, 24>;

namespace detail {

inline std::uint16_t read_u16_le(const std::uint8_t* source) noexcept {
    return static_cast<std::uint16_t>(source[0]) |
           static_cast<std::uint16_t>(static_cast<std::uint16_t>(source[1]) << 8);
}

inline std::uint32_t read_u32_le(const std::uint8_t* source) noexcept {
    return static_cast<std::uint32_t>(source[0]) |
           (static_cast<std::uint32_t>(source[1]) << 8) |
           (static_cast<std::uint32_t>(source[2]) << 16) |
           (static_cast<std::uint32_t>(source[3]) << 24);
}

inline void write_u16_le(std::uint8_t* target, std::uint16_t value) noexcept {
    target[0] = static_cast<std::uint8_t>(value);
    target[1] = static_cast<std::uint8_t>(value >> 8);
}

inline void write_u32_le(std::uint8_t* target, std::uint32_t value) noexcept {
    for (unsigned index = 0; index != 4; ++index) {
        target[index] = static_cast<std::uint8_t>(value >> (8 * index));
    }
}

template <typename To, typename From>
inline To copy_bits(From value) noexcept {
    static_assert(sizeof(To) == sizeof(From));
    static_assert(std::is_trivially_copyable_v<To>);
    static_assert(std::is_trivially_copyable_v<From>);
    To result;
    std::memcpy(&result, &value, sizeof(result));
    return result;
}

}  // namespace detail

struct NoteRecordStorage {
    std::int32_t i32_at_00;
    std::int32_t i32_at_04;
    std::int32_t i32_at_08;
    std::int16_t i16_at_12;
    std::uint16_t u16_at_14;
    std::array<std::uint8_t, 8> opaque_at_16;

    // Decode all 24 bytes explicitly. No type-punning or host-endian memcpy of
    // the whole structure is required, and opaque bytes are never interpreted.
    static NoteRecordStorage from_bytes(const NoteRecordBytes& bytes) noexcept {
        NoteRecordStorage result{};
        result.i32_at_00 = detail::copy_bits<std::int32_t>(detail::read_u32_le(bytes.data()));
        result.i32_at_04 = detail::copy_bits<std::int32_t>(detail::read_u32_le(bytes.data() + 4));
        result.i32_at_08 = detail::copy_bits<std::int32_t>(detail::read_u32_le(bytes.data() + 8));
        result.i16_at_12 = detail::copy_bits<std::int16_t>(detail::read_u16_le(bytes.data() + 12));
        result.u16_at_14 = detail::read_u16_le(bytes.data() + 14);
        std::memcpy(result.opaque_at_16.data(), bytes.data() + 16, result.opaque_at_16.size());
        return result;
    }

    NoteRecordBytes to_bytes() const noexcept {
        NoteRecordBytes result{};
        detail::write_u32_le(result.data(), detail::copy_bits<std::uint32_t>(i32_at_00));
        detail::write_u32_le(result.data() + 4, detail::copy_bits<std::uint32_t>(i32_at_04));
        detail::write_u32_le(result.data() + 8, detail::copy_bits<std::uint32_t>(i32_at_08));
        detail::write_u16_le(result.data() + 12, detail::copy_bits<std::uint16_t>(i16_at_12));
        detail::write_u16_le(result.data() + 14, u16_at_14);
        std::memcpy(result.data() + 16, opaque_at_16.data(), opaque_at_16.size());
        return result;
    }

    // Safe alternate views corroborated by overlapping native descriptors.
    std::uint16_t u16_overlay_at_04() const noexcept {
        return static_cast<std::uint16_t>(detail::copy_bits<std::uint32_t>(i32_at_04));
    }

    std::uint16_t u16_overlay_at_06() const noexcept {
        return static_cast<std::uint16_t>(detail::copy_bits<std::uint32_t>(i32_at_04) >> 16);
    }

    std::int32_t i32_overlay_at_16() const noexcept {
        return detail::copy_bits<std::int32_t>(detail::read_u32_le(opaque_at_16.data()));
    }

    std::int32_t i32_overlay_at_20() const noexcept {
        return detail::copy_bits<std::int32_t>(detail::read_u32_le(opaque_at_16.data() + 4));
    }
};

static_assert(std::numeric_limits<std::int32_t>::min() == (-2147483647 - 1));
static_assert(std::numeric_limits<std::int16_t>::min() == -32768);
static_assert(std::is_standard_layout_v<NoteRecordStorage>);
static_assert(std::is_trivially_copyable_v<NoteRecordStorage>);
static_assert(sizeof(NoteRecordStorage) == 24);
static_assert(offsetof(NoteRecordStorage, i32_at_00) == 0);
static_assert(offsetof(NoteRecordStorage, i32_at_04) == 4);
static_assert(offsetof(NoteRecordStorage, i32_at_08) == 8);
static_assert(offsetof(NoteRecordStorage, i16_at_12) == 12);
static_assert(offsetof(NoteRecordStorage, u16_at_14) == 14);
static_assert(offsetof(NoteRecordStorage, opaque_at_16) == 16);

}  // namespace vlstudio::native
