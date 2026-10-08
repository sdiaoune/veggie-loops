// Original isolated AU instrument host. Registers a supplied bundle only in
// this process; does not install it or modify the system plugin registry.
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

static void require(bool ok, const char* reason) { if (!ok) throw std::runtime_error(reason); }
static void check(OSStatus status, const char* reason) {
    if (status != noErr) throw std::runtime_error(std::string(reason) + " status=" + std::to_string(status));
}
struct Bundle {
    CFBundleRef value = nullptr;
    ~Bundle() { if (value) { CFBundleUnloadExecutable(value); CFRelease(value); } }
};
struct Unit {
    AudioUnit value = nullptr;
    bool initialized = false;
    ~Unit() { if (value) { if (initialized) AudioUnitUninitialize(value); AudioComponentInstanceDispose(value); } }
};
struct Property {
    CFPropertyListRef value = nullptr;
    ~Property() { if (value) CFRelease(value); }
};
static CFStringRef stringValue(CFDictionaryRef dict, CFStringRef key) {
    auto value = CFDictionaryGetValue(dict, key);
    require(value && CFGetTypeID(value) == CFStringGetTypeID(), "Missing string in AU metadata");
    return static_cast<CFStringRef>(value);
}
static UInt32 fourcc(CFStringRef string) {
    char bytes[5]{};
    require(CFStringGetLength(string) == 4 && CFStringGetCString(string, bytes, 5, kCFStringEncodingASCII), "Invalid AU fourcc");
    return (UInt32(uint8_t(bytes[0])) << 24) | (UInt32(uint8_t(bytes[1])) << 16)
        | (UInt32(uint8_t(bytes[2])) << 8) | UInt32(uint8_t(bytes[3]));
}
static void save(const std::string& prefix, const char* suffix, CFPropertyListRef value) {
    if (prefix.empty()) return;
    auto bytes = CFPropertyListCreateData(nullptr, value, kCFPropertyListBinaryFormat_v1_0, 0, nullptr);
    require(bytes, "AU state serialization failed");
    std::ofstream output(prefix + suffix, std::ios::binary);
    output.write(reinterpret_cast<const char*>(CFDataGetBytePtr(bytes)), CFDataGetLength(bytes));
    CFRelease(bytes);
    require(static_cast<bool>(output), "AU state diagnostic write failed");
}

