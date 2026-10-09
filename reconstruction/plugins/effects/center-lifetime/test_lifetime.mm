#if !defined(__APPLE__) || !defined(__aarch64__)
#error This source-only lifetime fixture is restricted to macOS arm64.
#endif
#import <Cocoa/Cocoa.h>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <stdexcept>
#include <thread>

namespace {
std::array<void *, 4> watched{};
std::array<unsigned, 4> frees{};
int allocationBudget = -1;
void *failureAllocation = nullptr;
unsigned failureAllocations = 0, failureFrees = 0;
#if defined(VL_CENTER_APPKIT_EDITOR)
unsigned editorCleanupEntries = 0;
#endif
}
void *operator new(std::size_t n) {
  if (allocationBudget == 0)
    throw std::bad_alloc();
  const bool injection = allocationBudget > 0;
  if (injection)
    --allocationBudget;
  if (void *p = std::malloc(n ? n : 1)) {
    if (injection) {
      failureAllocation = p;
      ++failureAllocations;
    }
    return p;
  }
  throw std::bad_alloc();
}
void *operator new(std::size_t n, const std::nothrow_t &) noexcept {
  try { return ::operator new(n); } catch (...) { return nullptr; }
}
void operator delete(void *p) noexcept {
  if (p) {
    for (std::size_t i = 0; i < watched.size(); ++i)
      if (watched[i] == p)
        ++frees[i];
    if (p == failureAllocation)
      ++failureFrees;
  }
  std::free(p);
}
void operator delete(void *p, const std::nothrow_t &) noexcept { ::operator delete(p); }
void operator delete(void *p, std::size_t) noexcept { ::operator delete(p); }

#if defined(VL_TEST_CENTER_EDITOR_VARIANT)
#include "center_native_editor_candidate.cpp"
#else
#include "center_native_abi.cpp"
#endif

#if defined(VL_CENTER_APPKIT_EDITOR)
// Only own source instrumentation: retain the complete, unchanged public
// editor body and observe calls through a renamed test-only cleanup symbol.
// Installed code and callback tables are never imported/replaced here.
#define vl_center_editor_destroy vl_test_center_editor_destroy_real
#include "center_editor.mm"
#undef vl_center_editor_destroy
extern "C" int vl_center_editor_destroy(void *editor) {
  ++editorCleanupEntries;
  return vl_test_center_editor_destroy_real(editor);
}
#endif

namespace {
using namespace veggie_loops::center::native;
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
struct NumericalSnapshot {
  std::array<uint8_t, 8> raw{};
  std::array<double, 4> filter{};
};
NumericalSnapshot snapshot(Plugin *p) {
  NumericalSnapshot s;
  require(vl_center_save_state(object(p).numerical, s.raw.data(), s.raw.size()) &&
              vl_center_get_filter_state(object(p).numerical, s.filter.data()),
          "Live numerical snapshot failed");
  return s;
}
bool same(const NumericalSnapshot &a, const NumericalSnapshot &b) {
  return a.raw == b.raw && !std::memcmp(a.filter.data(), b.filter.data(), sizeof a.filter);
}
std::array<float, 64> input() {
  std::array<float, 64> data{};
  for (size_t i = 0; i < 32; ++i) {
    data[2 * i] = .125f + float(i) * .0009765625f;
    data[2 * i + 1] = -.25f + float(i) * .001953125f;
  }
  return data;
}
void renderPeer(Plugin *p, VLCenterPlugin *reference) {
  const auto in = input();
  std::array<float, 68> actual{}, expected{};
  actual.fill(123.25f); expected.fill(123.25f);
  p->functions->effect(p, in.data(), actual.data() + 2, 32);
  require(vl_center_render(reference, in.data(), expected.data() + 2, 32),
          "Reference render failed");
  require(!std::memcmp(actual.data(), expected.data(), sizeof actual),
          "Peer numerical render or nonzero guards changed");
}
#if defined(VL_CENTER_APPKIT_EDITOR)
void retainedViewActions(VLCenterEditorView *view) {
  require(view && view.numerical == nullptr && view.toggle.target == nil &&
              view.host.context == nullptr && !view.host.lock && !view.host.unlock &&
              !view.host.changed && !view.host.hint,
          "Detached retained view still owns live numerical or context access");
  [view refresh];
  [view change:view.toggle];
  vl_center_editor_hint((__bridge void *)view, 0, 1);
}
#endif
} // namespace

