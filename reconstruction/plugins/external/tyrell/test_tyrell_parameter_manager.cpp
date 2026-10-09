// Source-only guard and bounded-controller fixtures. MIT.
#include "tyrell_parameter_manager.h"
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

static void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
static uint32_t bits(float value) { return std::bit_cast<uint32_t>(value); }
int main() {
    try {
        check(std::fegetround() == FE_TONEAREST, "Nearest-even rounding required");
        std::array<float, 92> initial{};
        VLTyrellParameterManager manager{};
        check(vl_tyrell_parameter_manager_prepare(initial.data(), 92, -0.0f, -1, &manager), "Preparation failed");
        VLTyrellParameterWrite result{};
        check(vl_tyrell_parameter_manager_write(&manager, 2, 1, -0.0f, &result), "Signed zero write failed");
        check(!result.notifier_calls && bits(result.value) == 0x80000000u && bits(manager.raw[2]) == 0 &&
              manager.last_identifier == 8 && bits(result.clock) == 0x80000000u, "Equal signed-zero suppression differs");
        check(vl_tyrell_parameter_manager_write(&manager, 1, 1, std::nextafter(0.5f, 0.0f), &result) &&
              result.value == 1.0f, "ADDSS rounds the below-half input to one before floor");
        check(vl_tyrell_parameter_manager_write(&manager, 7, 0, std::nextafter(-0.5f, -1.0f), &result) &&
              result.value == -1.0f, "Strict negative-half floor differs");
        check(vl_tyrell_parameter_manager_write(&manager, 7, 0, -0.5f, &result) && bits(result.value) == 0,
              "Negative-half boundary differs");
        check(vl_tyrell_parameter_manager_clock(&manager, std::numeric_limits<float>::max()), "Finite extreme clock rejected");
        check(vl_tyrell_parameter_manager_write(&manager, 2, 1, 4096.0f, &result) &&
              result.notifier_calls && bits(result.clock) == bits(std::numeric_limits<float>::max()), "Clock forwarding changed");
        check(manager.raw[2] == 4096 && result.previous == 0 && result.getter_calls == 1 &&
              result.getter_flag == 0 && result.notifier_flag == 0, "Prepared backend commit differs");
        check(vl_tyrell_parameter_decide(0, 3, 1, 0, 2, &result) && result.ignored && !result.getter_calls &&
              !result.notifier_calls, "Prepared meter early return differs");
        check(vl_tyrell_parameter_decide(0, 5, -0.75f, 0, 2, &result) && result.value == -1,
              "Prepared type-five floor differs");
        uint64_t rejectionCases = 0;
        const auto rejectWrite = [&](int32_t index, int32_t flag, float value) {
            const auto before = manager;
            std::memset(&result, 0xa5, sizeof result); const auto beforeResult = result;
            check(!vl_tyrell_parameter_manager_write(&manager, index, flag, value, &result) &&
                  std::memcmp(&manager, &before, sizeof manager) == 0 &&
                  std::memcmp(&result, &beforeResult, sizeof result) == 0, "Rejected write mutated bytes");
            ++rejectionCases;
        };
        for (auto index : {-1, 92, 10000, INT32_MIN, INT32_MAX}) rejectWrite(index, 1, 1);
        for (auto index : {-1, 1, 6, 11, 213, INT32_MIN, INT32_MAX}) rejectWrite(index, 0, 1);
        for (auto flag : {-1, 2, 255, 256, INT32_MIN, INT32_MAX}) rejectWrite(0, flag, 1);
        const std::array<float, 6> invalidValues{INFINITY, -INFINITY, NAN, 4096.5f, -4096.5f,
                                                std::numeric_limits<float>::max()};
        for (float value : invalidValues) rejectWrite(0, 1, value);
        for (float value : invalidValues) {
            const auto before = manager;
            manager.raw[91] = value;
            rejectWrite(0, 1, 1); manager = before;
        }
        for (float clock : {INFINITY, -INFINITY, NAN}) {
            const auto before = manager;
            check(!vl_tyrell_parameter_manager_clock(&manager, clock) &&
                  !std::memcmp(&manager, &before, sizeof manager), "Rejected clock mutated bytes");
            ++rejectionCases;
            manager.clock = clock; rejectWrite(0, 1, 1); manager = before;
        }
        for (int32_t last : {1, 6, -2, 213, INT32_MAX}) {
            const auto before = manager; manager.last_identifier = last;
            rejectWrite(0, 1, 1); manager = before;
        }
        const auto rejectionPreparation = [&](const float* values, uint32_t count, float clock, int32_t last) {
            const auto before = manager;
            check(!vl_tyrell_parameter_manager_prepare(values, count, clock, last, &manager) &&
                  !std::memcmp(&manager, &before, sizeof manager), "Rejected preparation mutated bytes");
            ++rejectionCases;
        };
        rejectionPreparation(nullptr, 92, 0, -1);
        for (uint32_t count : {0u, 91u, 93u, UINT32_MAX}) rejectionPreparation(initial.data(), count, 0, -1);
        rejectionPreparation(initial.data(), 92, INFINITY, -1);
        rejectionPreparation(initial.data(), 92, 0, 1);
        rejectionPreparation(manager.raw, 92, 0, -1);
        initial[91] = NAN; rejectionPreparation(initial.data(), 92, 0, -1); initial[91] = 0;

        // Every aligned partial overlap between an output record and live state,
        // including ranges straddling either edge, is rejected before access.
        struct Storage { std::array<unsigned char, 64> lead; VLTyrellParameterManager state;
                         std::array<unsigned char, 64> tail; } storage{};
        storage.state = manager;
        auto* start = reinterpret_cast<unsigned char*>(&storage.state);
        const auto bytesBefore = storage;
        for (int offset = -44; offset < int(sizeof manager); offset += 4) {
            auto* output = reinterpret_cast<VLTyrellParameterWrite*>(start + offset);
            check(!vl_tyrell_parameter_manager_write(&storage.state, 0, 1, 1, output) &&
                  !std::memcmp(&storage, &bytesBefore, sizeof storage), "Partial state/result overlap accepted");
            ++rejectionCases;
        }
        for (int offset = 0; offset < int(sizeof manager); offset += 4) {
            auto* output = reinterpret_cast<float*>(start + offset);
            check(!vl_tyrell_parameter_manager_get(&storage.state, 0, 1, output) &&
                  !std::memcmp(&storage, &bytesBefore, sizeof storage), "State/getter overlap accepted");
            ++rejectionCases;
        }
        struct PrepareStorage { std::array<unsigned char, 384> lead;
                                VLTyrellParameterManager state;
                                std::array<unsigned char, 384> tail; } prepareStorage{};
        prepareStorage.state = manager;
        const auto prepareBefore = prepareStorage;
        auto* prepareStart = reinterpret_cast<unsigned char*>(&prepareStorage.state);
        for (int offset = -364; offset < int(sizeof manager); offset += 4) {
            auto* values = reinterpret_cast<float*>(prepareStart + offset);
            check(!vl_tyrell_parameter_manager_prepare(values, 92, 0, -1, &prepareStorage.state) &&
                  !std::memcmp(&prepareStorage, &prepareBefore, sizeof prepareStorage),
                  "Partial preparation input/state overlap accepted");
            ++rejectionCases;
        }
        const auto before = manager;
        check(!vl_tyrell_parameter_manager_write(nullptr, 0, 1, 1, &result) &&
              !vl_tyrell_parameter_manager_write(&manager, 0, 1, 1, nullptr) &&
              !vl_tyrell_parameter_manager_get(nullptr, 0, 1, &initial[0]) &&
              !vl_tyrell_parameter_manager_get(&manager, 0, 1, nullptr) &&
              !vl_tyrell_parameter_manager_clock(nullptr, 0) &&
              !std::memcmp(&manager, &before, sizeof manager), "Null arguments accepted");
        rejectionCases += 5;
        for (auto type : {256u, UINT32_MAX}) {
            std::memset(&result, 0x5a, sizeof result); const auto prior = result;
            check(!vl_tyrell_parameter_decide(0, type, 0, 0, 0, &result) &&
                  !std::memcmp(&result, &prior, sizeof result), "Invalid descriptor type changed result");
            ++rejectionCases;
        }
        const auto rejectDecision = [&](int32_t id, uint32_t type, float input, float previous, float clock) {
            std::memset(&result, 0x5a, sizeof result); const auto prior = result;
            check(!vl_tyrell_parameter_decide(id, type, input, previous, clock, &result) &&
                  !std::memcmp(&result, &prior, sizeof result), "Rejected scalar decision mutated output");
            ++rejectionCases;
        };
        for (int32_t id : {-1, 213, INT32_MIN, INT32_MAX}) rejectDecision(id, 1, 0, 0, 0);
        for (float value : invalidValues) {
            rejectDecision(0, 1, value, 0, 0);
            rejectDecision(0, 1, 0, value, 0);
        }
        for (float clock : {INFINITY, -INFINITY, NAN}) rejectDecision(0, 1, 0, 0, clock);
        for (int32_t index : {-1, 92, INT32_MIN, INT32_MAX}) {
            VLTyrellParameterDescriptor descriptor{}; std::memset(&descriptor, 0x5a, sizeof descriptor);
            const auto prior = descriptor;
            check(!vl_tyrell_parameter_descriptor(index, 1, &descriptor) &&
                  !std::memcmp(&descriptor, &prior, sizeof descriptor), "Rejected descriptor changed output");
            ++rejectionCases;
            float read = -1234.5f;
            const auto priorState = manager;
            check(!vl_tyrell_parameter_manager_get(&manager, index, 1, &read) && read == -1234.5f &&
                  !std::memcmp(&manager, &priorState, sizeof manager), "Rejected getter changed state/output");
            ++rejectionCases;
        }
        for (float value : invalidValues) {
            const auto beforeState = manager; manager.raw[91] = value;
            const auto corrupted = manager; float read = -1234.5f;
            check(!vl_tyrell_parameter_manager_get(&manager, 0, 1, &read) && read == -1234.5f &&
                  !std::memcmp(&manager, &corrupted, sizeof manager), "Malformed state getter mutated bytes");
            manager = beforeState; ++rejectionCases;
        }
        check(!vl_tyrell_parameter_decide(0, 1, 0, 0, 0, nullptr) &&
              !vl_tyrell_parameter_descriptor(0, 1, nullptr) &&
              !vl_tyrell_parameter_manager_prepare(initial.data(), 92, 0, -1, nullptr), "Null decision outputs accepted");
        rejectionCases += 3;
        std::cout << "{\"source_contract\":true,\"atomic_rejections\":" << rejectionCases << "}\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
