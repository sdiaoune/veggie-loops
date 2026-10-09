#if !defined(__APPLE__) || !defined(__aarch64__)
#error This identity-bound native fixture supports macOS arm64 only.
#endif
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <array>
#include <bit>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include "rms_compressor.h"
#include <vector>
namespace {
void require(bool ok, const char* text) { if (!ok) throw std::runtime_error(text); }
struct Module {
    void* value;
    explicit Module(const char* path) : value(dlopen(path, RTLD_LOCAL | RTLD_NOW)) {
        if (!value) throw std::runtime_error(dlerror());
    }
    ~Module() { dlclose(value); }
    template<class T> T get(const char* name) {
        auto* result = dlsym(value, name); require(result != nullptr, name);
        return reinterpret_cast<T>(result);
    }
};
std::string sha256(NSData* bytes) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, static_cast<CC_LONG>(bytes.length), digest);
    std::string result;
    for (unsigned char b : digest) { char hex[3]; std::snprintf(hex, sizeof hex, "%02x", b); result += hex; }
    return result;
}
}
int main(int argc, char** argv) { @autoreleasepool {
    try {
        require(argc == 3, "Expected original binary and rebuilt compressor library");
        NSData* bytes = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        require(bytes != nil && sha256(bytes) == "ef2675ee69f9498ae10807820660e1158ba3c50684f44dea46b03efd7ceb1b07",
                "The original Purity universal binary identity changed");
        Module original(argv[1]), rebuilt(argv[2]);
        auto native = original.get<void(*)(void*, float*, float*, int)>("_ZN17CIFXRMSCompressor7processEPfS0_i");
        auto process = rebuilt.get<decltype(&vl_purity_rms_compress)>("vl_purity_rms_compress");
        struct GuardedRMSCompressor {
            std::array<std::uint64_t, 2> before;
            VLPurityRMSCompressor state;
            std::array<std::uint64_t, 2> after;
        };
        constexpr std::array<std::uint64_t, 2> guard{0x3141592653589793, 0xa5b6c7d8e9f00112};
        constexpr float sentinel = std::bit_cast<float>(std::uint32_t{0x5a29d113});
        std::uint32_t random_state = 0x1a87b092;
        auto uniform = [&]() {
            random_state ^= random_state << 13; random_state ^= random_state >> 17;
            random_state ^= random_state << 5;
            return double(random_state) / double(UINT32_MAX);
        };
        std::uint64_t cases = 0, frames = 0, repeated = 0;
        const std::array<int, 9> counts{0, 1, 3, 31, 64, 255, 512, 1024, 8192};
        for (float rate : {8000.0f, 11025.0f, 44100.0f, 48000.0f, 96000.0f, 192000.0f})
            for (int setup = 0; setup < 12; ++setup) for (int count : counts) for (bool alias : {false, true}) {
                VLPurityRMSCompressor initial{};
                initial.base.reserved0 = 0xabadbeef31415926;
                for (auto& v : initial.base.reserved1) v = 0x8765abcd;
                initial.base.sample_rate = rate;
                initial.base.threshold = setup % 4 == 0 ? -0.0f : float(uniform());
                initial.base.ratio = setup % 4 == 1 ? 1.0f : float(uniform());
                initial.base.release = setup % 4 == 2 ? 0.0f : float(uniform());
                initial.base.target_threshold = setup % 3 == 0 ? 0.0f : setup % 3 == 1 ? 1.0f : initial.base.threshold;
                initial.base.target_ratio = setup % 3 == 0 ? 1.0f : setup % 3 == 1 ? 0.0f : initial.base.ratio;
                initial.base.target_release = setup % 3 == 0 ? 0.0f : setup % 3 == 1 ? 1.0f : initial.base.release;
                initial.base.gain = setup % 2 ? 1.0f : float(uniform());
                initial.base.dirty = 0x71;
                initial.detector = setup % 3 == 0 ? 0.0f : setup % 3 == 1 ? 131072.0f : float(uniform() * 131072);
                initial.reserved3 = 0xe32a961b;
                for (auto& v : initial.base.reserved2) v = 0x8c;
                GuardedRMSCompressor expected{guard, initial, guard}, actual = expected;
                std::vector<float> nl(count + 4, sentinel), nr = nl, ml = nl, mr = nl;
                const int generations = count < 8192 ? 12 : 2;
                for (int generation = 0; generation < generations; ++generation) {
                    for (int i = 0; i < count; ++i) {
                        float left = float(uniform() * 8 - 4), right = float(uniform() * 8 - 4);
                        if (i % 8 == 0) left = 0;
                        if (i % 8 == 1) left = -0.0f;
                        if (i % 8 == 2) right = std::numeric_limits<float>::denorm_min();
                        if (i % 8 == 3) right = -std::numeric_limits<float>::denorm_min();
                        nl[i + 2] = ml[i + 2] = left; nr[i + 2] = mr[i + 2] = right;
                    }
                    native(&expected.state, nl.data() + 2, alias ? nl.data() + 2 : nr.data() + 2, count);
                    require(process(&actual.state, ml.data() + 2, alias ? ml.data() + 2 : mr.data() + 2, count) == 1,
                            "Rebuilt compressor rejected prepared fixture");
                    require(std::memcmp(&expected.state, &actual.state, sizeof actual.state) == 0,
                            "Prepared compressor state mismatch");
                    require(std::memcmp(nl.data(), ml.data(), nl.size() * sizeof(float)) == 0 &&
                            std::memcmp(nr.data(), mr.data(), nr.size() * sizeof(float)) == 0,
                            "Compressor audio mismatch");
                    for (const auto* audio : {&nl, &nr, &ml, &mr})
                        require((*audio)[0] == sentinel && (*audio)[1] == sentinel &&
                            (*audio)[count + 2] == sentinel && (*audio)[count + 3] == sentinel,
                            "Compressor audio guard changed");
                    require(expected.before == guard && expected.after == guard &&
                            actual.before == guard && actual.after == guard, "Compressor state guard changed");
                    ++cases; frames += count; if (generation > 0) ++repeated;
                }
            }
        VLPurityRMSCompressor valid{}; valid.base.sample_rate = 48000; valid.base.gain = 1;
        valid.base.dirty = 77;
        std::array<float, 12> left{}, right{};
        std::uint64_t invalid = 0;
        auto reject = [&](VLPurityRMSCompressor initial, float* l, float* r, int count, bool state_alias = false) {
            const auto saved_left = left, saved_right = right;
            auto state = initial;
            if (state_alias) l = reinterpret_cast<float*>(&state);
            require(process(&state, l, r, count) == 0 && std::memcmp(&state, &initial, sizeof state) == 0 &&
                    std::memcmp(left.data(), saved_left.data(), sizeof left) == 0 &&
                    std::memcmp(right.data(), saved_right.data(), sizeof right) == 0,
                    "Invalid compressor call changed state/audio");
            ++invalid;
        };
        for (int count : {-1, 8193}) reject(valid, left.data(), right.data(), count);
        reject(valid, nullptr, right.data(), 4); reject(valid, left.data(), nullptr, 4);
        reject(valid, left.data(), left.data() + 1, 4);
        reject(valid, nullptr, right.data(), 4, true);
        for (float rate : {7999.0f, 192001.0f, float(INFINITY), float(NAN)}) {
            auto x = valid; x.base.sample_rate = rate; reject(x, left.data(), right.data(), 4);
        }
        for (int field = 0; field < 7; ++field) for (float bad : {-0.1f, 1.1f, float(INFINITY), float(NAN)}) {
            auto x = valid;
            float* fields[] = {&x.base.threshold, &x.base.ratio, &x.base.release, &x.base.target_threshold,
                              &x.base.target_ratio, &x.base.target_release, &x.base.gain};
            *fields[field] = bad; reject(x, left.data(), right.data(), 4);
        }
        for (float bad : {-0.1f, 131073.0f, float(INFINITY), float(NAN)}) {
            auto x = valid; x.detector = bad; reject(x, left.data(), right.data(), 4);
        }
        for (float bad : {-4.1f, 4.1f, float(INFINITY), float(NAN)}) {
            left[3] = bad; reject(valid, left.data(), right.data(), 4); left[3] = 0;
            right[3] = bad; reject(valid, left.data(), right.data(), 4); right[3] = 0;
        }
        require(process(nullptr, nullptr, nullptr, 0) == 0, "Null compressor state accepted");
        require(process(&valid, nullptr, nullptr, 0) == 1 && valid.base.dirty == 0, "Zero-count completion failed");
        std::printf("{\"status\":\"passed\",\"prepared_state_cases\":%llu,\"stereo_frames\":%llu,\"repeated_cases\":%llu,\"invalid_cases\":%llu,\"guarded\":true,\"native_factory\":false,\"native_plugin_recompiled\":false}\n",
            static_cast<unsigned long long>(cases), static_cast<unsigned long long>(frames),
            static_cast<unsigned long long>(repeated), static_cast<unsigned long long>(invalid + 1));
        return 0;
    } catch (const std::exception& error) { std::fprintf(stderr, "%s\n", error.what()); return 1; }
} }
