#include "fast_dist_editor.h"
#import <Cocoa/Cocoa.h>
#include <array>
#include <cmath>
#include <cstdio>
namespace {
constexpr std::array<int32_t, 5> minimum{64, 1, 0, 0, 0},
    maximum{192, 10, 1, 128, 128};
constexpr std::array<const char *, 5> names{"Pre Gain", "Threshold", "Type",
                                            "Mix", "Post Gain"};
void lock(const VLFastDistEditorHost &h) {
  if (h.lock)
    h.lock(h.context);
}
void unlock(const VLFastDistEditorHost &h) {
  if (h.unlock)
    h.unlock(h.context);
}
void hint(const VLFastDistEditorHost &h, int32_t index, int32_t raw) {
  if (!h.hint || index < 0 || index >= 5 || raw < minimum[index] ||
      raw > maximum[index])
    return;
  char text[64];
  std::snprintf(text, sizeof(text), "%s: %d", names[index], raw);
  h.hint(h.context, text);
}
} // namespace
@interface VLFastDistEditorView : NSView
@property(nonatomic) VLFastDistPlugin *numerical;
@property(nonatomic) VLFastDistEditorHost host;
@property(nonatomic, strong) NSArray<NSControl *> *controls;
@property(nonatomic, strong) NSArray<NSTextField *> *values;
- (void)refresh;
- (void)change:(id)sender;
@end
@implementation VLFastDistEditorView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (!self)
    return nil;
  self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  self.wantsLayer = YES;
  self.layer.backgroundColor =
      [NSColor colorWithSRGBRed:.06 green:.10 blue:.08 alpha:1].CGColor;
  NSTextField *title = [NSTextField labelWithString:@"VL Fast Dist"];
  title.frame = NSMakeRect(20, 265, 420, 30);
  title.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
  [self addSubview:title];
  NSMutableArray<NSControl *> *controls = [NSMutableArray array];
  NSMutableArray<NSTextField *> *values = [NSMutableArray array];
  for (int32_t index = 0; index < 5; ++index) {
    const CGFloat y = 220 - index * 44;
    NSTextField *label = [NSTextField
        labelWithString:[NSString stringWithUTF8String:names[index]]];
    label.frame = NSMakeRect(20, y, 100, 24);
    [self addSubview:label];
    NSControl *control;
    if (index == 2) {
      NSButton *button = [NSButton checkboxWithTitle:@"Curve B"
                                              target:self
                                              action:@selector(change:)];
      button.allowsMixedState = NO;
      control = button;
    } else {
      NSSlider *slider = [NSSlider sliderWithValue:minimum[index]
                                          minValue:minimum[index]
                                          maxValue:maximum[index]
                                            target:self
                                            action:@selector(change:)];
      slider.continuous = YES;
      if (index == 1) {
        slider.numberOfTickMarks = 10;
        slider.allowsTickMarkValuesOnly = YES;
      }
      control = slider;
    }
    control.tag = index;
    control.frame = NSMakeRect(125, y, 250, 26);
    [controls addObject:control];
    [self addSubview:control];
    NSTextField *value = [NSTextField labelWithString:@"0"];
    value.tag = index;
    value.frame = NSMakeRect(390, y, 50, 24);
    value.alignment = NSTextAlignmentRight;
    value.font = [NSFont monospacedDigitSystemFontOfSize:13
                                                  weight:NSFontWeightRegular];
    [values addObject:value];
    [self addSubview:value];
  }
  self.controls = controls;
  self.values = values;
  return self;
}
- (void)refresh {
  if (!NSThread.isMainThread || !self.numerical)
    return;
  const auto h = self.host;
  std::array<int32_t, 5> raw{};
  bool ok = true;
  lock(h);
  for (int32_t index = 0; index < 5; ++index)
    ok = vl_fast_dist_parameter(self.numerical, index, 0, 2, &raw[index]) && ok;
  unlock(h);
  if (!ok)
    return;
  for (int32_t index = 0; index < 5; ++index) {
    NSControl *control = self.controls[index];
    if (index == 2)
      ((NSButton *)control).state =
          raw[index] ? NSControlStateValueOn : NSControlStateValueOff;
    else
      control.integerValue = raw[index];
    self.values[index].stringValue =
        [NSString stringWithFormat:@"%d", raw[index]];
  }
}
- (void)change:(id)sender {
  if (!NSThread.isMainThread || !self.numerical ||
      ![self.controls containsObject:sender])
    return;
  NSControl *control = sender;
  const int32_t index = int32_t(control.tag);
  const int32_t raw =
      index == 2
          ? (((NSButton *)control).state == NSControlStateValueOn ? 1 : 0)
          : int32_t(std::lround(control.doubleValue));
  const auto h = self.host;
  int32_t result = 0;
  lock(h);
  const bool ok =
      vl_fast_dist_parameter(self.numerical, index, raw, 1, &result);
  unlock(h);
  if (!ok)
    return;
  if (h.changed)
    h.changed(h.context, index, result);
  hint(h, index, result);
  [self refresh];
}
@end
extern "C" int vl_fast_dist_editor_main_thread() {
  return NSThread.isMainThread;
}
extern "C" void *vl_fast_dist_editor_create(VLFastDistPlugin *p,
                                            const VLFastDistEditorHost *h) {
  if (!NSThread.isMainThread || !p || (h && bool(h->lock) != bool(h->unlock)))
    return nullptr;
  auto *view =
      [[VLFastDistEditorView alloc] initWithFrame:NSMakeRect(0, 0, 460, 310)];
  view.numerical = p;
  if (h)
    view.host = *h;
  [view refresh];
  return (__bridge_retained void *)view;
}
extern "C" void vl_fast_dist_editor_attach(void *e, void *parent) {
  if (!NSThread.isMainThread || !e)
    return;
  auto *view = (__bridge VLFastDistEditorView *)e;
  [view removeFromSuperview];
  if (parent)
    [(__bridge NSView *)parent addSubview:view];
}
extern "C" void vl_fast_dist_editor_refresh(void *e) {
  if (!NSThread.isMainThread || !e)
    return;
  [(__bridge VLFastDistEditorView *)e refresh];
}
extern "C" void vl_fast_dist_editor_hint(void *e, int32_t index, int32_t raw) {
  if (!NSThread.isMainThread || !e)
    return;
  hint([(__bridge VLFastDistEditorView *)e host], index, raw);
}
extern "C" int vl_fast_dist_editor_destroy(void *e) {
  if (!NSThread.isMainThread)
    return 0;
  if (!e)
    return 1;
  auto *view = (__bridge_transfer VLFastDistEditorView *)e;
  [view removeFromSuperview];
  for (NSControl *control in view.controls)
    control.target = nil;
  view.numerical = nullptr;
  view.host = {};
  return 1;
}
