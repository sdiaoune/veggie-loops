// Original isolated VST3 verification host. Build against a locally supplied SDK.
// This verifies loading and a narrow processing/state corpus, not full equivalence.
#include <CoreFoundation/CoreFoundation.h>
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivsthostapplication.h"
#include "pluginterfaces/vst/vstspeaker.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

using namespace Steinberg;
using namespace Steinberg::Vst;

static void require(bool ok, const char* what) { if (!ok) throw std::runtime_error(what); }
static bool iidIs(const TUID id, const FUID& target) { return std::memcmp(id, target.toTUID(), 16) == 0; }
struct Release { void operator()(FUnknown* p) const { if (p) p->release(); } };
template<class T> using Interface = std::unique_ptr<T, Release>;

struct ComponentLifetime {
    IComponent* component = nullptr;
    IAudioProcessor* processor = nullptr;
    bool initialized = false, active = false, processing = false;
    ~ComponentLifetime() {
        if (processor && processing) processor->setProcessing(false);
        if (component && active) component->setActive(false);
        if (processor) processor->release();
        if (component) {
            if (initialized) component->terminate();
            component->release();
        }
    }
};

struct BundleLifetime {
    CFBundleRef bundle = nullptr;
    bool (*exit)() = nullptr;
    bool entered = false;
    ~BundleLifetime() {
        if (entered && exit) exit();
        if (bundle) { CFBundleUnloadExecutable(bundle); CFRelease(bundle); }
    }
};

class Host final : public IHostApplication {
public:
    tresult PLUGIN_API queryInterface(const TUID id, void** out) override {
        if (!out) return kInvalidArgument;
        *out = nullptr;
        if (iidIs(id, IHostApplication::iid) || iidIs(id, FUnknown::iid)) { *out = this; addRef(); return kResultOk; }
        return kNoInterface;
    }
    uint32 PLUGIN_API addRef() override { return ++refs; }
    uint32 PLUGIN_API release() override { return refs > 1 ? --refs : 1; }
    tresult PLUGIN_API getName(String128 name) override {
        std::fill(name, name + 128, 0);
        const char* text = "VL Plugin Verification";
        for (int i = 0; text[i]; ++i) name[i] = text[i];
        return kResultOk;
    }
    tresult PLUGIN_API createInstance(TUID, TUID, void** out) override { if (out) *out = nullptr; return kNoInterface; }
private:
    uint32 refs = 1;
};

class Events final : public IEventList {
public:
    std::vector<Event> items;
    tresult PLUGIN_API queryInterface(const TUID id, void** out) override {
        if (!out) return kInvalidArgument;
        *out = nullptr;
        if (iidIs(id, IEventList::iid) || iidIs(id, FUnknown::iid)) { *out = this; return kResultOk; }
        return kNoInterface;
    }
    uint32 PLUGIN_API addRef() override { return 1; }
    uint32 PLUGIN_API release() override { return 1; }
    int32 PLUGIN_API getEventCount() override { return static_cast<int32>(items.size()); }
    tresult PLUGIN_API getEvent(int32 i, Event& event) override {
        if (i < 0 || static_cast<size_t>(i) >= items.size()) return kInvalidArgument;
        event = items[i]; return kResultOk;
    }
    tresult PLUGIN_API addEvent(Event& event) override { items.push_back(event); return kResultOk; }
};

class Stream final : public IBStream {
public:
    std::vector<unsigned char> bytes;
    int64 position = 0;
    tresult PLUGIN_API queryInterface(const TUID id, void** out) override {
        if (!out) return kInvalidArgument;
        *out = nullptr;
        if (iidIs(id, IBStream::iid) || iidIs(id, FUnknown::iid)) { *out = this; return kResultOk; }
        return kNoInterface;
    }
    uint32 PLUGIN_API addRef() override { return 1; }
    uint32 PLUGIN_API release() override { return 1; }
    tresult PLUGIN_API read(void* data, int32 count, int32* done) override {
        if (done) *done = 0;
        if (count < 0 || position < 0 || (!data && count)) return kInvalidArgument;
        const auto available = position < static_cast<int64>(bytes.size()) ? bytes.size() - position : 0;
        const auto length = std::min<size_t>(count, available);
        if (length) std::memcpy(data, bytes.data() + position, length);
        position += length; if (done) *done = static_cast<int32>(length);
        // A short read and EOF are successful reads, as in the SDK MemoryStream.
        // Returning kResultFalse here makes JUCE discard the final partial block.
        return kResultOk;
    }
    tresult PLUGIN_API write(void* data, int32 count, int32* done) override {
        if (done) *done = 0;
        if (count < 0 || position < 0 || (!data && count) || position + count > 64 * 1024 * 1024) return kInvalidArgument;
        if (position + count > static_cast<int64>(bytes.size())) bytes.resize(position + count);
        if (count) std::memcpy(bytes.data() + position, data, count);
        position += count; if (done) *done = count; return kResultOk;
    }
    tresult PLUGIN_API seek(int64 value, int32 mode, int64* result) override {
        int64 base = 0;
        if (mode == kIBSeekCur) base = position;
        else if (mode == kIBSeekEnd) base = static_cast<int64>(bytes.size());
        else if (mode != kIBSeekSet) return kInvalidArgument;
        constexpr int64 maximum = 64 * 1024 * 1024;
        if (value < -base || value > maximum - base) return kInvalidArgument;
        const int64 next = base + value;
        position = next; if (result) *result = next; return kResultOk;
    }
    tresult PLUGIN_API tell(int64* result) override { if (!result) return kInvalidArgument; *result = position; return kResultOk; }
};

