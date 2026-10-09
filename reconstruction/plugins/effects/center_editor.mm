#include "center_editor.h"
#import <Cocoa/Cocoa.h>
#include <array>
#include <cstdio>
namespace {
void lock(const VLCenterEditorHost &h) {
  if (h.lock)
    h.lock(h.context);
}
void unlock(const VLCenterEditorHost &h) {
  if (h.unlock)
    h.unlock(h.context);
}
} // namespace
@interface VLCenterEditorView : NSView
@property(nonatomic) VLCenterPlugin *numerical;
@property(nonatomic) VLCenterEditorHost host;
@property(nonatomic, strong) NSButton *toggle;
@property(nonatomic, strong) NSTextField *left;
@property(nonatomic, strong) NSTextField *right;
- (void)refresh;
- (void)change:(id)sender;
@end
@implementation VLCenterEditorView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (!self)
    return nil;
  self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  self.wantsLayer = YES;
  self.layer.backgroundColor =
      [NSColor colorWithSRGBRed:.06 green:.10 blue:.08 alpha:1].CGColor;
  NSTextField *title = [NSTextField labelWithString:@"VL Center"];
  title.frame = NSMakeRect(20, 140, 350, 30);
  title.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
  [self addSubview:title];
  self.toggle = [NSButton checkboxWithTitle:@"Center DC offsets"
                                     target:self
                                     action:@selector(change:)];
  self.toggle.frame = NSMakeRect(20, 99, 350, 25);
  self.toggle.allowsMixedState = NO;
  [self addSubview:self.toggle];
  NSTextField *explain = [NSTextField labelWithString:@"Estimated offsets"];
  explain.frame = NSMakeRect(20, 66, 350, 18);
  explain.textColor = NSColor.secondaryLabelColor;
  [self addSubview:explain];
  self.left = [NSTextField labelWithString:@"Left: +0.0000"];
  self.right = [NSTextField labelWithString:@"Right: +0.0000"];
  self.left.frame = NSMakeRect(20, 34, 170, 22);
  self.right.frame = NSMakeRect(195, 34, 175, 22);
  for (NSTextField *t in @[ self.left, self.right ]) {
    t.font = [NSFont monospacedDigitSystemFontOfSize:13
                                              weight:NSFontWeightRegular];
    [self addSubview:t];
  }
  return self;
}
- (void)refresh {
  if (!NSThread.isMainThread || !self.numerical)
    return;
  const auto h = self.host;
  int32_t enabled = 0;
  std::array<double, 4> filter{};
  lock(h);
  const bool ok = vl_center_parameter(self.numerical, 0, 0, 2, &enabled) &&
                  vl_center_get_filter_state(self.numerical, filter.data());
  unlock(h);
  if (!ok)
    return;
  self.toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
  char text[96];
  std::snprintf(text, sizeof(text), "Left: %+.4f", filter[0]);
  self.left.stringValue = [NSString stringWithUTF8String:text];
  std::snprintf(text, sizeof(text), "Right: %+.4f", filter[1]);
  self.right.stringValue = [NSString stringWithUTF8String:text];
}
- (void)change:(id)sender {
  if (!NSThread.isMainThread || !self.numerical || sender != self.toggle)
    return;
  const auto h = self.host;
  int32_t result = 0;
  const int32_t value = self.toggle.state == NSControlStateValueOn ? 1 : 0;
  lock(h);
  const bool ok = vl_center_parameter(self.numerical, 0, value, 1, &result);
  unlock(h);
  if (!ok)
    return;
  if (h.changed)
    h.changed(h.context, 0, result);
  if (h.hint)
    h.hint(h.context, result ? "DC centering: on" : "DC centering: off");
  [self refresh];
}
@end
extern "C" int vl_center_editor_main_thread() { return NSThread.isMainThread; }
extern "C" void *vl_center_editor_create(VLCenterPlugin *p,
                                         const VLCenterEditorHost *h) {
  if (!NSThread.isMainThread || !p || (h && bool(h->lock) != bool(h->unlock)))
    return nullptr;
  auto *v =
      [[VLCenterEditorView alloc] initWithFrame:NSMakeRect(0, 0, 390, 190)];
  v.numerical = p;
  if (h)
    v.host = *h;
  [v refresh];
  return (__bridge_retained void *)v;
}
extern "C" void vl_center_editor_attach(void *e, void *parent) {
  if (!NSThread.isMainThread || !e)
    return;
  auto *v = (__bridge VLCenterEditorView *)e;
  [v removeFromSuperview];
  if (parent)
    [(__bridge NSView *)parent addSubview:v];
}
extern "C" void vl_center_editor_refresh(void *e) {
  if (!NSThread.isMainThread || !e)
    return;
  [(__bridge VLCenterEditorView *)e refresh];
}
extern "C" void vl_center_editor_hint(void *e, int32_t index, int32_t value) {
  if (!NSThread.isMainThread || !e || index != 0 || value < 0 || value > 1)
    return;
  const auto h = [(__bridge VLCenterEditorView *)e host];
  if (h.hint)
    h.hint(h.context, value ? "DC centering: on" : "DC centering: off");
}
extern "C" int vl_center_editor_destroy(void *e) {
  if (!NSThread.isMainThread)
    return 0;
  if (!e)
    return 1;
  auto *v = (__bridge_transfer VLCenterEditorView *)e;
  [v removeFromSuperview];
  v.toggle.target = nil;
  v.numerical = nullptr;
  v.host = {};
  return 1;
}
