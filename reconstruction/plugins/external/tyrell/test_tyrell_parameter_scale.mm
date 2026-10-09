// Original differential fixture. No commercial SDK or implementation included.
#if !defined(__APPLE__) || !defined(__x86_64__)
#error The pinned TyrellN6 fixture requires macOS x86_64 (Rosetta is supported).
#endif
#define main vl_reference_probe_unused_main
#include "../../common/vst2_probe.mm"
#undef main
#include "tyrell_parameter_scale.h"
#include <CommonCrypto/CommonDigest.h>
#include <bit>
#include <cfenv>
#include <dlfcn.h>
#include <limits>

template<class T> static T field(const void* pointer, size_t offset) {
    T value;
    std::memcpy(&value, static_cast<const char*>(pointer) + offset, sizeof value);
    return value;
}
template<class T> static void store(void* pointer, size_t offset, T value) {
    std::memcpy(static_cast<char*>(pointer) + offset, &value, sizeof value);
}
static uint32_t bits(float value) { return std::bit_cast<uint32_t>(value); }
static std::string sha256(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    require(bool(file), "Target binary not found");
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    std::array<char, 65536> bytes{};
    while (file.read(bytes.data(), bytes.size()) || file.gcount())
        CC_SHA256_Update(&context, bytes.data(), CC_LONG(file.gcount()));
    require(file.eof(), "Target binary read failed");
    std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest{};
    CC_SHA256_Final(digest.data(), &context);
    std::string result;
    for (auto byte : digest) {
        result += "0123456789abcdef"[byte >> 4];
        result += "0123456789abcdef"[byte & 15];
    }
    return result;
}

// Only the actual outer callbacks execute while this synthetic manager vtable
// is attached. Its three slots supply controlled descriptor/raw data and record
// forwarding arguments. They never call other native manager methods. Both
// original instance pointers are restored before any lifetime/real-manager call.
struct ManagerProbe {
    void* manager;
    void* object;
    void** originalVtable;
    void* originalUI;
    std::array<void*, 75> slots{};
    std::array<unsigned char, 84> descriptor{};
    int32_t expectedIndex = 0, expectedLookup = 0, expectedFlag = 1;
    int32_t capturedIdentifier = -1, capturedFlag = -1;
    float suppliedRaw = 0, capturedRaw = 0;
    unsigned lookupCalls = 0, setCalls = 0, getCalls = 0;
    static thread_local ManagerProbe* current;
    static void* lookup(void* self, int32_t index, int32_t flag) {
        auto& p = *current;
        require(self == p.manager && index == p.expectedLookup && flag == p.expectedFlag,
                "Actual callback descriptor forwarding differs");
        ++p.lookupCalls;
        return p.descriptor.data();
    }
    static void set(void* self, int32_t identifier, float raw, int32_t flag) {
        auto& p = *current;
        require(self == p.manager, "Actual callback setter receiver differs");
        p.capturedIdentifier = identifier;
        p.capturedRaw = raw;
        p.capturedFlag = flag;
        ++p.setCalls;
    }
    static float get(void* self, int32_t index, float fallback, int32_t flag) {
        auto& p = *current;
        require(self == p.manager && index == p.expectedIndex && flag == 1 && bits(fallback) == 0,
                "Actual callback getter forwarding differs");
        ++p.getCalls;
        return p.suppliedRaw;
    }
    ManagerProbe(void* nativeManager, void* nativeObject)
        : manager(nativeManager), object(nativeObject),
          originalVtable(field<void**>(manager, 0)), originalUI(field<void*>(object, 0x10)) {
        require(!current, "Nested manager probe");
        slots[0x250 / 8] = reinterpret_cast<void*>(&lookup);
        slots[0x1b8 / 8] = reinterpret_cast<void*>(&set);
        slots[0x1c8 / 8] = reinterpret_cast<void*>(&get);
        current = this;
        store(manager, 0, slots.data());
        store<void*>(object, 0x10, nullptr); // GUI branch deliberately excluded.
    }
    ~ManagerProbe() {
        store(manager, 0, originalVtable);
        store(object, 0x10, originalUI);
        current = nullptr;
    }
    void configure(int32_t index, int32_t identifier, float minimum, float maximum, float raw) {
        expectedIndex = index;
        expectedLookup = index >= 10000 ? index - 10000 : index;
        expectedFlag = index >= 10000 ? 0 : 1;
        suppliedRaw = raw;
        store(descriptor.data(), 0, identifier);
        store(descriptor.data(), 0x4c, minimum);
        store(descriptor.data(), 0x50, maximum);
        lookupCalls = setCalls = getCalls = 0;
    }
};
thread_local ManagerProbe* ManagerProbe::current = nullptr;

