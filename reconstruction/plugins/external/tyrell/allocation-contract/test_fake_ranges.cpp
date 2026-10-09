#include "allocation_gate.hpp"
#include <array>
#include <cstring>
#include <iostream>
#include <stdexcept>
using namespace vl::tyrell::allocation_gate;
static void require(bool ok, const char *text) { if (!ok) throw std::runtime_error(text); }
int main() {
  try {
    const std::array<Range, 4> ranges{{{0x1000, 0x2000}, {0x4000, 0x400}, {0x8000, 0x1000}, {0x9000, 0xd20}}};
    View base{}; base.ranges = ranges; base.inventoryComplete = true;
    base.quiescenceEstablished = base.ownerPrefixEstablished = true; // FAKE proofs only.
    base.manager = base.receiverOwner = 0x8000; base.receiver = base.selectedUnit = 0x9000;
    base.property = {0x1040, 0x1000, 0x1000, 0}; base.unitInfo = {0x4040, 0x4000, 120, 0};
    base.propertyPointer = base.propertyPayload = 0x1040; base.propertyRequested = 0x1000;
    base.routeBase = 0x1800; base.routeNext = 0x1880; base.routes = 2; base.unitCount = 3;
    Ready ready{}; require(prepare(base, ready) == Error::none, "Fake valid geometry rejected");
    unsigned rejected = 0;
    auto reject = [&](View changed, Error expected) {
      Ready out{{{{0x1234, 99}, 0x4567, 13}, {{0x8765, 22}, 0x1111, 7}, 0xabcdef}};
      std::array<unsigned char, sizeof(Ready)> before{};
      std::memcpy(before.data(), &out, sizeof out);
      require(prepare(changed, out) == expected, "Fake malformed case not rejected at selected gate");
      require(!std::memcmp(&out, before.data(), sizeof out), "Rejected model wrote readiness output"); ++rejected;
    };
    View v = base; v.inventoryComplete = false; reject(v, Error::incompleteInventory);
    v = base; v.quiescenceEstablished = false; reject(v, Error::missingQuiescence);
    v = base; v.ownerPrefixEstablished = false; reject(v, Error::missingOwnerPrefix);
    v = base; v.selectedUnit++; reject(v, Error::ownerCoherence);
    v = base; v.property.payload = 16; reject(v, Error::headerUnderflow);
    v = base; v.property.payload++; reject(v, Error::headerAlignment);
    v = base; v.property.rawBase = v.property.payload; reject(v, Error::headerBase);
    v = base; v.property.logicalBytes = 0; reject(v, Error::headerLength);
    v = base; v.property.logicalBytes = 0x4000; reject(v, Error::headerLength);
    v = base; v.property.definedFlag = 1; reject(v, Error::headerFlag);
    v = base; v.propertyRequested--; reject(v, Error::propertyLength);
    v = base; v.propertyPointer++; reject(v, Error::propertyLength);
    v = base; v.routeNext--; reject(v, Error::routeGeometry);
    v = base; v.routeBase = 0x2000; v.routeNext = 0x2080; reject(v, Error::routeGeometry);
    v = base; v.xyControls = 1; reject(v, Error::routeGeometry);
    v = base; v.unitCount = 1; reject(v, Error::unitCount);
    v = base; v.unitCount = 214; reject(v, Error::unitCount);
    v = base; v.unitInfo.logicalBytes = 121; reject(v, Error::unitLength);
    const std::array<Range, 2> overlap{{{0x1000, 0x2000}, {0x2000, 0x400}}};
    v = base; v.ranges = overlap; reject(v, Error::overlappingRanges);
    const std::array<Range, 2> wrap{{{0x1000, 0x2000}, {UINT64_MAX - 8, 16}}};
    v = base; v.ranges = wrap; reject(v, Error::malformedRange);
    std::uint64_t result = 0x1234;
    require(!add(UINT64_MAX, 1, result) && result == 0x1234, "Add overflow changed output");
    require(!multiply(UINT64_MAX, 2, result) && result == 0x1234, "Multiply overflow changed output");
    require(contains({0x1000, 16}, 0x1000, 16) && !contains({0x1000, 16}, 0x1001, 16), "Range endpoints differ");
    std::cout << "{\"status\":\"passed_fake_range_model_only\",\"rejections\":" << rejected
              << ",\"live_allocator_or_original_called\":false,\"live_bounds_certified\":false}\n";
    return 0;
  } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
