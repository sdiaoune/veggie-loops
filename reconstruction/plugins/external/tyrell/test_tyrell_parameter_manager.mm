// Identity-pinned original manager methods versus compiled independent source.
// No original code/assets are included. The raw backend/notifier are synthetic.
#if !defined(__APPLE__) || !defined(__x86_64__)
#error The pinned TyrellN6 manager fixture requires macOS x86_64.
#endif
#define main vl_reference_probe_unused_main
#include "../../common/vst2_probe.mm"
#undef main
#include "tyrell_parameter_manager.h"
#include <CommonCrypto/CommonDigest.h>
#include <bit>
#include <cfenv>
#include <dlfcn.h>
#include <limits>
#include <xmmintrin.h>

template<class T> static T field(const void* pointer, size_t offset) {
    T value; std::memcpy(&value, static_cast<const char*>(pointer) + offset, sizeof value); return value;
}
template<class T> static void store(void* pointer, size_t offset, T value) {
    std::memcpy(static_cast<char*>(pointer) + offset, &value, sizeof value);
}
static uint32_t bits(float value) { return std::bit_cast<uint32_t>(value); }
static std::string sha256(const std::string& path) {
    std::ifstream file(path, std::ios::binary); require(bool(file), "Target binary not found");
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    std::array<char, 65536> bytes{};
    while (file.read(bytes.data(), bytes.size()) || file.gcount())
        CC_SHA256_Update(&context, bytes.data(), CC_LONG(file.gcount()));
    require(file.eof(), "Target read failed");
    std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest{}; CC_SHA256_Final(digest.data(), &context);
    std::string result;
    for (auto byte : digest) { result += "0123456789abcdef"[byte >> 4]; result += "0123456789abcdef"[byte & 15]; }
    return result;
}
struct Rebuild {
    void* library = nullptr;
    decltype(&vl_tyrell_parameter_descriptor) descriptor = nullptr;
    decltype(&vl_tyrell_parameter_decide) decide = nullptr;
    decltype(&vl_tyrell_parameter_manager_prepare) prepare = nullptr;
    decltype(&vl_tyrell_parameter_manager_clock) clock = nullptr;
    decltype(&vl_tyrell_parameter_manager_get) get = nullptr;
    decltype(&vl_tyrell_parameter_manager_write) write = nullptr;
    explicit Rebuild(const char* path) {
        library = dlopen(path, RTLD_NOW | RTLD_LOCAL); require(library, "Compiled reconstruction failed to load");
        descriptor = reinterpret_cast<decltype(descriptor)>(dlsym(library, "vl_tyrell_parameter_descriptor"));
        decide = reinterpret_cast<decltype(decide)>(dlsym(library, "vl_tyrell_parameter_decide"));
        prepare = reinterpret_cast<decltype(prepare)>(dlsym(library, "vl_tyrell_parameter_manager_prepare"));
        clock = reinterpret_cast<decltype(clock)>(dlsym(library, "vl_tyrell_parameter_manager_clock"));
        get = reinterpret_cast<decltype(get)>(dlsym(library, "vl_tyrell_parameter_manager_get"));
        write = reinterpret_cast<decltype(write)>(dlsym(library, "vl_tyrell_parameter_manager_write"));
        if (!(descriptor && decide && prepare && clock && get && write)) {
            dlclose(library); library = nullptr;
            throw std::runtime_error("Compiled C API incomplete");
        }
    }
    ~Rebuild() { if (library) dlclose(library); }
};