int main() {
  @autoreleasepool {
    try {
      [NSApplication sharedApplication];
      // Prime only own shared metadata before deterministic allocation faults.
      Plugin *prime = CreatePlugInstance(nullptr, 0);
      require(prime, "Source factory prime failed");
      prime->functions->destroy(prime);
      unsigned allocationFailures = 0;
      for (int budget : {0, 1}) {
        failureAllocation = nullptr; failureAllocations = failureFrees = 0;
        allocationBudget = budget;
        Plugin *p = CreatePlugInstance(nullptr, 0);
        allocationBudget = -1;
        require(!p && failureAllocations == unsigned(budget) &&
                    failureFrees == unsigned(budget),
                "Source factory failure leaked allocated storage");
        failureAllocation = nullptr; ++allocationFailures;
      }
      // Defensive null lifetime calls are source-only behavior.
      functions.destroy(nullptr);
      functions.completeDestructor(nullptr);
      functions.deletingDestructor(nullptr);
      unsigned pairs = 0, refusals = 0, attached = 0, completed = 0;
      unsigned deleted = 0, ordinary = 0, retainedActions = 0;
      for (int iteration = 0; iteration < 4; ++iteration)
        for (int route = 0; route < 3; ++route) {
          watched = {}; frees = {};
          auto *p = CreatePlugInstance(nullptr, INT64_C(0x1234567812345678));
          auto *peer = CreatePlugInstance(nullptr, -INT64_C(0x11223344556677));
          require(p && peer && p != peer && object(p).numerical != object(peer).numerical,
                  "Two live factories must own distinct resources");
          auto *reference = vl_center_create(); require(reference, "Reference factory failed");
          watched = {p, object(p).numerical, peer, object(peer).numerical};
          p->mono = -7654321; peer->mono = 0x55667788;
          p->functions->parameter(p, 0, iteration % 2, 1);
          peer->functions->parameter(peer, 0, 1, 1);
          const int rate = 16000 + iteration * 16000;
          peer->functions->dispatch(peer, 4, 0, rate);
          require(vl_center_sample_rate(reference, rate) && vl_center_resume(reference),
                  "Reference context failed");
          peer->functions->dispatch(peer, 2, 0, 0);
          renderPeer(peer, reference);
          const auto peerState = snapshot(peer), selectedState = snapshot(p);
          const auto information = *peer->info;
          std::array<std::byte, sizeof(Instance)> peerBefore{};
          std::memcpy(peerBefore.data(), peer, peerBefore.size());
          auto finish = route == 0 ? p->functions->completeDestructor :
                        route == 1 ? p->functions->deletingDestructor : p->functions->destroy;
#if defined(VL_CENTER_APPKIT_EDITOR)
          const auto refuse = [&] {
            std::array<std::byte, sizeof(Instance)> before{};
            std::memcpy(before.data(), p, before.size());
            const auto calls = editorCleanupEntries;
            std::thread worker([&] { finish(p); }); worker.join();
            require(editorCleanupEntries == calls,
                    "Worker lifetime entered editor cleanup");
            require(frees == std::array<unsigned, 4>{0, 0, 0, 0} &&
                        !std::memcmp(before.data(), p, before.size()) &&
                        same(selectedState, snapshot(p)),
                    "Worker lifetime refusal changed selected object ownership/state");
            ++refusals;
          };
          refuse(); // Before any optional editor allocation/attachment.
          auto *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, 260)];
          p->functions->dispatch(p, 0, 0,
              reinterpret_cast<intptr_t>((__bridge void *)parent));
          require(object(p).editor && parent.subviews.count == 1,
                  "Optional editor attachment failed");
          VLCenterEditorView *retained = (__bridge VLCenterEditorView *)object(p).editor;
          ++attached; refuse();
#else
          (void)selectedState;
#endif
          finish(p);
          require(frees[1] == 1 && frees[2] == 0 && frees[3] == 0,
                  "Selected numerical resource must be released exactly once");
          if (route == 0) {
            require(frees[0] == 0, "Complete lifetime must retain caller raw storage");
            ::operator delete(static_cast<void *>(p)); ++completed;
          } else if (route == 1) ++deleted;
          else ++ordinary;
          require(frees[0] == 1, "Deleting lifetime must release selected raw storage once");
          watched[0] = watched[1] = nullptr;
          require(!std::memcmp(peerBefore.data(), peer, peerBefore.size()) &&
                      !std::memcmp(&information, peer->info, sizeof information) &&
                      same(peerState, snapshot(peer)) && peer->mono == 0x55667788,
                  "Peer instance/metadata/filter/raw state changed on selected cleanup");
          renderPeer(peer, reference);
#if defined(VL_CENTER_APPKIT_EDITOR)
          require(parent.subviews.count == 0, "Successful lifetime left an attached editor");
          retainedViewActions(retained); ++retainedActions;
#endif
          peer->functions->destroy(peer);
          require(frees[2] == 1 && frees[3] == 1,
                  "Peer cleanup must release both resources exactly once");
          watched = {}; vl_center_destroy(reference); ++pairs;
        }
      std::cout << "{\"status\":\"passed_source_Center_lifetime_contract\","
        "\"pairs\":" << pairs << ",\"complete_caller_free\":" << completed <<
        ",\"deleting\":" << deleted << ",\"DestroyObject\":" << ordinary <<
        ",\"allocation_failures\":" << allocationFailures <<
        ",\"offmain_refusals\":" << refusals << ",\"attached_editors\":" << attached <<
        ",\"retained_view_actions\":" << retainedActions <<
        ",\"own_allocator_hooks\":true,\"original_images_loaded\":false,"
        "\"original_extra_destructor_equivalence\":false,\"full_plugin_equivalence\":false}\n";
      return 0;
    } catch (const std::exception &e) {
      allocationBudget = -1;
      std::cerr << e.what() << '\n'; return 1;
    }
  }
}