static void dumpState(const std::string& prefix, const char* suffix, const Stream& stream) {
    if (prefix.empty()) return;
    std::ofstream file(prefix + suffix, std::ios::binary);
    require(static_cast<bool>(file), "State diagnostic file open failed");
    file.write(reinterpret_cast<const char*>(stream.bytes.data()), stream.bytes.size());
    require(static_cast<bool>(file), "State diagnostic file write failed");
}

static void probe(IPluginFactory* factory, const std::string& prefix, const std::string& inputState) {
    const auto count = factory->countClasses();
    require(count > 0 && count <= 256, "Invalid factory class count");
    std::cout << "factory_classes=" << count << '\n';
    bool processed = false;
    for (int32 index = 0; index < count; ++index) {
        PClassInfo info{};
        require(factory->getClassInfo(index, &info) == kResultOk, "getClassInfo failed");
        std::cout << "class=" << info.name << " category=" << info.category << '\n';
        if (std::strcmp(info.category, kVstAudioEffectClass) != 0) continue;
        Host host;
        ComponentLifetime lifetime;
        require(factory->createInstance(info.cid, IComponent::iid, reinterpret_cast<void**>(&lifetime.component)) == kResultOk && lifetime.component, "createInstance failed");
        auto* component = lifetime.component;
        require(component->initialize(&host) == kResultOk, "initialize failed");
        lifetime.initialized = true;
        require(component->queryInterface(IAudioProcessor::iid, reinterpret_cast<void**>(&lifetime.processor)) == kResultOk && lifetime.processor, "No audio processor");
        auto* processor = lifetime.processor;
        const auto inputCount = component->getBusCount(kAudio, kInput);
        const auto outputCount = component->getBusCount(kAudio, kOutput);
        require(inputCount == 0 && outputCount == 1, "Probe currently supports a zero-input stereo instrument only");
        SpeakerArrangement stereo = SpeakerArr::kStereo;
        require(processor->setBusArrangements(nullptr, 0, &stereo, 1) == kResultOk, "Stereo arrangement failed");
        require(component->activateBus(kAudio, kOutput, 0, true) == kResultOk, "Audio bus activation failed");
        require(component->getBusCount(kEvent, kInput) > 0, "Instrument lacks event input");
        require(component->activateBus(kEvent, kInput, 0, true) == kResultOk, "Event bus activation failed");
        ProcessSetup setup{}; setup.processMode = kOffline; setup.symbolicSampleSize = kSample32;
        setup.maxSamplesPerBlock = 512; setup.sampleRate = 48000;
        require(processor->setupProcessing(setup) == kResultOk, "setupProcessing failed");
        if (!inputState.empty()) {
            std::ifstream input(inputState, std::ios::binary | std::ios::ate);
            require(static_cast<bool>(input), "Input state file missing");
            const auto size = input.tellg();
            require(size > 0 && size <= 64 * 1024 * 1024, "Input state size invalid");
            Stream supplied; supplied.bytes.resize(static_cast<size_t>(size));
            input.seekg(0); input.read(reinterpret_cast<char*>(supplied.bytes.data()), size);
            require(static_cast<bool>(input), "Input state read failed");
            require(component->setState(&supplied) == kResultOk, "Input state restore failed");
        }
        Stream before;
        require(component->getState(&before) == kResultOk && !before.bytes.empty(), "State export failed");
        dumpState(prefix, "-before.bin", before);
        std::cout << "state_export_bytes=" << before.bytes.size() << '\n';
        before.position = 0;
        require(component->setState(&before) == kResultOk, "State restoration failed");
        Stream after;
        require(component->getState(&after) == kResultOk, "Second state export failed");
        dumpState(prefix, "-after.bin", after);
        const bool identicalState = before.bytes == after.bytes;
        require(component->setActive(true) == kResultOk, "setActive failed");
        lifetime.active = true;
        require(processor->setProcessing(true) == kResultOk, "setProcessing failed");
        lifetime.processing = true;
        std::array<float, 512> left{}, right{};
        float* channels[] = {left.data(), right.data()};
        AudioBusBuffers output{}; output.numChannels = 2; output.channelBuffers32 = channels;
        ProcessData data{}; data.processMode = kOffline; data.symbolicSampleSize = kSample32;
        data.numSamples = 512; data.numInputs = 0; data.numOutputs = 1; data.outputs = &output;
        Events events; data.inputEvents = &events;
        double peak = 0, energy = 0;
        std::vector<float> rendered; rendered.reserve(188 * 512 * 2);
        for (int block = 0; block < 188; ++block) {
            left.fill(0); right.fill(0); events.items.clear(); output.silenceFlags = 0;
            if (block == 0 || block == 94) {
                Event e{}; e.busIndex = 0; e.type = block == 0 ? Event::kNoteOnEvent : Event::kNoteOffEvent;
                if (block == 0) { e.noteOn.channel = 0; e.noteOn.pitch = 60; e.noteOn.velocity = 0.8f; e.noteOn.noteId = 1; }
                else { e.noteOff.channel = 0; e.noteOff.pitch = 60; e.noteOff.noteId = 1; }
                events.items.push_back(e);
            }
            require(processor->process(data) == kResultOk, "process failed");
            for (auto* channel : channels) for (int frame = 0; frame < 512; ++frame) {
                require(std::isfinite(channel[frame]), "Nonfinite sample");
                peak = std::max(peak, static_cast<double>(std::abs(channel[frame])));
                energy += static_cast<double>(channel[frame]) * channel[frame];
            }
            for (int frame = 0; frame < 512; ++frame) {
                rendered.push_back(left[frame]); rendered.push_back(right[frame]);
            }
        }
        if (!prefix.empty()) {
            std::ofstream audio(prefix + "-audio.f32", std::ios::binary);
            audio.write(reinterpret_cast<const char*>(rendered.data()), rendered.size() * sizeof(float));
            require(static_cast<bool>(audio), "Audio diagnostic write failed");
        }
        require(peak > 0.001 && energy > 0.001, "MIDI produced silent output");
        std::cout << "native_processing=true sample_rate=48000 frames=96256 peak=" << peak
                  << " state_bytes=" << after.bytes.size() << " state_roundtrip=" << identicalState << '\n';
        // Byte identity is a metric. Persistent state semantics require a
        // format-specific validator of the optional diagnostic snapshots.
        processed = true;
    }
    require(processed, "No supported instrument class processed");
}

