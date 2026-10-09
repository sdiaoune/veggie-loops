#import <Cocoa/Cocoa.h>
#include "balance_editor.h"
#include <cmath>

@interface VLBalanceEditorView : NSView
@property(nonatomic,assign) VLBalancePlugin* numerical;
@property(nonatomic,assign) VLBalanceEditorHost callbacks;
@property(nonatomic,strong) NSArray<NSSlider*>* sliders;
@property(nonatomic,strong) NSArray<NSTextField*>* values;
@property(nonatomic,strong) NSArray<NSLevelIndicator*>* meters;
- (void)refresh;
- (void)changed:(NSSlider*)sender;
@end

namespace {
NSTextField* label(NSString* text,NSRect frame){
  auto* result=[NSTextField labelWithString:text];result.frame=frame;
  result.font=[NSFont systemFontOfSize:12];return result;
}
NSString* valueText(int32_t index,int32_t value){
  if(index==0){if(value==0)return @"Center";
    return [NSString stringWithFormat:@"%.0f%% %@",std::fabs(double(value))*100/128,value<0?@"L":@"R"];}
  if(value==0)return @"Muted";
  const double gain=(std::exp(double(float((double(value)/320)*1.25))*2.3978952727983707)-1)/10;
  return [NSString stringWithFormat:@"%+.1f dB",20*std::log10(gain)];
}
void lock(const VLBalanceEditorHost& h){if(h.lock)h.lock(h.context);}
void unlock(const VLBalanceEditorHost& h){if(h.unlock)h.unlock(h.context);}
}

@implementation VLBalanceEditorView
- (instancetype)initWithFrame:(NSRect)frame {
  self=[super initWithFrame:frame];if(!self)return nil;
  self.wantsLayer=YES;self.layer.backgroundColor=[NSColor colorWithRed:.08 green:.12 blue:.10 alpha:1].CGColor;
  auto* title=label(@"VL Balance",NSMakeRect(18,149,230,25));
  title.font=[NSFont systemFontOfSize:19 weight:NSFontWeightSemibold];title.textColor=NSColor.whiteColor;[self addSubview:title];
  NSMutableArray<NSSlider*>* sliders=[NSMutableArray array];NSMutableArray<NSTextField*>* values=[NSMutableArray array];
  for(int32_t i=0;i<2;++i){
    const CGFloat y=111-43*i;auto* caption=label(i==0?@"Pan":@"Volume",NSMakeRect(18,y,64,20));
    caption.textColor=NSColor.whiteColor;[self addSubview:caption];
    auto* slider=[NSSlider sliderWithValue:i==0?0:256 minValue:i==0?-128:0 maxValue:i==0?128:320 target:self action:@selector(changed:)];
    slider.frame=NSMakeRect(82,y,173,22);slider.tag=i;slider.continuous=YES;
    slider.accessibilityLabel=i==0?@"Pan":@"Volume";[self addSubview:slider];[sliders addObject:slider];
    auto* value=label(@"",NSMakeRect(267,y,80,20));value.textColor=NSColor.whiteColor;
    value.alignment=NSTextAlignmentRight;[self addSubview:value];[values addObject:value];
  }
  self.sliders=sliders;self.values=values;
  NSMutableArray<NSLevelIndicator*>* meters=[NSMutableArray array];
  for(int i=0;i<2;++i){const CGFloat x=18+174*i;
    auto* caption=label(i==0?@"L":@"R",NSMakeRect(x,22,18,20));caption.textColor=NSColor.whiteColor;[self addSubview:caption];
    auto* meter=[[NSLevelIndicator alloc]initWithFrame:NSMakeRect(x+18,27,132,12)];
    meter.levelIndicatorStyle=NSLevelIndicatorStyleContinuousCapacity;meter.minValue=0;meter.maxValue=1;meter.warningValue=.8;meter.criticalValue=.98;
    meter.accessibilityLabel=i==0?@"Left peak":@"Right peak";[self addSubview:meter];[meters addObject:meter];
  }
  self.meters=meters;return self;
}
- (void)refresh {
  if(!self.numerical || !NSThread.isMainThread)return;
  int32_t values[2]{};float left=0,right=0;const auto callbacks=self.callbacks;
  lock(callbacks);for(int32_t i=0;i<2;++i)vl_balance_parameter(self.numerical,i,0,2,&values[i]);
  vl_balance_get_meters(self.numerical,&left,&right);unlock(callbacks);
  for(int32_t i=0;i<2;++i){self.sliders[i].integerValue=values[i];self.values[i].stringValue=valueText(i,values[i]);}
  self.meters[0].doubleValue=std::fmin(1,std::fmax(0,left));self.meters[1].doubleValue=std::fmin(1,std::fmax(0,right));
}
- (void)changed:(NSSlider*)sender {
  if(!self.numerical || !NSThread.isMainThread)return;
  const auto index=static_cast<int32_t>(sender.tag),raw=static_cast<int32_t>(sender.integerValue);
  int32_t result=0;const auto callbacks=self.callbacks;lock(callbacks);
  const auto accepted=vl_balance_parameter(self.numerical,index,raw,1,&result);unlock(callbacks);
  if(!accepted)return;
  self.values[index].stringValue=valueText(index,result);
  if(callbacks.changed)callbacks.changed(callbacks.context,index,result);
  NSString* hint=[NSString stringWithFormat:@"%@: %@",index==0?@"Pan":@"Volume",self.values[index].stringValue];
  if(callbacks.hint)callbacks.hint(callbacks.context,hint.UTF8String);
}
@end

extern "C" void* vl_balance_editor_create(VLBalancePlugin* numerical,const VLBalanceEditorHost* host){
  if(!numerical || !NSThread.isMainThread)return nullptr;
  if(host && bool(host->lock)!=bool(host->unlock))return nullptr;
  auto* view=[[VLBalanceEditorView alloc]initWithFrame:NSMakeRect(0,0,366,188)];view.numerical=numerical;
  if(host)view.callbacks=*host;[view refresh];return (__bridge_retained void*)view;
}
extern "C" void vl_balance_editor_attach(void* editor,void* parent){
  if(!editor || !NSThread.isMainThread)return;
  auto* view=(__bridge VLBalanceEditorView*)editor;[view removeFromSuperview];
  if(parent)[(__bridge NSView*)parent addSubview:view];
}
extern "C" void vl_balance_editor_refresh(void* editor){
  if(editor && NSThread.isMainThread)[(__bridge VLBalanceEditorView*)editor refresh];
}
extern "C" void vl_balance_editor_hint(void* editor,int32_t index,int32_t value){
  if(!editor || !NSThread.isMainThread || index<0 || index>1)return;
  auto* view=(__bridge VLBalanceEditorView*)editor;const auto callbacks=view.callbacks;
  NSString* text=[NSString stringWithFormat:@"%@: %@",index==0?@"Pan":@"Volume",valueText(index,value)];
  if(callbacks.hint)callbacks.hint(callbacks.context,text.UTF8String);
}
extern "C" int vl_balance_editor_main_thread(void){return NSThread.isMainThread;}
extern "C" int vl_balance_editor_destroy(void* editor){
  if(!editor)return 1;
  if(!NSThread.isMainThread)return 0;
  auto* view=(__bridge_transfer VLBalanceEditorView*)editor;[view removeFromSuperview];view.numerical=nullptr;
  view.callbacks={};
  for(NSControl* control in view.sliders)control.target=nil;
  return 1;
}