// Original lookup, map method, setter and getter-forwarder stay intact. Only
// the nested raw getter and manager write target are substituted. The actual
// native object/vtable/clock/last-ID are restored before factory destruction.
// The controlled notifier synchronously commits to the prepared raw array;
// this is NOT an equivalence claim for the native audio object's scheduling.
struct Backend {
    void* manager;
    void* audio;
    void** originalAudioVtable;
    void* originalTarget;
    void* originalClock;
    int32_t originalLast;
    std::array<void*, 101> audioVtable{};
    std::array<void*, 84> notifierVtable{};
    struct Target { void** vtable; uint64_t guard; } target{};
    float clock = 0;
    std::array<float, 92> values{};
    int32_t expectedIndex = 0, expectedFlag = 0, lastAtGet = -1, lastAtNotify = -1;
    unsigned getCalls = 0, notifyCalls = 0;
    int32_t gotIndex = -1, gotFlag = -1, notifyIndex = -1, notifyFlag = -1;
    float gotFallback = 0, notifyValue = 0, notifyClock = 0;
    static thread_local Backend* current;
    static float rawGet(void* self, int32_t index, float fallback, int32_t flag) {
        auto& p = *current;
        require(self == p.audio && index == p.expectedIndex && flag == p.expectedFlag,
                "Native getter-forwarding receiver/index/flag differs");
        p.gotIndex = index; p.gotFlag = flag; p.gotFallback = fallback;
        p.lastAtGet = field<int32_t>(p.manager, 0xf0); ++p.getCalls;
        const auto* r = vl_tyrell_parameter_range(flag ? index : 10000 + index);
        require(r, "Synthetic getter index outside bounded map");
        return p.values[r->public_index];
    }
    static void notify(void* self, int32_t identifier, float value, int32_t flag, float floatClock) {
        auto& p = *current;
        require(self == &p.target && p.target.guard == 0x5a5a5a5a12345678ull,
                "Native notifier receiver/guard differs");
        p.notifyIndex = identifier; p.notifyFlag = flag;
        p.notifyValue = value; p.notifyClock = floatClock;
        p.lastAtNotify = field<int32_t>(p.manager, 0xf0); ++p.notifyCalls;
        const auto* r = vl_tyrell_parameter_range(10000 + identifier);
        require(r, "Synthetic notifier identifier outside map");
        p.values[r->public_index] = value;
    }
    explicit Backend(void* nativeManager) : manager(nativeManager),
        audio(field<void*>(manager, 0x40)), originalAudioVtable(field<void**>(audio, 0)),
        originalTarget(field<void*>(manager, 0x48)), originalClock(field<void*>(manager, 0x58)),
        originalLast(field<int32_t>(manager, 0xf0)) {
        require(!current, "Nested backend substitution");
        std::copy_n(originalAudioVtable, audioVtable.size(), audioVtable.begin());
        audioVtable[0x2d8 / 8] = reinterpret_cast<void*>(&rawGet);
        notifierVtable[0x298 / 8] = reinterpret_cast<void*>(&notify);
        target = {notifierVtable.data(), 0x5a5a5a5a12345678ull};
        current = this;
        store(audio, 0, audioVtable.data()); store<void*>(manager, 0x48, &target);
        store<void*>(manager, 0x58, &clock);
    }
    ~Backend() {
        store(audio, 0, originalAudioVtable); store(manager, 0x48, originalTarget);
        store(manager, 0x58, originalClock); store(manager, 0xf0, originalLast); current = nullptr;
    }
    void begin(int32_t identifier, float time, int32_t previousLast) {
        expectedIndex = identifier; expectedFlag = 0; clock = time;
        getCalls = notifyCalls = 0; lastAtGet = lastAtNotify = -1;
        gotIndex = gotFlag = notifyIndex = notifyFlag = -1;
        gotFallback = notifyValue = notifyClock = 0;
        store(manager, 0xf0, previousLast);
    }
};
thread_local Backend* Backend::current = nullptr;

static void compareDecision(const Backend& backend, const VLTyrellParameterWrite& result) {
    require(backend.getCalls == result.getter_calls && backend.notifyCalls == result.notifier_calls,
            "Native getter/notifier suppression differs");
    if (result.getter_calls) {
        require(backend.gotIndex == result.identifier && backend.gotFlag == result.getter_flag &&
                bits(backend.gotFallback) == bits(result.getter_fallback) && backend.lastAtGet == result.identifier,
                "Fallback or last-ID-before-get ordering differs");
    }
    if (result.notifier_calls) {
        require(backend.notifyIndex == result.identifier && backend.notifyFlag == result.notifier_flag &&
                bits(backend.notifyValue) == bits(result.value) && bits(backend.notifyClock) == bits(result.clock) &&
                backend.lastAtNotify == result.identifier, "Notifier ID/value/clock/order differs");
    }
}