int main(int argc, char** argv) {
    std::cout << std::unitbuf;
    if (argc < 2 || argc > 4) { std::cerr << "usage: vst3_probe /path/to/plugin.vst3 [private-diagnostic-prefix [input-state]]\n"; return 2; }
    try {
        auto url = CFURLCreateFromFileSystemRepresentation(nullptr, reinterpret_cast<const UInt8*>(argv[1]), std::strlen(argv[1]), true);
        require(url, "Invalid bundle URL");
        BundleLifetime module;
        module.bundle = CFBundleCreate(nullptr, url); CFRelease(url);
        auto bundle = module.bundle; require(bundle, "Invalid plugin bundle");
        require(CFBundleLoadExecutable(bundle), "Plugin executable did not load");
        auto entry = reinterpret_cast<bool (*)(CFBundleRef)>(CFBundleGetFunctionPointerForName(bundle, CFSTR("bundleEntry")));
        module.exit = reinterpret_cast<bool (*)()>(CFBundleGetFunctionPointerForName(bundle, CFSTR("bundleExit")));
        if (entry) { require(entry(bundle), "bundleEntry failed"); module.entered = true; }
        auto getFactory = reinterpret_cast<IPluginFactory* (*)()>(CFBundleGetFunctionPointerForName(bundle, CFSTR("GetPluginFactory")));
        require(getFactory, "Missing GetPluginFactory");
        auto factory = getFactory(); require(factory, "Null plugin factory");
        { Interface<IPluginFactory> factoryRef(factory); probe(factory, argc >= 3 ? argv[2] : "", argc == 4 ? argv[3] : ""); }
        if (module.entered && module.exit) {
            const bool exited = module.exit(); module.entered = false;
            require(exited, "bundleExit failed");
        }
        return 0;
    } catch (const std::exception& error) { std::cerr << "verification_failed: " << error.what() << '\n'; return 1; }
}
