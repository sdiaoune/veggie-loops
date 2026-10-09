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
#include <stdexcept>
#include <string>
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
        require(argc == 3, "Expected original binary and rebuilt curve library");
        NSData* bytes = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        require(bytes != nil && sha256(bytes) == "ef2675ee69f9498ae10807820660e1158ba3c50684f44dea46b03efd7ceb1b07",
                "The original Purity universal binary identity changed");
        Module original(argv[1]), rebuilt(argv[2]);
        auto prepare = original.get<void(*)(const double*)>("_Z18_makeEnvelopeCurvePd");
        auto* nativeCurve = original.get<const float*>("curveEnvelope");
        auto generate = rebuilt.get<int(*)(double, float*)>("vl_purity_envelope_curve");
        std::vector<double> amounts;
        for (int i = -1024; i <= 1024; ++i) amounts.push_back(double(i) / 64);
        for (double value : {0.0, -0.0, 1e-300, -1e-300, std::nextafter(16.0, 0.0), std::nextafter(-16.0, 0.0)})
            amounts.push_back(value);
        constexpr float sentinel = std::bit_cast<float>(std::uint32_t{0x5a29d113});
        std::array<float, 263> storage;
        std::uint64_t compared = 0;
        for (double amount : amounts) {
            storage.fill(sentinel);
            std::array<double, 4> parameters{0, 0, 0, amount};
            prepare(parameters.data());
            auto* output = storage.data() + 2;
            require(generate(amount, output) == 1, "Rebuilt curve failed");
            require(std::memcmp(output, nativeCurve, 259 * sizeof(float)) == 0, "Curve mismatch");
            require(storage[0] == sentinel && storage[1] == sentinel &&
                    storage[261] == sentinel && storage[262] == sentinel, "Output guard overwritten");
            compared += 259;
        }
        storage.fill(sentinel);
        const auto saved = storage;
        for (double invalid : {std::nextafter(-16.0, -17.0), std::nextafter(16.0, 17.0),
                               double(INFINITY), double(-INFINITY), double(NAN)}) {
            require(generate(invalid, storage.data() + 2) == 0 && storage == saved,
                    "Invalid curve amount changed output");
        }
        require(generate(0, nullptr) == 0, "Null output accepted");
        std::printf("{\"status\":\"passed\",\"curve_cases\":%zu,\"exact_float_values\":%llu,\"output_guards\":true,\"invalid_arguments_atomic\":true,\"native_plugin_recompiled\":false}\n",
                    amounts.size(), static_cast<unsigned long long>(compared));
        return 0;
    } catch (const std::exception& error) { std::fprintf(stderr, "%s\n", error.what()); return 1; }
} }
