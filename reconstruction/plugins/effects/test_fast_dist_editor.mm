#include "fast_dist_editor.h"
#import <Cocoa/Cocoa.h>
#include <array>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
namespace {
void require(bool v, const char *m) {
  if (!v)
    throw std::runtime_error(m);
}
struct Host {
  bool held = false;
  size_t locks = 0, unlocks = 0, changes = 0, hints = 0;
  int32_t index = -1, value = -1;
  std::string text;
};
void lock(void *p) {
  auto &h = *static_cast<Host *>(p);
  require(NSThread.isMainThread && !h.held, "Lock protocol");
  h.held = true;
  ++h.locks;
}
void unlock(void *p) {
  auto &h = *static_cast<Host *>(p);
  require(NSThread.isMainThread && h.held, "Unlock protocol");
  h.held = false;
  ++h.unlocks;
}
void changed(void *p, int32_t index, int32_t value) {
  auto &h = *static_cast<Host *>(p);
  require(NSThread.isMainThread && !h.held, "Change before unlock");
  h.index = index;
  h.value = value;
  ++h.changes;
}
void hint(void *p, const char *text) {
  auto &h = *static_cast<Host *>(p);
  require(NSThread.isMainThread && !h.held && text, "Hint before unlock");
  h.text = text;
  ++h.hints;
}
constexpr std::array<int32_t, 5> minimum{64, 1, 0, 0, 0},
    maximum{192, 10, 1, 128, 128};
constexpr std::array<const char *, 5> names{"Pre Gain", "Threshold", "Type",
                                            "Mix", "Post Gain"};
std::string hintText(int32_t index, int32_t value) {
  char text[64];
  std::snprintf(text, sizeof(text), "%s: %d", names[index], value);
  return text;
}
std::array<uint8_t, 20> state(VLFastDistPlugin *p) {
  std::array<uint8_t, 20> b{};
  require(vl_fast_dist_save_state(p, b.data(), b.size()), "State save");
  return b;
}
std::array<float, 3> coefficients(VLFastDistPlugin *p) {
  std::array<float, 3> c{};
  require(vl_fast_dist_get_coefficients(p, c.data()), "Coefficient getter");
  return c;
}
std::array<NSControl *, 5> controls(NSView *view) {
  std::array<NSControl *, 5> c{};
  for (NSView *v in view.subviews)
    if ([v isKindOfClass:NSSlider.class] || [v isKindOfClass:NSButton.class]) {
      auto *x = (NSControl *)v;
      require(x.tag >= 0 && x.tag < 5 && !c[x.tag], "Control identity");
      c[x.tag] = x;
    }
  for (auto *x : c)
    require(x, "Missing control");
  return c;
}
void display(NSView *view, const std::array<NSControl *, 5> &c,
             VLFastDistPlugin *p) {
  for (int32_t i = 0; i < 5; ++i) {
    int32_t raw = 0;
    require(vl_fast_dist_parameter(p, i, 0, 2, &raw), "Getter");
    require(i == 2 ? (((NSButton *)c[i]).state ==
                      (raw ? NSControlStateValueOn : NSControlStateValueOff))
                   : c[i].integerValue == raw,
            "Control display");
    bool found = false;
    for (NSView *v in view.subviews)
      if ([v isKindOfClass:NSTextField.class] && v.tag == i &&
          [((NSTextField *)v).stringValue
              isEqualToString:[NSString stringWithFormat:@"%d", raw]])
        found = true;
    require(found, "Raw display label");
  }
}
} // namespace
int main(int argc, char **argv) {
  @autoreleasepool {
    try {
      [NSApplication sharedApplication];
      auto *p = vl_fast_dist_create(0);
      require(p, "Numerical create");
      Host host;
      const VLFastDistEditorHost callbacks{&host, lock, unlock, changed, hint};
      auto invalid = callbacks;
      invalid.unlock = nullptr;
      require(!vl_fast_dist_editor_create(p, &invalid) &&
                  !vl_fast_dist_editor_create(nullptr, &callbacks),
              "Invalid editor create");
      void *e = vl_fast_dist_editor_create(p, &callbacks);
      require(e, "Editor create");
      auto *view = (__bridge NSView *)e;
      auto *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 400)];
      vl_fast_dist_editor_attach(e, (__bridge void *)parent);
      require(view.superview == parent, "Attach");
      const auto widgets = controls(view);
      display(view, widgets, p);
      size_t automation = 0, actions = 0, preservation = 0;
      for (int32_t i = 0; i < 5; ++i)
        for (int32_t raw = minimum[i]; raw <= maximum[i]; ++raw) {
          int32_t result = 0;
          require(vl_fast_dist_parameter(p, i, raw, 1, &result),
                  "Automation update");
          const auto before = state(p);
          const auto beforeCoefficients = coefficients(p);
          vl_fast_dist_editor_refresh(e);
          display(view, widgets, p);
          require(state(p) == before &&
                      std::memcmp(coefficients(p).data(),
                                  beforeCoefficients.data(),
                                  sizeof(beforeCoefficients)) == 0,
                  "Refresh mutated parameters/coefficients");
          ++automation;
          ++preservation;
          const int32_t next = minimum[i] + (raw - minimum[i] + 1) %
                                                (maximum[i] - minimum[i] + 1);
          if (i == 2)
            ((NSButton *)widgets[i]).state =
                next ? NSControlStateValueOn : NSControlStateValueOff;
          else
            widgets[i].integerValue = next;
          [widgets[i] sendAction:widgets[i].action to:widgets[i].target];
          require(host.index == i && host.value == next &&
                      host.text == hintText(i, next) &&
                      vl_fast_dist_parameter(p, i, 0, 2, &result) &&
                      result == next,
                  "UI action/numerical/notification");
          display(view, widgets, p);
          ++actions;
        }
      constexpr std::array<int32_t, 5> defaults{128, 10, 0, 128, 128};
      for (int32_t i = 0; i < 5; ++i) {
        int32_t ignored = 0;
        require(vl_fast_dist_parameter(p, i, defaults[i], 1, &ignored),
                "Restore defaults");
      }
      std::array<float, 16> input{.5f,   -.25f,  .333f, -.017f, 0,    -0.0f,
                                  1.0f,  -1.0f,  .2f,   -.7f,   .13f, -.031f,
                                  .003f, -.003f, .8f,   -.8f},
          beforeOutput{}, afterOutput{};
      size_t qualityCases = 0;
      std::array<std::array<float, 16>, 2> qualityOutputs{};
      for (int32_t q : {0, 1}) {
        require(
            vl_fast_dist_quality(p, q) &&
                vl_fast_dist_render(p, input.data(), beforeOutput.data(), 8),
            "Quality setup/render");
        const auto before = state(p);
        const auto beforeCoefficients = coefficients(p);
        for (size_t iteration = 0; iteration < 32; ++iteration) {
          vl_fast_dist_editor_attach(e, nullptr);
          vl_fast_dist_editor_attach(e, (__bridge void *)parent);
          vl_fast_dist_editor_refresh(e);
          require(vl_fast_dist_restore_state(p, before.data(), before.size()),
                  "State restore");
        }
        require(vl_fast_dist_render(p, input.data(), afterOutput.data(), 8) &&
                    std::memcmp(beforeOutput.data(), afterOutput.data(),
                                sizeof(beforeOutput)) == 0 &&
                    state(p) == before &&
                    std::memcmp(coefficients(p).data(),
                                beforeCoefficients.data(),
                                sizeof(beforeCoefficients)) == 0,
                "GUI/state changed quality or DSP");
        qualityOutputs[q] = afterOutput;
        ++qualityCases;
      }
      require(std::memcmp(qualityOutputs[0].data(), qualityOutputs[1].data(),
                          sizeof(qualityOutputs[0])) != 0,
              "Quality preservation probe is not discriminating");
      const auto locksBefore = host.locks, hintsBefore = host.hints;
      int workerDestroy = 1;
      void *workerCreate = e;
      std::thread worker([&] {
        workerCreate = vl_fast_dist_editor_create(p, &callbacks);
        vl_fast_dist_editor_refresh(e);
        vl_fast_dist_editor_hint(e, 0, 128);
        vl_fast_dist_editor_attach(e, nullptr);
        workerDestroy = vl_fast_dist_editor_destroy(e);
      });
      worker.join();
      require(!workerCreate && !workerDestroy && host.locks == locksBefore &&
                  host.hints == hintsBefore && view.superview == parent,
              "Worker touched GUI/locks or freed view");
      vl_fast_dist_editor_hint(e, -1, 0);
      vl_fast_dist_editor_hint(e, 0, 63);
      vl_fast_dist_editor_hint(e, 5, 0);
      require(host.hints == hintsBefore, "Invalid hint accepted");
      for (int32_t i = 0; i < 5; ++i)
        vl_fast_dist_editor_hint(e, i, defaults[i]);
      require(host.hints == hintsBefore + 5, "Hints");
      if (argc == 2) {
        vl_fast_dist_editor_refresh(e);
        auto *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        require([[bitmap representationUsingType:NSBitmapImageFileTypePNG
                                      properties:@{}]
                    writeToFile:[NSString stringWithUTF8String:argv[1]]
                     atomically:YES],
                "Bitmap export");
      }
      vl_fast_dist_editor_attach(e, nullptr);
      require(!view.superview, "Detach");
      vl_fast_dist_editor_attach(e, (__bridge void *)parent);
      require(vl_fast_dist_editor_destroy(e) && parent.subviews.count == 0 &&
                  host.locks == host.unlocks && !host.held,
              "Main destruction/paired locks");
      vl_fast_dist_destroy(p);
      std::cout << "{\"status\":\"passed\",\"independently_written_appkit_"
                   "editor\":true,\"automation_display_cases\":"
                << automation << ",\"control_changes\":" << actions
                << ",\"parameter_coefficient_preservation_cases\":"
                << preservation
                << ",\"quality_preservation_cases\":" << qualityCases
                << ",\"notifications_after_unlock\":true,\"worker_ui_calls_"
                   "skipped\":true,\"off_main_destroy_preserves_view\":true,"
                   "\"full_plugin_equivalence\":false}\n";
    } catch (const std::exception &e) {
      std::cerr << e.what() << '\n';
      return 1;
    }
  }
}
