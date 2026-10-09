#include "center_editor.h"
#import <Cocoa/Cocoa.h>
#include <array>
#include <cstdio>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
namespace {
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
struct Host {
  bool locked = false;
  size_t locks = 0, unlocks = 0, changes = 0, hints = 0;
  int32_t index = -1, value = -1;
  std::string hint;
};
void lock(void *context) {
  auto &h = *static_cast<Host *>(context);
  require(NSThread.isMainThread && !h.locked, "Editor lock protocol");
  h.locked = true;
  ++h.locks;
}
void unlock(void *context) {
  auto &h = *static_cast<Host *>(context);
  require(NSThread.isMainThread && h.locked, "Editor unlock protocol");
  h.locked = false;
  ++h.unlocks;
}
void changed(void *context, int32_t index, int32_t value) {
  auto &h = *static_cast<Host *>(context);
  require(NSThread.isMainThread && !h.locked, "Change before unlock");
  h.index = index;
  h.value = value;
  ++h.changes;
}
void hint(void *context, const char *text) {
  auto &h = *static_cast<Host *>(context);
  require(NSThread.isMainThread && !h.locked && text, "Hint before unlock");
  h.hint = text;
  ++h.hints;
}
bool contains(NSView *view, NSString *text) {
  for (NSView *child in view.subviews)
    if ([child isKindOfClass:NSTextField.class] &&
        [((NSTextField *)child).stringValue isEqualToString:text])
      return true;
  return false;
}
void displays(NSView *view, const std::array<double, 4> &state) {
  char text[96];
  std::snprintf(text, sizeof(text), "Left: %+.4f", state[0]);
  require(contains(view, [NSString stringWithUTF8String:text]),
          "Left offset display differs from retained state");
  std::snprintf(text, sizeof(text), "Right: %+.4f", state[1]);
  require(contains(view, [NSString stringWithUTF8String:text]),
          "Right offset display differs from retained state");
}
} // namespace
int main(int argc, char **argv) {
  @autoreleasepool {
    try {
      [NSApplication sharedApplication];
      auto *p = vl_center_create();
      require(p, "Numerical allocation");
      Host host;
      const VLCenterEditorHost callbacks{&host, lock, unlock, changed, hint};
      auto unpaired = callbacks;
      unpaired.unlock = nullptr;
      require(!vl_center_editor_create(p, &unpaired) &&
                  !vl_center_editor_create(nullptr, &callbacks),
              "Invalid editor creation accepted");
      void *editor = vl_center_editor_create(p, &callbacks);
      require(editor, "Editor allocation");
      auto *view = (__bridge NSView *)editor;
      auto *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
      vl_center_editor_attach(editor, (__bridge void *)parent);
      require(view.superview == parent && contains(view, @"VL Center") &&
                  contains(view, @"Estimated offsets"),
              "Own view missing labels or attachment");
      NSButton *toggle = nil;
      for (NSView *child in view.subviews)
        if ([child isKindOfClass:NSButton.class])
          toggle = (NSButton *)child;
      require(toggle && toggle.state == NSControlStateValueOn,
              "Enable default display");
      size_t automationCases = 0, displayCases = 0;
      for (int32_t iteration = 0; iteration < 256; ++iteration) {
        const int32_t enabled = iteration % 2;
        int32_t result = -1;
        require(vl_center_parameter(p, 0, enabled, 1, &result),
                "Automation numerical update");
        vl_center_editor_refresh(editor);
        require(toggle.state ==
                    (enabled ? NSControlStateValueOn : NSControlStateValueOff),
                "Automation display");
        ++automationCases;
        toggle.state = enabled ? NSControlStateValueOff : NSControlStateValueOn;
        [toggle sendAction:toggle.action to:toggle.target];
        require(host.index == 0 && host.value == (enabled ^ 1) &&
                    vl_center_parameter(p, 0, 0, 2, &result) &&
                    result == (enabled ^ 1) &&
                    host.hint ==
                        (result ? "DC centering: on" : "DC centering: off"),
                "UI action numerical/notification mismatch");
      }
      int32_t result = 0;
      require(vl_center_parameter(p, 0, 1, 1, &result), "Enable for display");
      std::array<float, 2048> input{}, output{};
      std::array<double, 4> retained{};
      constexpr std::array<int32_t, 8> frames{0, 1, 3, 8, 17, 63, 257, 1024};
      constexpr std::array<int32_t, 4> rates{8000, 44100, 96000, 384000};
      for (int32_t rate : rates) {
        require(vl_center_sample_rate(p, rate), "Display sample rate");
        for (size_t sequence = 0; sequence < 16; ++sequence)
          for (int32_t count : frames) {
            for (int32_t n = 0; n < count; ++n) {
              input[size_t(n) * 2] = sequence % 2 ? .5f : -.25f;
              input[size_t(n) * 2 + 1] = sequence % 3 ? -.75f : .125f;
            }
            require(vl_center_render(p, input.data(), output.data(), count) &&
                        vl_center_get_filter_state(p, retained.data()),
                    "Display processing");
            vl_center_editor_refresh(editor);
            displays(view, retained);
            std::array<double, 4> afterRefresh{};
            require(vl_center_get_filter_state(p, afterRefresh.data()) &&
                        retained == afterRefresh,
                    "Refresh mutated retained history");
            ++displayCases;
          }
      }
      const auto beforeBypass = retained;
      toggle.state = NSControlStateValueOff;
      [toggle sendAction:toggle.action to:toggle.target];
      require(vl_center_render(p, input.data(), output.data(), 1024) &&
                  vl_center_get_filter_state(p, retained.data()) &&
                  retained == beforeBypass,
              "Bypass action changed retained history");
      vl_center_editor_refresh(editor);
      displays(view, retained);
      ++displayCases;
      require(vl_center_resume(p) &&
                  vl_center_get_filter_state(p, retained.data()) &&
                  retained == std::array<double, 4>{},
              "Reset history");
      vl_center_editor_refresh(editor);
      displays(view, retained);
      ++displayCases;
      const auto locksBefore = host.locks, hintsBefore = host.hints;
      void *workerEditor = editor;
      int workerDestroyed = 1;
      std::thread worker([&] {
        workerEditor = vl_center_editor_create(p, &callbacks);
        vl_center_editor_refresh(editor);
        vl_center_editor_hint(editor, 0, 1);
        vl_center_editor_attach(editor, nullptr);
        workerDestroyed = vl_center_editor_destroy(editor);
      });
      worker.join();
      require(!workerEditor && workerDestroyed == 0 &&
                  host.locks == locksBefore && host.hints == hintsBefore &&
                  view.superview == parent,
              "Worker UI entry touched main-owned view");
      vl_center_editor_hint(editor, 1, 1);
      vl_center_editor_hint(editor, 0, 2);
      require(host.hints == hintsBefore, "Invalid hint accepted");
      if (argc == 2) {
        toggle.state = NSControlStateValueOn;
        [toggle sendAction:toggle.action to:toggle.target];
        vl_center_editor_refresh(editor);
        NSBitmapImageRep *bitmap =
            [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        require([[bitmap representationUsingType:NSBitmapImageFileTypePNG
                                      properties:@{}]
                    writeToFile:[NSString stringWithUTF8String:argv[1]]
                     atomically:YES],
                "Bitmap export");
      }
      vl_center_editor_attach(editor, nullptr);
      require(view.superview == nil, "Detach");
      vl_center_editor_attach(editor, (__bridge void *)parent);
      require(vl_center_editor_destroy(editor) && parent.subviews.count == 0 &&
                  host.locks == host.unlocks && !host.locked,
              "Main destruction and locks");
      vl_center_destroy(p);
      std::cout << "{\"status\":\"passed\",\"independently_written_appkit_"
                   "editor\":true,"
                   "\"automation_display_cases\":"
                << automationCases
                << ",\"filter_display_cases\":" << displayCases
                << ",\"parameter_control_changes\":" << host.changes
                << ",\"refresh_preserves_history\":true,\"bypass_preserves_"
                   "history\":true,"
                   "\"notifications_after_unlock\":true,\"worker_ui_calls_"
                   "skipped\":true,"
                   "\"off_main_destroy_preserves_view\":true,\"native_editor_"
                   "integration\":false,"
                   "\"full_plugin_equivalence\":false}\n";
    } catch (const std::exception &e) {
      std::cerr << e.what() << '\n';
      return 1;
    }
  }
}
