#include "soft_clipper_editor.h"
#import <Cocoa/Cocoa.h>
#include <array>
#include <cmath>
namespace {
const std::array<NSString *, 2> labels{@"Knee threshold", @"Output level"};
NSString *valueText(int32_t index, int32_t raw) {
  if (index == 0)
    return [NSString stringWithFormat:@"%.1f%%", double(raw) * 100.0 / 128.0];
  const float unit = float(raw) * 0x1p-7f;
  const float gain =
      unit == 1.0f ? 1.0f
                   : float((std::exp(double(unit * 0x1.32ee3cp+1f)) - 1.0) *
                           double(0x1.99999ap-4f));
  return [NSString stringWithFormat:@"%.2f×", double(gain)];
}
NSTextField *label(NSString *text, NSRect rect) {
  auto *v = [NSTextField labelWithString:text];
  v.frame = rect;
  v.textColor = NSColor.whiteColor;
  return v;
}
void lock(const VLSoftClipperEditorHost &h) {
  if (h.lock)
    h.lock(h.context);
}
void unlock(const VLSoftClipperEditorHost &h) {
  if (h.unlock)
    h.unlock(h.context);
}
} // namespace
@interface VLSoftClipperEditorView : NSView
@property(nonatomic, assign) VLSoftClipperPlugin *numerical;
@property(nonatomic, assign) VLSoftClipperEditorHost callbacks;
@property(nonatomic, strong) NSMutableArray<NSSlider *> *sliders;
@property(nonatomic, strong) NSMutableArray<NSTextField *> *values;
@property(nonatomic, strong) NSMutableArray<NSLevelIndicator *> *meters;
@property(nonatomic, strong) NSMutableArray<NSTextField *> *peaks;
- (void)refresh;
- (void)changed:(NSSlider *)control;
@end
@implementation VLSoftClipperEditorView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (!self)
    return nil;
  self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  self.wantsLayer = YES;
  self.layer.backgroundColor =
      [NSColor colorWithRed:.08 green:.12 blue:.10 alpha:1].CGColor;
  auto *title = label(@"VL Soft Clipper", NSMakeRect(20, 208, 440, 28));
  title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
  [self addSubview:title];
  self.sliders = [NSMutableArray array];
  self.values = [NSMutableArray array];
  self.meters = [NSMutableArray array];
  self.peaks = [NSMutableArray array];
  for (int32_t i = 0; i < 2; ++i) {
    const double y = 165 - i * 40;
    [self addSubview:label(labels[size_t(i)], NSMakeRect(20, y, 116, 23))];
    auto *v = [NSSlider sliderWithValue:i == 0 ? 100 : 128
                               minValue:i == 0 ? 1 : 0
                               maxValue:i == 0 ? 127 : 160
                                 target:self
                                 action:@selector(changed:)];
    v.frame = NSMakeRect(140, y, 245, 23);
    v.tag = i;
    v.accessibilityLabel = labels[size_t(i)];
    [self addSubview:v];
    [self.sliders addObject:v];
    auto *value = label(@"", NSMakeRect(394, y, 77, 23));
    value.font = [NSFont monospacedDigitSystemFontOfSize:12
                                                  weight:NSFontWeightRegular];
    [self addSubview:value];
    [self.values addObject:value];
  }
  [self addSubview:label(@"Knee peaks", NSMakeRect(20, 83, 120, 20))];
  for (int32_t channel = 0; channel < 2; ++channel) {
    const double y = 53 - channel * 25;
    [self addSubview:label(channel == 0 ? @"L" : @"R",
                           NSMakeRect(20, y, 22, 20))];
    auto *meter =
        [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(47, y + 3, 334, 16)];
    meter.levelIndicatorStyle = NSLevelIndicatorStyleContinuousCapacity;
    meter.minValue = 0;
    meter.maxValue = 1;
    meter.warningValue = .90;
    meter.criticalValue = .99;
    meter.accessibilityLabel =
        channel == 0 ? @"Left knee peak" : @"Right knee peak";
    [self addSubview:meter];
    [self.meters addObject:meter];
    auto *peak = label(@"0.000", NSMakeRect(393, y, 80, 20));
    peak.font = [NSFont monospacedDigitSystemFontOfSize:12
                                                 weight:NSFontWeightRegular];
    [self addSubview:peak];
    [self.peaks addObject:peak];
  }
  return self;
}
- (void)refresh {
  if (!NSThread.isMainThread || !self.numerical)
    return;
  std::array<int32_t, 2> raw{};
  std::array<float, 2> peaks{};
  const auto h = self.callbacks;
  lock(h);
  for (int32_t i = 0; i < 2; ++i)
    vl_soft_clipper_parameter(self.numerical, i, 0, 2, &raw[size_t(i)]);
  vl_soft_clipper_get_meters(self.numerical, peaks.data());
  vl_soft_clipper_clear_meters(self.numerical);
  unlock(h);
  for (int32_t i = 0; i < 2; ++i) {
    self.sliders[size_t(i)].integerValue = raw[size_t(i)];
    self.values[size_t(i)].stringValue = valueText(i, raw[size_t(i)]);
    self.meters[size_t(i)].doubleValue = double(peaks[size_t(i)]);
    self.peaks[size_t(i)].stringValue =
        [NSString stringWithFormat:@"%.3f", double(peaks[size_t(i)])];
  }
}
- (void)changed:(NSSlider *)control {
  if (!NSThread.isMainThread || !self.numerical)
    return;
  const int32_t index = int32_t(control.tag);
  if (index < 0 || index > 1)
    return;
  const auto h = self.callbacks;
  int32_t value = 0;
  lock(h);
  const int accepted = vl_soft_clipper_parameter(
      self.numerical, index, int32_t(control.integerValue), 1, &value);
  unlock(h);
  if (!accepted)
    return;
  self.values[size_t(index)].stringValue = valueText(index, value);
  if (h.changed)
    h.changed(h.context, index, value);
  if (h.hint)
    h.hint(h.context,
           [NSString stringWithFormat:@"%@: %@", labels[size_t(index)],
                                      valueText(index, value)]
               .UTF8String);
}
@end
extern "C" void *
vl_soft_clipper_editor_create(VLSoftClipperPlugin *p,
                              const VLSoftClipperEditorHost *h) {
  if (!NSThread.isMainThread || !p || (h && bool(h->lock) != bool(h->unlock)))
    return nullptr;
  auto *v = [[VLSoftClipperEditorView alloc]
      initWithFrame:NSMakeRect(0, 0, 490, 250)];
  v.numerical = p;
  if (h)
    v.callbacks = *h;
  [v refresh];
  return (__bridge_retained void *)v;
}
extern "C" void vl_soft_clipper_editor_attach(void *e, void *parent) {
  if (!NSThread.isMainThread || !e)
    return;
  auto *v = (__bridge VLSoftClipperEditorView *)e;
  [v removeFromSuperview];
  if (parent)
    [(__bridge NSView *)parent addSubview:v];
}
extern "C" void vl_soft_clipper_editor_refresh(void *e) {
  if (NSThread.isMainThread && e)
    [(__bridge VLSoftClipperEditorView *)e refresh];
}
extern "C" void vl_soft_clipper_editor_hint(void *e, int32_t index,
                                            int32_t value) {
  if (!NSThread.isMainThread || !e || index < 0 || index > 1 ||
      value < (index == 0 ? 1 : 0) || value > (index == 0 ? 127 : 160))
    return;
  auto *v = (__bridge VLSoftClipperEditorView *)e;
  const auto h = v.callbacks;
  if (h.hint)
    h.hint(h.context,
           [NSString stringWithFormat:@"%@: %@", labels[size_t(index)],
                                      valueText(index, value)]
               .UTF8String);
}
extern "C" int vl_soft_clipper_editor_main_thread(void) {
  return NSThread.isMainThread;
}
extern "C" int vl_soft_clipper_editor_destroy(void *e) {
  if (!e)
    return 1;
  if (!NSThread.isMainThread)
    return 0;
  auto *v = (__bridge_transfer VLSoftClipperEditorView *)e;
  [v removeFromSuperview];
  v.numerical = nullptr;
  return 1;
}