int main(int argc, char** argv) {
    std::cout << std::unitbuf;
    @autoreleasepool {
        try {
            require(argc == 2, "Expected installed TyrellN6 VST bundle");
            require(std::fegetround() == FE_TONEAREST, "Nearest-even rounding required");
            const std::string bundlePath = argv[1];
            require(sha256(bundlePath + "/Contents/MacOS/TyrellN6") ==
                    "a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54",
                    "Installed TyrellN6 identity differs; refusing native offsets");
            transport.sampleRate = 48000; transport.tempo = 120;
            Bundle bundle;
            auto url = CFURLCreateFromFileSystemRepresentation(nullptr,
                reinterpret_cast<const UInt8*>(argv[1]), std::strlen(argv[1]), true);
            require(url, "Bundle URL failed");
            bundle.value = CFBundleCreate(nullptr, url); CFRelease(url);
            require(bundle.value && CFBundleLoadExecutable(bundle.value), "Bundle load failed");
            auto entry = reinterpret_cast<Effect* (*)(Dispatch)>(
                CFBundleGetFunctionPointerForName(bundle.value, CFSTR("VSTPluginMain")));
            require(entry, "Factory entry missing");
            Dl_info info{};
            require(dladdr(reinterpret_cast<void*>(entry), &info) && info.dli_fbase,
                    "Native image base missing");
            const auto base = reinterpret_cast<uintptr_t>(info.dli_fbase);
            require(reinterpret_cast<uintptr_t>(entry) - base == 0x3ddb0,
                    "Factory entry does not match pinned x86_64 slice");
            Instance instance;
            instance.value = entry(host);
            auto* effect = instance.value;
            require(effect && effect->magic == 0x56737450 && effect->dispatcher,
                    "Actual native factory failed");
            effect->dispatcher(effect, 0, 0, 0, nullptr, 0); instance.opened = true;
            require(effect->parameters == 92 && effect->object, "Unexpected public parameter layout");
            require(reinterpret_cast<uintptr_t>(effect->getParameter) - base == 0x3c300 &&
                    reinterpret_cast<uintptr_t>(effect->setParameter) - base == 0x3c320,
                    "Actual parameter callbacks differ");
            void* manager = field<void*>(effect->object, 0x138);
            require(manager, "Native parameter manager missing");
            auto** original = field<void**>(manager, 0);
            auto lookup = reinterpret_cast<void* (*)(void*, int32_t, int32_t)>(original[0x250 / 8]);
            auto getRaw = reinterpret_cast<float (*)(void*, int32_t, float, int32_t)>(original[0x1c8 / 8]);
            uint64_t descriptors = 0, actualRoundTrips = 0, callbackSetCases = 0, callbackGetCases = 0;
            for (int32_t index = 0; index < 92; ++index) {
                const auto* range = vl_tyrell_parameter_range(index);
                void* descriptor = lookup(manager, index, 1);
                require(range && descriptor && range->public_index == index &&
                        range->identifier == field<int32_t>(descriptor, 0) &&
                        bits(range->minimum) == bits(field<float>(descriptor, 0x4c)) &&
                        bits(range->maximum) == bits(field<float>(descriptor, 0x50)),
                        "Rebuilt range differs from actual manager descriptor");
                require(vl_tyrell_parameter_range(10000 + range->identifier) == range &&
                        lookup(manager, range->identifier, 0) == descriptor,
                        "Known public/internal descriptor mapping differs");
                ++descriptors;
                for (float normalized : {0.0f, std::nextafter(0.0f, 1.0f), 0.01f, 0.125f,
                                         0.25f, 0.5f, 0.75f, 0.9f, std::nextafter(1.0f, 0.0f), 1.0f}) {
                    effect->setParameter(effect, index, normalized);
                    const float raw = getRaw(manager, index, 0.0f, 1);
                    float rebuilt = -999.0f;
                    require(vl_tyrell_parameter_normalize(range->minimum, range->maximum, raw, &rebuilt) &&
                            bits(rebuilt) == bits(effect->getParameter(effect, index)),
                            "Actual unmodified-manager getter differs");
                    ++actualRoundTrips;
                }
                {
                    ManagerProbe probe(manager, effect->object);
                    for (int mode = 0; mode < 2; ++mode) {
                        const int32_t nativeIndex = mode ? 10000 + range->identifier : index;
                        for (int step = -256; step <= 256; ++step) {
                            const float normalized = float(step) / 128.0f;
                            float raw = 0, rebuilt = 0;
                            require(vl_tyrell_parameter_denormalize(range->minimum, range->maximum,
                                    normalized, &raw), "Supported setter input rejected");
                            probe.configure(nativeIndex, range->identifier, range->minimum, range->maximum, raw);
                            effect->setParameter(effect, nativeIndex, normalized);
                            require(probe.lookupCalls == 1 && probe.setCalls == 1 && !probe.getCalls &&
                                    probe.capturedIdentifier == range->identifier && probe.capturedFlag == 0 &&
                                    bits(probe.capturedRaw) == bits(raw), "Actual setter conversion differs");
                            ++callbackSetCases;
                            require(vl_tyrell_parameter_normalize(range->minimum, range->maximum, raw, &rebuilt),
                                    "Supported getter input rejected");
                            probe.configure(nativeIndex, range->identifier, range->minimum, range->maximum, raw);
                            const float result = effect->getParameter(effect, nativeIndex);
                            require(probe.lookupCalls == 1 && probe.getCalls == 1 && !probe.setCalls &&
                                    bits(result) == bits(rebuilt), "Actual controlled getter conversion differs");
                            ++callbackGetCases;
                        }
                    }
                }
            }
            uint64_t zeroWidthCases = 0;
            {
                ManagerProbe probe(manager, effect->object);
                for (float minimum : {-7.0f, -0.0f, 0.0f, 7.0f}) {
                    for (float raw : {-9.0f, 0.0f, 9.0f}) {
                        float rebuilt = 123;
                        probe.configure(0, 0, minimum, minimum, raw);
                        require(vl_tyrell_parameter_normalize(minimum, minimum, raw, &rebuilt) &&
                                bits(rebuilt) == bits(effect->getParameter(effect, 0)) &&
                                bits(rebuilt) == bits(minimum), "Zero-width minimum return differs");
                        ++zeroWidthCases;
                    }
                }
            }
            require(field<void**>(manager, 0) == original, "Native manager vtable not restored");
            std::cout << "{\"status\":\"passed\",\"actual_original_factory\":true,"
                      << "\"descriptors\":" << descriptors << ",\"actual_manager_round_trips\":" << actualRoundTrips
                      << ",\"controlled_native_setter_cases\":" << callbackSetCases
                      << ",\"controlled_native_getter_cases\":" << callbackGetCases
                      << ",\"synthetic_zero_width_getter_cases\":" << zeroWidthCases
                      << ",\"actual_manager_restored\":true,\"gui_branch_in_controlled_cases\":false,"
                      << "\"parameter_manager_rebuilt\":false,\"full_plugin_equivalence\":false}\n";
            return 0;
        } catch (const std::exception& error) {
            std::cerr << error.what() << '\n';
            return 1;
        }
    }
}
