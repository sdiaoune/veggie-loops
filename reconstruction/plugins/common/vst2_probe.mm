// Original, isolated 64-bit legacy VST instrument probe. The ABI records below
// describe the protocol; no commercial SDK or plugin implementation is included.
// Loading an installed plugin is reference evidence, never recompilation proof.
#import <AppKit/AppKit.h>
#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

struct Effect;
using Dispatch = intptr_t (*)(Effect*, int32_t, int32_t, intptr_t, void*, float);
using Process = void (*)(Effect*, float**, float**, int32_t);
struct Effect {
    int32_t magic;
    Dispatch dispatcher;
    Process process;
    void (*setParameter)(Effect*, int32_t, float);
    float (*getParameter)(Effect*, int32_t);
    int32_t programs, parameters, inputs, outputs, flags;
    intptr_t reserved1, reserved2;
    int32_t initialDelay, realQualities, offlineQualities;
    float ioRatio;
    void* object;
    void* user;
    int32_t uniqueID, version;
    Process replacing;
    void (*doubleReplacing)(Effect*, double**, double**, int32_t);
    char future[56];
};
struct Midi {
    int32_t type, byteSize, deltaFrames, flags, noteLength, noteOffset;
    uint8_t data[4];
    int8_t detune;
    uint8_t offVelocity, reserved1, reserved2;
};
struct Events { int32_t count; intptr_t reserved; Midi* events[2]; };
struct Time {
    double samplePos, sampleRate, nanoSeconds, ppqPos, tempo, barStart, cycleStart, cycleEnd;
    int32_t numerator, denominator, smpteOffset, smpteFrameRate, nextClock, flags;
};
static_assert(sizeof(void*) == 8 && sizeof(Effect) == 192);
static_assert(offsetof(Effect, dispatcher) == 8 && offsetof(Effect, replacing) == 120);
static_assert(offsetof(Effect, inputs) == 48 && offsetof(Effect, uniqueID) == 112);
static_assert(sizeof(Midi) == 32 && offsetof(Midi, data) == 24);
static_assert(offsetof(Events, events) == 16 && sizeof(Time) == 88);

static void require(bool ok, const char* reason) { if (!ok) throw std::runtime_error(reason); }
static Time transport{};
static int32_t blockSize = 512;
static std::array<std::atomic<uint64_t>, 256> callbackCounts{};
static std::atomic<uint64_t> otherCallbacks{0};
static std::mutex transportMutex;
static intptr_t host(Effect*, int32_t opcode, int32_t, intptr_t, void* data, float) {
    if (opcode >= 0 && size_t(opcode) < callbackCounts.size()) ++callbackCounts[size_t(opcode)];
    else ++otherCallbacks;
    switch (opcode) {
        case 1: return 2400;
        case 7: {
            thread_local Time snapshot{};
            std::lock_guard<std::mutex> lock(transportMutex);
            snapshot = transport;
            return reinterpret_cast<intptr_t>(&snapshot);
        }
        case 16: return intptr_t(transport.sampleRate);
        case 17: return blockSize;
        case 22: return 1; // replacing
        case 23: return 4; // offline
        case 32: if (data) std::strcpy(static_cast<char*>(data), "Veggie Loops"); return data ? 1 : 0;
        case 33: if (data) std::strcpy(static_cast<char*>(data), "VL Reference Probe"); return data ? 1 : 0;
        case 34: return 1;
        case 37:
            if (!data) return 0;
            for (const char* capability : {"sendVstEvents", "sendVstMidiEvent"})
                if (std::strcmp(static_cast<const char*>(data), capability) == 0) return 1;
            return 0;
        case 38: return 1; // English
        default: return 0; // GUI, file selection, audio input and other callbacks unsupported
    }
}
struct Bundle {
    CFBundleRef value = nullptr;
    ~Bundle() { if (value) { CFBundleUnloadExecutable(value); CFRelease(value); } }
};
struct Instance {
    Effect* value = nullptr;
    bool opened = false, powered = false, started = false;
    ~Instance() {
        if (!value || !opened) return;
        if (started) value->dispatcher(value, 72, 0, 0, nullptr, 0);
        if (powered) value->dispatcher(value, 12, 0, 0, nullptr, 0);
        value->dispatcher(value, 1, 0, 0, nullptr, 0);
    }
};
static std::vector<char> chunk(Effect* effect) {
    void* data = nullptr;
    const intptr_t size = effect->dispatcher(effect, 23, 1, 0, &data, 0);
    require(size >= 0 && size <= 64 * 1024 * 1024, "Invalid state chunk size");
    if (size == 0) return {};
    require(data, "State chunk pointer missing");
    const auto* bytes = static_cast<const char*>(data);
    return {bytes, bytes + size};
}
static void save(const std::string& path, const std::vector<char>& bytes) {
    std::ofstream file(path, std::ios::binary);
    file.write(bytes.data(), std::streamsize(bytes.size()));
    require(bool(file), "State diagnostic write failed");
}
static std::vector<char> read(const char* path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    require(bool(file), "State input open failed");
    const auto length = file.tellg();
    require(length > 0 && length <= 64 * 1024 * 1024, "Invalid state input size");
    std::vector<char> bytes(static_cast<size_t>(length));
    file.seekg(0); file.read(bytes.data(), length);
    require(bool(file), "State input read failed");
    return bytes;
}
static int parsePositive(const char* text, int minimum, int maximum) {
    size_t used = 0; const auto value = std::stoll(text, &used);
    require(used == std::strlen(text) && value >= minimum && value <= maximum, "Invalid numeric argument");
    return int(value);
}