int main(int argc, char** argv) {
    std::cout << std::unitbuf;
    @autoreleasepool {
        try {
            require(argc == 3, "Expected original bundle and rebuilt library");
            require(std::fegetround() == FE_TONEAREST, "Nearest-even rounding required");
            require(sha256(std::string(argv[1]) + "/Contents/MacOS/TyrellN6") ==
                    "a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54",
                    "Native identity mismatch; refusing offsets");
            Rebuild rebuilt(argv[2]);
            transport.sampleRate = 48000; transport.tempo = 120;
            Bundle bundle;
            auto url = CFURLCreateFromFileSystemRepresentation(nullptr,
                reinterpret_cast<const UInt8*>(argv[1]), std::strlen(argv[1]), true);
            require(url, "Bundle URL failed"); bundle.value = CFBundleCreate(nullptr, url); CFRelease(url);
            require(bundle.value && CFBundleLoadExecutable(bundle.value), "Original bundle load failed");
            auto entry = reinterpret_cast<Effect* (*)(Dispatch)>(
                CFBundleGetFunctionPointerForName(bundle.value, CFSTR("VSTPluginMain")));
            require(entry, "Native factory missing");
            Dl_info info{}; require(dladdr(reinterpret_cast<void*>(entry), &info) && info.dli_fbase, "No image base");
            const auto base = reinterpret_cast<uintptr_t>(info.dli_fbase);
            require(reinterpret_cast<uintptr_t>(entry) - base == 0x3ddb0, "Unexpected native factory entry");
            Instance instance; instance.value = entry(host);
            auto* effect = instance.value;
            require(effect && effect->magic == 0x56737450 && effect->dispatcher, "Native factory failed");
            effect->dispatcher(effect, 0, 0, 0, nullptr, 0); instance.opened = true;
            require(effect->parameters == 92 && effect->object, "Actual parameter count differs");
            require(std::fegetround() == FE_TONEAREST && (_mm_getcsr() & 0x8040u) == 0,
                    "Original factory changed the required nearest/gradual FP environment");
            void* manager = field<void*>(effect->object, 0x138); require(manager, "No native manager");
            auto** vtable = field<void**>(manager, 0);
            for (const auto [slot, offset] : {std::pair<size_t, size_t>{0x1b8, 0x125630},
                    {0x1c8, 0x125780}, {0x250, 0x1255b0}})
                require(reinterpret_cast<uintptr_t>(vtable[slot / 8]) - base == offset, "Actual native manager slot mismatch");
            auto nativeSet = reinterpret_cast<void (*)(void*, int32_t, float, int32_t)>(vtable[0x1b8 / 8]);
            auto nativeGet = reinterpret_cast<float (*)(void*, int32_t, float, int32_t)>(vtable[0x1c8 / 8]);
            auto nativeLookup = reinterpret_cast<void* (*)(void*, int32_t, int32_t)>(vtable[0x250 / 8]);
            uint64_t descriptors = 0, type0 = 0, type1 = 0, writes = 0, equalWrites = 0, notifications = 0, forwardedGets = 0, syntheticTypes = 0;
            for (int i = 0; i < 92; ++i) {
                VLTyrellParameterDescriptor d{}, internal{};
                require(rebuilt.descriptor(i, 1, &d) && rebuilt.descriptor(d.range.identifier, 0, &internal) &&
                        !std::memcmp(&d, &internal, sizeof d), "Compiled descriptor map differs");
                void* source = nativeLookup(manager, i, 1);
                require(source && source == nativeLookup(manager, d.range.identifier, 0) &&
                        field<int32_t>(source, 0) == d.range.identifier && field<uint8_t>(source, 0x48) == d.type &&
                        bits(field<float>(source, 0x4c)) == bits(d.range.minimum) &&
                        bits(field<float>(source, 0x50)) == bits(d.range.maximum), "Actual descriptor type/map/range differs");
                ++descriptors;
                type0 += d.type == 0; type1 += d.type == 1;
            }
            {
                Backend backend(manager);
                VLTyrellParameterManager model{};
                require(rebuilt.prepare(backend.values.data(), 92, 0, -1, &model), "Compiled preparation failed");
                std::vector<float> values{0.0f, -0.0f, std::numeric_limits<float>::denorm_min(),
                    -std::numeric_limits<float>::denorm_min(), std::numeric_limits<float>::min(),
                    -std::numeric_limits<float>::min(), 4096, -4096, 4095.5f, -4095.5f};
                for (int integer = -128; integer <= 128; integer += 4) {
                    const float half = float(integer) + 0.5f;
                    values.push_back(half); values.push_back(std::nextafter(half, -INFINITY));
                    values.push_back(std::nextafter(half, INFINITY));
                }
                uint32_t rng = 0x7319743;
                for (int i = 0; i < 256; ++i) {
                    rng = rng * 1664525u + 1013904223u;
                    values.push_back(float(int32_t(rng % 1048577u) - 524288) / 128.0f);
                }
                const std::array<float, 8> clocks{0.0f, -0.0f, 0.125f, -12.75f, 48000.5f,
                    std::numeric_limits<float>::denorm_min(), std::numeric_limits<float>::max(),
                    -std::numeric_limits<float>::max()};
                for (int publicIndex = 0; publicIndex < 92; ++publicIndex) {
                    VLTyrellParameterDescriptor d{}; require(rebuilt.descriptor(publicIndex, 1, &d), "Descriptor missing");
                    // Direct actual get-forwarder calls retain public/internal
                    // flag and fallback independently of the setter corpus.
                    for (int flag = 0; flag < 2; ++flag) for (float fallback : clocks) {
                        backend.expectedIndex = flag ? publicIndex : d.range.identifier; backend.expectedFlag = flag;
                        backend.values[publicIndex] = -23.25f; backend.getCalls = 0;
                        const float got = nativeGet(manager, backend.expectedIndex, fallback, flag);
                        require(got == -23.25f && backend.getCalls == 1 && bits(backend.gotFallback) == bits(fallback),
                                "Direct getter fallback forwarding differs"); ++forwardedGets;
                    }
                    for (int flag = 0; flag < 2; ++flag) for (float input : values) for (int oldMode = 0; oldMode < 3; ++oldMode) {
                        const float time = clocks[(writes + oldMode) % clocks.size()];
                        VLTyrellParameterWrite expected{};
                        require(rebuilt.decide(d.range.identifier, d.type, input, 0, time, &expected), "Compiled decision rejected valid input");
                        const float old = oldMode == 0 ? expected.value : oldMode == 1 ? 37.125f : -0.0f;
                        model.raw[publicIndex] = backend.values[publicIndex] = old;
                        model.clock = time;
                        model.last_identifier = publicIndex == 0 ? 7 : 0;
                        backend.begin(d.range.identifier, time, model.last_identifier);
                        const int index = flag ? publicIndex : d.range.identifier;
                        VLTyrellParameterWrite result{};
                        require(rebuilt.write(&model, index, flag, input, &result), "Compiled write rejected valid input");
                        nativeSet(manager, index, input, flag);
                        compareDecision(backend, result);
                        require(field<int32_t>(manager, 0xf0) == model.last_identifier &&
                                !std::memcmp(model.raw, backend.values.data(), sizeof model.raw), "Prepared backend/last-ID result differs");
                        float read = 123; require(rebuilt.get(&model, index, flag, &read) &&
                            bits(read) == bits(backend.values[publicIndex]), "Prepared getter differs");
                        ++writes; notifications += result.notifier_calls; equalWrites += !result.notifier_calls;
                    }
                }
                // Additional descriptor branch semantics use a synthetic table
                // of empty descriptors. The map and all three manager methods
                // are still original. No native public type-3/5 is asserted.
                struct DescriptorTable {
                    void* audio; void* old; std::array<unsigned char, 213 * 116> bytes{};
                    explicit DescriptorTable(void* object) : audio(object), old(field<void*>(audio, 0x4e0)) {
                        store<void*>(audio, 0x4e0, bytes.data());
                    }
                    ~DescriptorTable() { store(audio, 0x4e0, old); }
                } table(backend.audio);
                for (uint32_t type : {0u, 1u, 2u, 3u, 4u, 5u, 255u}) {
                    table.bytes[0x48] = uint8_t(type);
                    for (float input : {-0.0f, std::nextafter(-0.5f, -1.0f), -0.5f,
                                         std::nextafter(0.5f, 0.0f), 0.5f, 4096.0f}) {
                        backend.values[0] = 0.0f; backend.begin(0, -0.0f, 7);
                        VLTyrellParameterWrite result{};
                        require(rebuilt.decide(0, type, input, 0.0f, backend.clock, &result), "Prepared type decision failed");
                        nativeSet(manager, 0, input, 0); compareDecision(backend, result);
                        require(field<int32_t>(manager, 0xf0) == (type == 3 ? 7 : 0), "Synthetic meter last-ID early return differs");
                        ++syntheticTypes;
                    }
                }
            }
            std::cout << "{\"native_manager\":true,\"actual_descriptors\":" << descriptors
                << ",\"actual_type0\":" << type0 << ",\"actual_type1\":" << type1
                << ",\"write_cases\":" << writes << ",\"equal_suppressed\":" << equalWrites
                << ",\"notifications\":" << notifications << ",\"get_forwarding\":" << forwardedGets
                << ",\"synthetic_type_cases\":" << syntheticTypes << "}\n";
            return 0;
        } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    }
}
