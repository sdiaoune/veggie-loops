#pragma once
#include <cstddef>
#include <cstdint>
#include <limits>
#include <span>

// Own portable geometry model. No pointer dereference, allocator query or
// original callback is performed here. Caller-supplied proof flags are modeled
// prerequisites, not evidence of actual live quiescence or object construction.
// Every span must already refer to readable caller-owned storage, and the
// output object must not overlap that span. The model does not validate C++
// object lifetimes or hostile pointers. A Ready is internal modeled state;
// the unbuilt live observer intentionally cannot create one.
namespace vl::tyrell::allocation_gate {
constexpr std::size_t maxRanges = 32768;
constexpr std::size_t maxZones = 256;
constexpr std::int32_t maxUnitInfoCount = 213; // Observer budget, not native limit.
struct Range { std::uint64_t base = 0, extent = 0; };
struct Header {
  std::uint64_t payload = 0, rawBase = 0, logicalBytes = 0;
  std::uint32_t definedFlag = 0;
};
struct Block { Range allocation{}; std::uint64_t payload = 0, logicalBytes = 0; };
enum class Error {
  none, incompleteInventory, malformedRange, overlappingRanges, noAllocation,
  headerUnderflow, headerBase, headerAlignment, headerLength, headerFlag,
  propertyLength, routeGeometry, unitCount, unitLength, ownerCoherence,
  missingQuiescence, missingOwnerPrefix
};
inline bool add(std::uint64_t a, std::uint64_t b, std::uint64_t &out) noexcept {
  if (b > std::numeric_limits<std::uint64_t>::max() - a) return false;
  out = a + b; return true;
}
inline bool multiply(std::uint64_t a, std::uint64_t b, std::uint64_t &out) noexcept {
  if (a && b > std::numeric_limits<std::uint64_t>::max() / a) return false;
  out = a * b; return true;
}
inline bool contains(Range r, std::uint64_t address, std::uint64_t bytes) noexcept {
  if (!r.base || !r.extent || r.extent > std::numeric_limits<std::uint64_t>::max() - r.base || address < r.base) return false;
  const auto offset = address - r.base;
  return bytes <= r.extent && offset <= r.extent - bytes;
}
inline Error inventory(std::span<const Range> rows, bool complete) noexcept {
  if (!complete || rows.empty() || rows.size() > maxRanges) return Error::incompleteInventory;
  std::uint64_t end = 0;
  for (const auto r : rows) {
    std::uint64_t next = 0;
    if (!r.base || !r.extent || !add(r.base, r.extent, next)) return Error::malformedRange;
    if (r.base < end) return Error::overlappingRanges;
    end = next;
  }
  return Error::none;
}
inline const Range *find(std::span<const Range> rows, std::uint64_t address, std::uint64_t bytes) noexcept {
  for (const auto &r : rows) if (contains(r, address, bytes)) return &r;
  return nullptr;
}
inline Error block(std::span<const Range> rows, const Header &h, Block &out) noexcept {
  if (h.payload < 24) return Error::headerUnderflow;
  if (h.payload & 15) return Error::headerAlignment;
  const auto *r = find(rows, h.payload - 24, 24);
  if (!r) return Error::noAllocation;
  if (h.rawBase != r->base) return Error::headerBase;
  if (!h.logicalBytes || !contains(*r, h.payload, h.logicalBytes)) return Error::headerLength;
  if (h.definedFlag != 0) return Error::headerFlag;
  out = {*r, h.payload, h.logicalBytes}; return Error::none;
}
struct View {
  std::span<const Range> ranges{};
  bool inventoryComplete = false, quiescenceEstablished = false, ownerPrefixEstablished = false;
  Header property{}, unitInfo{};
  std::uint64_t manager = 0, receiver = 0, receiverOwner = 0, selectedUnit = 0;
  std::uint64_t propertyPointer = 0, propertyPayload = 0, routeBase = 0, routeNext = 0;
  std::int32_t propertyRequested = 0, unitCount = 0, routes = 0, xyControls = 0, xyTargets = 0;
};
struct Geometry { Block property{}, unitInfo{}; std::uint64_t routeBase = 0; };
struct Ready { Geometry storage{}; };
inline Error geometry(const View &v, Geometry &out) noexcept {
  auto e = inventory(v.ranges, v.inventoryComplete); if (e != Error::none) return e;
  if (!v.manager || !v.receiver || v.receiverOwner != v.manager || v.selectedUnit != v.receiver ||
      !find(v.ranges, v.manager, 0x160) || !find(v.ranges, v.receiver, 0xd20)) return Error::ownerCoherence;
  Geometry next{};
  e = block(v.ranges, v.property, next.property); if (e != Error::none) return e;
  e = block(v.ranges, v.unitInfo, next.unitInfo); if (e != Error::none) return e;
  if (v.propertyRequested <= 0 || v.property.logicalBytes != std::uint64_t(v.propertyRequested) ||
      v.propertyPointer != v.propertyPayload || v.propertyPayload != v.property.payload) return Error::propertyLength;
  if (v.routes != 2 || v.xyControls != 0 || v.xyTargets != 0) return Error::routeGeometry;
  std::uint64_t nextAddress = 0;
  const Range logical{v.property.payload, v.property.logicalBytes};
  if (!contains(logical, v.propertyPointer, 0x3e0) || !contains(logical, v.routeBase, 128) ||
      !add(v.routeBase, 128, nextAddress) || nextAddress != v.routeNext) return Error::routeGeometry;
  if (v.unitCount <= 1 || v.unitCount > maxUnitInfoCount) return Error::unitCount;
  std::uint64_t wanted = 0;
  if (!multiply(std::uint64_t(v.unitCount), 40, wanted) || v.unitInfo.logicalBytes != wanted) return Error::unitLength;
  next.routeBase = v.routeBase; out = next; return Error::none;
}
inline Error prepare(const View &v, Ready &out) noexcept {
  Geometry next{}; auto error = geometry(v, next); if (error != Error::none) return error;
  if (!v.quiescenceEstablished) return Error::missingQuiescence;
  if (!v.ownerPrefixEstablished) return Error::missingOwnerPrefix;
  out = {next}; return Error::none;
}
} // namespace vl::tyrell::allocation_gate