int main(int argc, char** argv) {
    std::cout << std::unitbuf;
    if (argc < 2 || argc > 6) {
        std::cerr << "usage: vst2_probe plugin.vst [private-prefix [input-state-or-dash [sample-rate [block-size]]]]\n";
        return 2;
    }
    @autoreleasepool {
        try {
            const int rate = argc >= 5 ? parsePositive(argv[4], 8000, 192000) : 48000;
            blockSize = argc >= 6 ? parsePositive(argv[5], 1, 8192) : 512;
            transport.sampleRate = rate; transport.tempo = 120; transport.numerator = transport.denominator = 4;
            transport.flags = (1 << 1) | (1 << 9) | (1 << 10) | (1 << 13);
            std::vector<char> inputState;
            if (argc >= 4 && std::strcmp(argv[3], "-") != 0) inputState = read(argv[3]);
            Bundle bundle;
            auto url = CFURLCreateFromFileSystemRepresentation(nullptr, reinterpret_cast<const UInt8*>(argv[1]), std::strlen(argv[1]), true);
            require(url, "Invalid bundle URL");
            bundle.value = CFBundleCreate(nullptr, url); CFRelease(url);
            require(bundle.value, "VST bundle not found");
            std::cout << "stage=load_bundle\n";
            require(CFBundleLoadExecutable(bundle.value), "VST bundle did not load");
            using Entry = Effect* (*)(Dispatch);
            Entry entry = nullptr;
            for (auto symbol : {CFSTR("VSTPluginMain"), CFSTR("main_macho")}) {
                entry = reinterpret_cast<Entry>(CFBundleGetFunctionPointerForName(bundle.value, symbol));
                if (entry) break;
            }
            require(entry, "VST entry missing");
            Instance instance;
            std::cout << "stage=create_instance\n";
            instance.value = entry(host);
            auto* effect = instance.value;
            require(effect && effect->magic == 0x56737450 && effect->dispatcher, "Invalid VST effect");
            effect->dispatcher(effect, 0, 0, 0, nullptr, 0); instance.opened = true;
            require(effect->inputs >= 0 && effect->inputs <= 64 && effect->outputs > 0 && effect->outputs <= 64,
                    "Unsupported channel count");
            require((effect->flags & (1 << 4)) && effect->replacing, "Replacing audio callback missing");
            effect->dispatcher(effect, 10, 0, 0, nullptr, float(rate));
            effect->dispatcher(effect, 11, 0, blockSize, nullptr, 0);
            std::cout << "stage=capture_state\n";
            intptr_t inputRestoreResult = 0, roundTripResult = 0;
            if (!inputState.empty()) inputRestoreResult = effect->dispatcher(effect, 24, 1, intptr_t(inputState.size()), inputState.data(), 0);
            const auto before = chunk(effect);
            if (!before.empty()) roundTripResult = effect->dispatcher(effect, 24, 1, intptr_t(before.size()), const_cast<char*>(before.data()), 0);
            const auto after = chunk(effect);
            const std::string prefix = argc >= 3 ? argv[2] : "";
            if (!prefix.empty()) { save(prefix + "-before.bin", before); save(prefix + "-after.bin", after); }
            std::cout << "factory=true id=" << effect->uniqueID << " version=" << effect->version
                      << " inputs=" << effect->inputs << " outputs=" << effect->outputs
                      << " parameters=" << effect->parameters << " state_bytes=" << before.size()
                      << " state_bytes_equal=" << (before == after)
                      << " input_restore_return=" << inputRestoreResult << " roundtrip_restore_return=" << roundTripResult
                      << " state_semantics_verified=false\n";
            std::vector<std::vector<float>> input(size_t(effect->inputs), std::vector<float>(size_t(blockSize)));
            std::vector<std::vector<float>> output(size_t(effect->outputs), std::vector<float>(size_t(blockSize)));
            std::vector<float*> inputPointers, outputPointers;
            for (auto& channel : input) inputPointers.push_back(channel.data());
            for (auto& channel : output) outputPointers.push_back(channel.data());
            std::ofstream audio;
            if (!prefix.empty()) { audio.open(prefix + "-audio.f32", std::ios::binary); require(bool(audio), "Audio diagnostic open failed"); }
            effect->dispatcher(effect, 12, 0, 1, nullptr, 0); instance.powered = true;
            effect->dispatcher(effect, 71, 0, 0, nullptr, 0); instance.started = true;
            const int blocks = (rate * 2 + blockSize - 1) / blockSize;
            const int offBlock = blocks / 2;
            double peak = 0, energy = 0;
            for (int block = 0; block < blocks; ++block) {
                {
                    std::lock_guard<std::mutex> lock(transportMutex);
                    transport.samplePos = double(block) * blockSize;
                    transport.ppqPos = transport.samplePos * transport.tempo / (60 * rate);
                }
                if (block == 0 || block == offBlock) {
                    Midi note{}; note.type = 1; note.byteSize = sizeof(note);
                    note.data[0] = block == 0 ? 0x90 : 0x80; note.data[1] = 60; note.data[2] = block == 0 ? 100 : 0;
                    Events events{}; events.count = 1; events.events[0] = &note;
                    effect->dispatcher(effect, 25, 0, 0, &events, 0);
                }
                for (auto& channel : output) std::fill(channel.begin(), channel.end(), 0);
                effect->replacing(effect, inputPointers.data(), outputPointers.data(), blockSize);
                for (int frame = 0; frame < blockSize; ++frame) for (const auto& channel : output) {
                    const float sample = channel[size_t(frame)];
                    require(std::isfinite(sample), "Nonfinite audio sample");
                    peak = std::max(peak, double(std::abs(sample))); energy += double(sample) * sample;
                    if (audio.is_open()) audio.write(reinterpret_cast<const char*>(&sample), sizeof(sample));
                }
            }
            if (audio.is_open()) require(bool(audio), "Audio diagnostic write failed");
            require(peak > 0.001 && energy > 0.001, "MIDI produced silent output");
            std::cout << "native_processing=true sample_rate=" << rate << " block_size=" << blockSize
                      << " frames=" << blocks * blockSize << " peak=" << peak << " callback_opcodes=";
            for (size_t opcode = 0; opcode < callbackCounts.size(); ++opcode) {
                const auto count = callbackCounts[opcode].load();
                if (count) std::cout << opcode << ':' << count << ',';
            }
            std::cout << "other:" << otherCallbacks.load();
            std::cout << "\nall_components_recompiled=false\n";
            return 0;
        } catch (const std::exception& error) {
            std::cerr << "verification_failed: " << error.what() << '\n'; return 1;
        }
    }
}
