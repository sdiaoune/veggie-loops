#include "soft_clipper_editor.h"
#import <Cocoa/Cocoa.h>
#include <array>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
namespace {
void require(bool v) {
  if (!v)
    throw std::runtime_error("Soft Clipper editor check failed");
}
struct Host {
  bool locked = false;
  int locks = 0, unlocks = 0, changes = 0, hints = 0;
  int32_t index = -1, value = 0;
  std::string hint;
};
void lock(void *c) {
  auto &h = *static_cast<Host *>(c);
  require(!h.locked);
  h.locked = true;
  ++h.locks;
}
void unlock(void *c) {
  auto &h = *static_cast<Host *>(c);
  require(h.locked);
  h.locked = false;
  ++h.unlocks;
}
void changed(void *c, int32_t i, int32_t value) {
  auto &h = *static_cast<Host *>(c);
  require(!h.locked);
  h.index = i;
  h.value = value;
  ++h.changes;
}
void hint(void *c, const char *text) {
  auto &h = *static_cast<Host *>(c);
  require(!h.locked && text);
  h.hint = text;
  ++h.hints;
}
bool contains(NSView *view, NSString *text) {
  for (NSView *c in view.subviews)
    if ([c isKindOfClass:NSTextField.class] &&
        [((NSTextField *)c).stringValue isEqualToString:text])
      return true;
  return false;
}
} // namespace
int main(int argc, char **argv) {
  @autoreleasepool {
    try {
      [NSApplication sharedApplication];
      auto *p = vl_soft_clipper_create();
      require(p);
      Host host;
      VLSoftClipperEditorHost callbacks{&host, lock, unlock, changed, hint};
      auto bad = callbacks;
      bad.unlock = nullptr;
      require(!vl_soft_clipper_editor_create(p, &bad));
      void *editor = vl_soft_clipper_editor_create(p, &callbacks);
      require(editor);
      auto *view = (__bridge NSView *)editor;
      auto *parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
      vl_soft_clipper_editor_attach(editor, (__bridge void *)parent);
      require(view.superview == parent && contains(view, @"78.1%") &&
              contains(view, @"1.00×"));
      std::array<NSSlider *, 2> sliders{};
      std::array<NSLevelIndicator *, 2> meters{};
      size_t n = 0;
      for (NSView *c in view.subviews) {
        if ([c isKindOfClass:NSSlider.class])
          sliders[size_t(((NSSlider *)c).tag)] = (NSSlider *)c;
        if ([c isKindOfClass:NSLevelIndicator.class])
          meters[n++] = (NSLevelIndicator *)c;
      }
      require(sliders[0] && sliders[1] && n == 2);
      size_t displays = 0;
      for (int32_t index = 0; index < 2; ++index) {
        const int32_t minimum = index == 0 ? 1 : 0,
                      maximum = index == 0 ? 127 : 160;
        require(sliders[size_t(index)].minValue == minimum &&
                sliders[size_t(index)].maxValue == maximum);
        for (int32_t value = minimum; value <= maximum; ++value) {
          int32_t result = 0;
          require(vl_soft_clipper_parameter(p, index, value, 1, &result));
          vl_soft_clipper_editor_refresh(editor);
          require(sliders[size_t(index)].integerValue == value);
          ++displays;
        }
        sliders[size_t(index)].integerValue = index == 0 ? 27 : 96;
        [sliders[size_t(index)] sendAction:sliders[size_t(index)].action
                                        to:sliders[size_t(index)].target];
        int32_t raw = 0;
        require(host.index == index && host.value == (index == 0 ? 27 : 96) &&
                vl_soft_clipper_parameter(p, index, 0, 2, &raw) &&
                raw == host.value);
      }
      require(contains(view, @"21.1%") && contains(view, @"0.50×"));
      std::array<float, 16> audio{}, output{};
      for (size_t i = 0; i < 8; ++i) {
        audio[2 * i] = .1f;
        audio[2 * i + 1] = -.15f;
      }
      require(vl_soft_clipper_render(p, audio.data(), output.data(), 8));
      vl_soft_clipper_editor_refresh(editor);
      require(meters[0].doubleValue == double(.1f) &&
              meters[1].doubleValue == double(.15f));
      std::array<float, 2> peaks{};
      require(vl_soft_clipper_get_meters(p, peaks.data()) &&
              peaks == std::array<float, 2>{0, 0});
      for (size_t i = 0; i < 3; ++i) {
        audio[2 * i] = .1f;
        audio[2 * i + 1] = -.15f;
      }
      require(vl_soft_clipper_render(p, audio.data(), output.data(), 3));
      vl_soft_clipper_editor_refresh(editor);
      require(meters[0].doubleValue == double(.1f) &&
              meters[1].doubleValue == 0);
      const int locks = host.locks, hints = host.hints;
      void *workerEditor = editor;
      int destroyed = 1;
      std::thread worker([&] {
        workerEditor = vl_soft_clipper_editor_create(p, &callbacks);
        vl_soft_clipper_editor_refresh(editor);
        vl_soft_clipper_editor_hint(editor, 0, 27);
        vl_soft_clipper_editor_attach(editor, nullptr);
        destroyed = vl_soft_clipper_editor_destroy(editor);
      });
      worker.join();
      require(!workerEditor && destroyed == 0 && host.locks == locks &&
              host.hints == hints && view.superview == parent);
      if (argc == 2) {
        int32_t ignored = 0;
        vl_soft_clipper_parameter(p, 0, 100, 1, &ignored);
        vl_soft_clipper_parameter(p, 1, 128, 1, &ignored);
        vl_soft_clipper_editor_refresh(editor);
        NSBitmapImageRep *b =
            [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:b];
        require([[b representationUsingType:NSBitmapImageFileTypePNG
                                 properties:@{}]
            writeToFile:[NSString stringWithUTF8String:argv[1]]
             atomically:YES]);
      }
      vl_soft_clipper_editor_attach(editor, nullptr);
      require(view.superview == nil);
      vl_soft_clipper_editor_attach(editor, (__bridge void *)parent);
      require(vl_soft_clipper_editor_destroy(editor) &&
              parent.subviews.count == 0 && host.locks == host.unlocks);
      vl_soft_clipper_destroy(p);
      std::cout << "{\"status\":\"passed\",\"independently_written_appkit_"
                   "editor\":true,\"parameter_control_changes\":"
                << host.changes << ",\"automation_display_cases\":" << displays
                << ",\"meter_full_group_and_signed_tail_checked\":true,"
                   "\"notifications_after_unlock\":true,\"worker_ui_calls_"
                   "skipped\":true,\"off_main_destroy_preserves_view\":true,"
                   "\"native_editor_integration\":false}\n";
    } catch (const std::exception &e) {
      std::cerr << e.what() << '\n';
      return 1;
    }
  }
}
