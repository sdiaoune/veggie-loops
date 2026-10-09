#if !defined(__APPLE__) || !defined(__aarch64__)
#error This identity-bound native fixture supports macOS arm64 only.
#endif
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include "envelope_follower.h"
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
struct Guarded {
    std::array<std::uint64_t, 2> before;
    VLPurityEnvelopeFollower state;
    std::array<std::uint64_t, 2> after;
};
}
int main(int argc, char** argv) { @autoreleasepool {
    try {
        require(argc == 3, "Expected original binary and rebuilt follower library");
        NSData* bytes = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        require(bytes != nil && sha256(bytes) == "ef2675ee69f9498ae10807820660e1158ba3c50684f44dea46b03efd7ceb1b07",
                "The original Purity universal binary identity changed");
        Module original(argv[1]), rebuilt(argv[2]);
        auto prepare = original.get<void(*)(const double*)>("_Z18_makeEnvelopeCurvePd");
        // The follower symbol is local. The verified arm64 image binds its
        // address to the exported curve helper; no target bytes are copied.
        Dl_info identity{};
        require(dladdr(reinterpret_cast<void*>(prepare), &identity) != 0 && identity.dli_fbase &&
                reinterpret_cast<std::uintptr_t>(prepare) -
                reinterpret_cast<std::uintptr_t>(identity.dli_fbase) == 0x65744,
                "Native arm64 curve helper address changed");
        auto native = reinterpret_cast<void(*)(const float*, VLPurityEnvelopeFollower*, const double*, int)>(
            reinterpret_cast<std::uintptr_t>(identity.dli_fbase) + 0x71884);
        auto curve = rebuilt.get<int(*)(double, float*)>("vl_purity_envelope_curve");
        auto follow = rebuilt.get<decltype(&vl_purity_envelope_follow)>("vl_purity_envelope_follow");
        constexpr std::array<std::uint64_t, 2> guard{0x3141592653589793, 0xa5b6c7d8e9f00112};
        const std::array<double, 13> positions{0, -0.0, 1e-300, 0.25, 0.5,
            std::nextafter(0.5, 0.0), std::nextafter(0.5, 1.0), 1.5, 127.5,
            254.5, std::nextafter(255.0, 0.0), 255, 254.999};
        const std::array<double, 9> motions{0, -0.0, 1e-300, 0.125, 0.5, 1, 31.25, 255, 510};
        const std::array<int, 5> counts{1, 3, 31, 511, 8192};
        const std::array<float, 4> attacks{0, -0.0f, 0.1f, 1};
        const std::array<float, 4> sustains{0, 0.25f, 0.9f, 1};
        std::uint64_t cases = 0, sequences = 0;
        std::array<float, 259> generated{};
        auto compare = [&](const std::array<float, 4>& config, Guarded& expected, Guarded& actual,
                           const std::array<double, 3>& steps, int count) {
            const auto saved_config = config;
            const auto saved_curve = generated;
            const auto saved_steps = steps;
            native(config.data(), &expected.state, steps.data(), count);
            require(follow(config[0], config[2], &actual.state, steps.data(), generated.data(), count) == 1,
                    "Rebuilt follower rejected valid fixture");
            if (std::memcmp(&actual.state, &expected.state, sizeof actual.state)) {
                std::fprintf(stderr, "Follower mismatch at case%llu stage%d pos%.17g count%d increments%.9g/%.9g\n",
                    static_cast<unsigned long long>(cases), config[0] > 0 ? actual.state.stage : expected.state.stage,
                    actual.state.position, count, actual.state.increment, expected.state.increment);
                throw std::runtime_error("Native follower state mismatch");
            }
            require(expected.before == guard && expected.after == guard &&
                    actual.before == guard && actual.after == guard, "Follower state guard changed");
            require(std::memcmp(config.data(), saved_config.data(), sizeof config) == 0 &&
                    std::memcmp(steps.data(), saved_steps.data(), sizeof steps) == 0 &&
                    std::memcmp(generated.data(), saved_curve.data(), sizeof generated) == 0,
                    "Caller-owned inputs changed");
            ++cases;
        };
        for (double amount : {-16.0, -8.0, -2.0, -0.125, 0.0, 0.125, 2.0, 8.0, 16.0}) {
            std::array<double, 4> parameters{0, 0, 0, amount};
            prepare(parameters.data());
            require(curve(amount, generated.data()) == 1, "Curve setup failed");
            for (int stage = 0; stage <= 5; ++stage) for (double position : positions)
                for (double motion : motions) for (int count : counts) for (int setup = 0; setup < 4; ++setup) {
                    const std::array<float, 4> config{attacks[setup], 0.333f, sustains[setup], 0.777f};
                    const std::array<double, 3> steps{motion, motion * 0.75, motion * 0.5};
                    const VLPurityEnvelopeFollower initial{stage, 0xdeadbeef, position,
                        sustains[3 - setup], -0.0f, (setup == 0 ? -0.0f : sustains[setup]), 0xcafef00d};
                    Guarded expected{guard, initial, guard}, actual = expected;
                    compare(config, expected, actual, steps, count);
                }
            // Processing repeated blocks separately from the caller's linear
            // level update exercises transitions and note-off initialization.
            for (int setup = 0; setup < 4; ++setup) {
                const std::array<float, 4> config{attacks[setup], 0, sustains[setup], 0};
                const std::array<double, 3> steps{31.875, 15.9375, 7.96875};
                Guarded expected{guard, {1, 0xdeadbeef, 0, 0, 0, 0, 0xcafef00d}, guard}, actual = expected;
                for (int block = 0; block < 80; ++block) {
                    if (block == 40) {
                        expected.state.stage = actual.state.stage = 5;
                        expected.state.position = actual.state.position = 255;
                        expected.state.release_scale = expected.state.level;
                        actual.state.release_scale = actual.state.level;
                    }
                    compare(config, expected, actual, steps, 31);
                    expected.state.level += expected.state.increment * 31.0f;
                    actual.state.level += actual.state.increment * 31.0f;
                }
                ++sequences;
            }
        }
        std::uint32_t random_state = 0x438a912b;
        auto uniform = [&]() {
            random_state ^= random_state << 13;
            random_state ^= random_state >> 17;
            random_state ^= random_state << 5;
            return double(random_state) / double(UINT32_MAX);
        };
        for (int trial = 0; trial < 10000; ++trial) {
            const double amount = uniform() * 32 - 16;
            std::array<double, 4> parameters{0, 0, 0, amount};
            prepare(parameters.data());
            require(curve(amount, generated.data()) == 1, "Random curve setup failed");
            const std::array<float, 4> config{float(uniform()), -0.0f, float(uniform()), 1};
            const std::array<double, 3> coefficients{uniform() * 510, uniform() * 510, uniform() * 510};
            const VLPurityEnvelopeFollower initial{trial % 6, 0xdeadbeef, uniform() * 255,
                float(uniform() * 2 - 1), float(uniform() * 2 - 1),
                float(uniform() * 4 - 2), 0xcafef00d};
            Guarded expected{guard, initial, guard}, actual = expected;
            compare(config, expected, actual, coefficients, 1 + int(uniform() * 8191));
        }
        std::uint64_t unit_overshoots = 0;
        for (double amount : {-16.0, -8.0, -2.0, 2.0, 8.0, 16.0}) {
            std::array<double, 4> parameters{0, 0, 0, amount};
            prepare(parameters.data());
            require(curve(amount, generated.data()) == 1, "Steep curve setup failed");
            for (double motion : {0.125, 0.5, 1.25, 31.875, 253.75, 255.0, 510.0})
                for (float sustain : {0.0f, 0.25f, 1.0f}) for (int note_off : {1, 2, 2100}) {
                    const std::array<float, 4> config{1, 0, sustain, 0};
                    const std::array<double, 3> coefficients{motion, motion, motion};
                    Guarded expected{guard, {2, 0xdeadbeef, 255, 1, 0, 1, 0xcafef00d}, guard}, actual = expected;
                    for (int block = 0; block < 2200; ++block) {
                        if (block == note_off) {
                            expected.state.stage = actual.state.stage = 5;
                            expected.state.position = actual.state.position = 255;
                            expected.state.release_scale = expected.state.level;
                            actual.state.release_scale = actual.state.level;
                        }
                        compare(config, expected, actual, coefficients, 1);
                        if (std::fabs(expected.state.increment) > 1 || expected.state.level < 0 ||
                            expected.state.level > 1) ++unit_overshoots;
                        expected.state.level += expected.state.increment;
                        actual.state.level += actual.state.increment;
                    }
                    ++sequences;
                }
        }
        require(unit_overshoots > 0, "Repeated native overshoot regression was not exercised");
        const float largest = std::numeric_limits<float>::max();
        const float smallest = std::numeric_limits<float>::denorm_min();
        for (float level : {-largest, largest, -smallest, smallest})
            for (float scale : {-2.0f, 2.0f}) for (int stage = 0; stage <= 5; ++stage) {
                const std::array<float, 4> config{1, 0, 1, 0};
                const std::array<double, 3> coefficients{1.25, 1.25, 1.25};
                const VLPurityEnvelopeFollower initial{stage, 0xdeadbeef, 255, level, largest, scale, 0xcafef00d};
                Guarded expected{guard, initial, guard}, actual = expected;
                compare(config, expected, actual, coefficients, 3);
            }
        VLPurityEnvelopeFollower valid{1, 0xdeadbeef, 0, 0, 0, 0.5f, 0xcafef00d};
        std::array<double, 3> steps{1, 2, 3};
        std::uint64_t rejected = 0;
        auto reject = [&](float attack, float sustain, VLPurityEnvelopeFollower initial,
                          const double* coefficients, const float* points, int count) {
            auto state = initial;
            require(follow(attack, sustain, &state, coefficients, points, count) == 0 &&
                    std::memcmp(&state, &initial, sizeof state) == 0, "Invalid input changed follower state");
            ++rejected;
        };
        for (float bad : {-0.1f, 1.1f, float(INFINITY), float(-INFINITY), float(NAN)}) {
            reject(bad, 0.5f, valid, steps.data(), generated.data(), 31);
            reject(0.5f, bad, valid, steps.data(), generated.data(), 31);
        }
        for (int stage : {-1, 6}) { auto x = valid; x.stage = stage; reject(.5f, .5f, x, steps.data(), generated.data(), 31); }
        for (double bad : {-0.1, 255.1, double(INFINITY), double(NAN)}) {
            auto x = valid; x.position = bad; reject(.5f, .5f, x, steps.data(), generated.data(), 31);
        }
        for (int field = 0; field < 3; ++field) for (float bad : {float(INFINITY), float(-INFINITY), float(NAN)}) {
            auto x = valid;
            if (field == 0) x.level = bad; else if (field == 1) x.increment = bad; else x.release_scale = bad;
            reject(.5f, .5f, x, steps.data(), generated.data(), 31);
        }
        for (float bad : {-2.1f, 2.1f}) {
            auto x = valid; x.release_scale = bad; reject(.5f, .5f, x, steps.data(), generated.data(), 31);
        }
        for (int field = 0; field < 3; ++field) for (double bad : {-0.1, 510.1, double(INFINITY), double(NAN)}) {
            auto x = steps; x[field] = bad; reject(.5f, .5f, valid, x.data(), generated.data(), 31);
        }
        for (int index : {0, 128, 258}) for (float bad : {-0.1f, 1.1f, float(INFINITY), float(NAN)}) {
            auto x = generated; x[index] = bad; reject(.5f, .5f, valid, steps.data(), x.data(), 31);
        }
        for (int count : {-1, 0, 8193}) reject(.5f, .5f, valid, steps.data(), generated.data(), count);
        reject(.5f, .5f, valid, nullptr, generated.data(), 31);
        reject(.5f, .5f, valid, steps.data(), nullptr, 31);
        require(follow(.5f, .5f, nullptr, steps.data(), generated.data(), 31) == 0, "Null state accepted");
        std::printf("{\"status\":\"passed\",\"state_cases\":%llu,\"exact_state_bytes\":%llu,\"sequences\":%llu,\"random_cases\":10000,\"unit_overshoot_blocks\":%llu,\"invalid_cases\":%llu,\"guarded\":true,\"native_plugin_recompiled\":false}\n",
            static_cast<unsigned long long>(cases), static_cast<unsigned long long>(cases * 32),
            static_cast<unsigned long long>(sequences), static_cast<unsigned long long>(unit_overshoots),
            static_cast<unsigned long long>(rejected + 1));
        return 0;
    } catch (const std::exception& error) { std::fprintf(stderr, "%s\n", error.what()); return 1; }
} }