int main(int argc, char** argv) {
    std::cout << std::unitbuf;
    if (argc < 2 || argc > 3) { std::cerr << "usage: au_probe /path/to/plugin.component [private-diagnostic-prefix]\n"; return 2; }
    try {
        Bundle bundle;
        auto url = CFURLCreateFromFileSystemRepresentation(nullptr, reinterpret_cast<const UInt8*>(argv[1]), std::strlen(argv[1]), true);
        require(url, "Invalid bundle URL");
        bundle.value = CFBundleCreate(nullptr, url); CFRelease(url);
        require(bundle.value && CFBundleLoadExecutable(bundle.value), "AU bundle did not load");
        auto metadata = CFBundleGetInfoDictionary(bundle.value);
        require(metadata, "No AU bundle metadata");
        auto components = static_cast<CFArrayRef>(CFDictionaryGetValue(metadata, CFSTR("AudioComponents")));
        require(components && CFGetTypeID(components) == CFArrayGetTypeID() && CFArrayGetCount(components) == 1,
                "Probe currently requires one advertised AU component");
        auto info = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(components, 0));
        require(CFGetTypeID(info) == CFDictionaryGetTypeID(), "Invalid AU component metadata");
        AudioComponentDescription description{};
        description.componentType = fourcc(stringValue(info, CFSTR("type")));
        description.componentSubType = fourcc(stringValue(info, CFSTR("subtype")));
        description.componentManufacturer = fourcc(stringValue(info, CFSTR("manufacturer")));
        require(description.componentType == kAudioUnitType_MusicDevice, "Probe currently supports AU instruments only");
        SInt64 version = 0;
        auto versionObject = static_cast<CFNumberRef>(CFDictionaryGetValue(info, CFSTR("version")));
        require(versionObject && CFGetTypeID(versionObject) == CFNumberGetTypeID()
                && CFNumberGetValue(versionObject, kCFNumberSInt64Type, &version) && version >= 0 && version <= UINT32_MAX,
                "Invalid AU component version");
        auto factory = reinterpret_cast<AudioComponentFactoryFunction>(
            CFBundleGetFunctionPointerForName(bundle.value, stringValue(info, CFSTR("factoryFunction"))));
        require(factory, "Advertised AU factory missing");
        auto component = AudioComponentRegister(&description, stringValue(info, CFSTR("name")), UInt32(version), factory);
        require(component, "Private AU registration failed");
        Unit unit;
        check(AudioComponentInstanceNew(component, &unit.value), "AU construction failed");
        AudioStreamBasicDescription format{};
        format.mSampleRate = 48000; format.mFormatID = kAudioFormatLinearPCM;
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
        format.mChannelsPerFrame = 2; format.mFramesPerPacket = 1;
        format.mBytesPerFrame = 4; format.mBytesPerPacket = 4; format.mBitsPerChannel = 32;
        check(AudioUnitSetProperty(unit.value, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof(format)), "AU stereo format failed");
        UInt32 maximum = 512;
        check(AudioUnitSetProperty(unit.value, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximum, sizeof(maximum)), "AU maximum block failed");
        check(AudioUnitInitialize(unit.value), "AU initialize failed"); unit.initialized = true;
        Property before, after;
        UInt32 stateSize = sizeof(CFPropertyListRef);
        check(AudioUnitGetProperty(unit.value, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &before.value, &stateSize), "AU state export failed");
        require(before.value, "AU state export empty");
        const std::string prefix = argc == 3 ? argv[2] : "";
        save(prefix, "-before.plist", before.value);
        check(AudioUnitSetProperty(unit.value, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &before.value, sizeof(before.value)), "AU state restore failed");
        stateSize = sizeof(CFPropertyListRef);
        check(AudioUnitGetProperty(unit.value, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &after.value, &stateSize), "AU second state export failed");
        require(after.value, "AU second state empty"); save(prefix, "-after.plist", after.value);
        std::array<float,512> left{}, right{};
        struct { UInt32 count; AudioBuffer buffers[2]; } storage{};
        storage.count = 2;
        storage.buffers[0] = {1, UInt32(sizeof(left)), left.data()};
        storage.buffers[1] = {1, UInt32(sizeof(right)), right.data()};
        static_assert(offsetof(decltype(storage), buffers) == offsetof(AudioBufferList, mBuffers));
        double peak = 0, energy = 0;
        for (int block = 0; block < 188; ++block) {
            left.fill(0); right.fill(0);
            if (block == 0 || block == 94)
                check(MusicDeviceMIDIEvent(unit.value, block == 0 ? 0x90 : 0x80, 60, block == 0 ? 100 : 0, 0), "AU MIDI failed");
            AudioTimeStamp time{}; time.mFlags = kAudioTimeStampSampleTimeValid; time.mSampleTime = block * 512;
            AudioUnitRenderActionFlags flags = 0;
            check(AudioUnitRender(unit.value, &flags, &time, 0, 512, reinterpret_cast<AudioBufferList*>(&storage)), "AU render failed");
            for (auto* channel : {left.data(), right.data()}) for (int frame = 0; frame < 512; ++frame) {
                require(std::isfinite(channel[frame]), "AU nonfinite sample");
                peak = std::max(peak, double(std::abs(channel[frame]))); energy += double(channel[frame]) * channel[frame];
            }
        }
        require(peak > 0.001 && energy > 0.001, "AU MIDI produced silent output");
        std::cout << "native_processing=true sample_rate=48000 frames=96256 peak=" << peak
                  << " state_property_equal=" << bool(CFEqual(before.value, after.value)) << '\n';
        return 0;
    } catch (const std::exception& error) { std::cerr << "verification_failed: " << error.what() << '\n'; return 1; }
}
