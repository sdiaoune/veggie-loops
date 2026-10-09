// Original implementation from measured parameter facts and scalar behavior.
#include "tyrell_parameter_manager.h"
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace {
constexpr uint8_t types[92] = {
    1,0,1,0,1,0,1,0,1,0,0,0,1,1,1,0,0,0,1,1,1,1,1,1,1,0,1,1,1,1,1,1,
    1,0,0,1,0,1,1,0,1,1,1,1,0,1,1,0,1,1,1,0,0,1,1,1,1,1,1,1,0,0,1,0,
    1,0,1,1,1,1,0,0,1,0,0,1,1,1,0,0,1,0,1,1,1,0,0,1,0,1,1,1
};
static_assert(sizeof(VLTyrellParameterManager) == 376);
static_assert(sizeof(VLTyrellParameterWrite) == 48);
static_assert(sizeof(VLTyrellParameterDescriptor) == 20);

bool overlap(const void* a, size_t na, const void* b, size_t nb) {
    const auto pa = reinterpret_cast<uintptr_t>(a), pb = reinterpret_cast<uintptr_t>(b);
    return pa <= pb ? pb - pa < na : pa - pb < nb;
}
bool rawValid(float v) { return std::isfinite(v) && std::fabs(v) <= 4096.0f; }
const VLTyrellParameterRange* range(int32_t index, int32_t flag) {
    if (flag == 1) return index >= 0 && index < 92 ? vl_tyrell_parameter_range(index) : nullptr;
    if (flag != 0 || index < 0 || index > 212) return nullptr;
    return vl_tyrell_parameter_range(10000 + index);
}
bool stateValid(const VLTyrellParameterManager& state) {
    if (!std::isfinite(state.clock) ||
        (state.last_identifier != -1 && !range(state.last_identifier, 0))) return false;
    for (float v : state.raw) if (!rawValid(v)) return false;
    return true;
}
}

extern "C" int vl_tyrell_parameter_descriptor(int32_t index, int32_t flag,
                                               VLTyrellParameterDescriptor* output) {
    const auto* r = range(index, flag);
    if (!r || !output) return 0;
    const VLTyrellParameterDescriptor result{*r, types[r->public_index]};
    std::memcpy(output, &result, sizeof result);
    return 1;
}
extern "C" int vl_tyrell_parameter_decide(int32_t identifier, uint32_t type, float input,
                                          float previous, float clock,
                                          VLTyrellParameterWrite* output) {
    if (!output || identifier < 0 || identifier > 212 || type > 255 ||
        !rawValid(input) || !rawValid(previous) || !std::isfinite(clock)) return 0;
    VLTyrellParameterWrite result{};
    result.identifier = identifier;
    result.descriptor_type = type;
    result.input = input;
    result.clock = clock;
    if (type == 3) {
        result.ignored = 1;
    } else {
        float value = input;
        if (type == 0 || type == 5) {
            const float shifted = input + 0.5f;
            value = std::floor(shifted);
        }
        result.getter_calls = 1;
        result.getter_fallback = result.value = value;
        result.previous = previous;
        result.notifier_calls = previous == value ? 0 : 1;
        // getter_flag and notifier_flag are both zero by initialization.
    }
    std::memcpy(output, &result, sizeof result);
    return 1;
}
extern "C" int vl_tyrell_parameter_manager_prepare(const float* raw, uint32_t count,
                                                    float clock, int32_t last_identifier,
                                                    VLTyrellParameterManager* output) {
    if (!raw || count != 92 || !output ||
        overlap(raw, 92 * sizeof(float), output, sizeof *output)) return 0;
    VLTyrellParameterManager prepared{};
    std::memcpy(prepared.raw, raw, sizeof prepared.raw);
    prepared.clock = clock;
    prepared.last_identifier = last_identifier;
    if (!stateValid(prepared)) return 0;
    std::memcpy(output, &prepared, sizeof prepared);
    return 1;
}
extern "C" int vl_tyrell_parameter_manager_clock(VLTyrellParameterManager* manager, float clock) {
    if (!manager || !std::isfinite(clock) || !stateValid(*manager)) return 0;
    manager->clock = clock;
    return 1;
}
extern "C" int vl_tyrell_parameter_manager_get(const VLTyrellParameterManager* manager,
                                                int32_t index, int32_t flag, float* output) {
    const auto* r = range(index, flag);
    if (!manager || !r || !output || overlap(manager, sizeof *manager, output, sizeof *output) ||
        !stateValid(*manager)) return 0;
    const float value = manager->raw[r->public_index];
    std::memcpy(output, &value, sizeof value);
    return 1;
}
extern "C" int vl_tyrell_parameter_manager_write(VLTyrellParameterManager* manager,
                                                  int32_t index, int32_t flag, float input,
                                                  VLTyrellParameterWrite* output) {
    const auto* r = range(index, flag);
    if (!manager || !r || !output || overlap(manager, sizeof *manager, output, sizeof *output) ||
        !stateValid(*manager)) return 0;
    VLTyrellParameterWrite result{};
    if (!vl_tyrell_parameter_decide(r->identifier, types[r->public_index], input,
                                    manager->raw[r->public_index], manager->clock, &result)) return 0;
    manager->last_identifier = r->identifier;
    if (result.notifier_calls) manager->raw[r->public_index] = result.value;
    std::memcpy(output, &result, sizeof result);
    return 1;
}
