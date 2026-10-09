#import <Cocoa/Cocoa.h>
#include "stereo_shaper_editor.h"
#include <array>
#include <cmath>

namespace {
const std::array<NSString*,6>labels{@"Right → left",@"Left level",@"Right level",@"Left → right",@"Delay",@"Phase offset"};
NSString*valueText(int32_t index,int32_t value){
  if(index<4){const float unit=float(double(value)/12800.0);const float magnitude=std::abs(unit);const float gain=magnitude==1.0f?1.0f:float((std::exp(double(magnitude*0x1.193ea8p+0f))-1.0)*0.5);return [NSString stringWithFormat:@"%+.1f%%",double(gain)*100.0*((value>0)-(value<0))];}
  if(!value)return @"Off";
  if(index==4){const double milliseconds=double(float(std::exp(double(float(std::abs(value))*0x1p-12f)*6.90875477931522)-1.0)*50.0f)/100.0;return [NSString stringWithFormat:@"%@ %.2f ms",value<0?@"Left":@"Right",milliseconds];}
  return [NSString stringWithFormat:@"%@ %.1f%%",value<0?@"Left":@"Right",double(std::abs(value))*100.0/4096.0];
}
NSTextField*label(NSString*text,NSRect rect){auto*v=[NSTextField labelWithString:text];v.frame=rect;v.textColor=NSColor.whiteColor;return v;}
void lock(const VLStereoShaperEditorHost&h){if(h.lock)h.lock(h.context);}
void unlock(const VLStereoShaperEditorHost&h){if(h.unlock)h.unlock(h.context);}
}
@interface VLStereoShaperEditorView:NSView
@property(nonatomic,assign)VLStereoShaperPlugin*numerical;
@property(nonatomic,assign)VLStereoShaperEditorHost callbacks;
@property(nonatomic,strong)NSMutableArray<NSSlider*>*sliders;
@property(nonatomic,strong)NSMutableArray<NSTextField*>*values;
@property(nonatomic,strong)NSPopUpButton*send;
@property(nonatomic,strong)NSSegmentedControl*position;
-(void)refresh;
-(void)changed:(NSControl*)control;
@end
@implementation VLStereoShaperEditorView
-(instancetype)initWithFrame:(NSRect)frame{
  self=[super initWithFrame:frame];if(!self)return nil;self.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];self.wantsLayer=YES;self.layer.backgroundColor=[NSColor colorWithRed:.08 green:.12 blue:.10 alpha:1].CGColor;
  auto*title=label(@"VL Stereo Shaper",NSMakeRect(20,309,470,28));title.font=[NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];[self addSubview:title];self.sliders=[NSMutableArray array];self.values=[NSMutableArray array];
  for(int32_t i=0;i<6;++i){const double y=271-i*36;[self addSubview:label(labels[size_t(i)],NSMakeRect(20,y,116,23))];auto*slider=[NSSlider sliderWithValue:0 minValue:i<4?-25600:-4096 maxValue:i<4?25600:4096 target:self action:@selector(changed:)];slider.frame=NSMakeRect(137,y,239,23);slider.tag=i;slider.accessibilityLabel=labels[size_t(i)];[self addSubview:slider];[self.sliders addObject:slider];auto*value=label(@"",NSMakeRect(386,y,123,23));value.font=[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];[self addSubview:value];[self.values addObject:value];}
  [self addSubview:label(@"Side output",NSMakeRect(20,42,106,24))];auto*send=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(132,39,115,28) pullsDown:NO];[send addItemsWithTitles:@[@"Off",@"Output 1",@"Output 2",@"Output 3"]];send.tag=6;send.target=self;send.action=@selector(changed:);send.accessibilityLabel=@"Side output";[self addSubview:send];self.send=send;
  [self addSubview:label(@"Delay / phase",NSMakeRect(266,42,106,24))];auto*position=[NSSegmentedControl segmentedControlWithLabels:@[@"Before",@"After"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changed:)];position.frame=NSMakeRect(373,40,127,26);position.tag=7;position.accessibilityLabel=@"Delay and phase matrix position";[self addSubview:position];self.position=position;return self;
}
-(void)refresh{
  if(!NSThread.isMainThread||!self.numerical)return;std::array<int32_t,6>raw{};int32_t send=0,position=0;const auto h=self.callbacks;lock(h);for(int i=0;i<6;++i)vl_stereo_shaper_parameter(self.numerical,i,0,2,&raw[size_t(i)]);vl_stereo_shaper_get_routing(self.numerical,&send,&position);unlock(h);
  for(int i=0;i<6;++i){self.sliders[size_t(i)].integerValue=raw[size_t(i)];self.values[size_t(i)].stringValue=valueText(i,raw[size_t(i)]);}[self.send selectItemAtIndex:send];self.position.selectedSegment=position;
}
-(void)changed:(NSControl*)control{
  if(!NSThread.isMainThread||!self.numerical)return;const int32_t index=int32_t(control.tag);const auto h=self.callbacks;
  if(index>=0&&index<6){int32_t value=0;lock(h);const int accepted=vl_stereo_shaper_parameter(self.numerical,index,int32_t(control.integerValue),1,&value);unlock(h);if(!accepted)return;self.values[size_t(index)].stringValue=valueText(index,value);if(h.changed)h.changed(h.context,index,value);if(h.hint)h.hint(h.context,[NSString stringWithFormat:@"%@: %@",labels[size_t(index)],valueText(index,value)].UTF8String);}
  else if(index==6||index==7){const int32_t send=int32_t(self.send.indexOfSelectedItem),position=int32_t(self.position.selectedSegment);lock(h);const int accepted=vl_stereo_shaper_routing(self.numerical,send,position);unlock(h);if(accepted&&h.routing)h.routing(h.context,send,position);}
}
@end
extern "C" void*vl_stereo_shaper_editor_create(VLStereoShaperPlugin*p,const VLStereoShaperEditorHost*h){if(!NSThread.isMainThread||!p||(h&&bool(h->lock)!=bool(h->unlock)))return nullptr;auto*v=[[VLStereoShaperEditorView alloc]initWithFrame:NSMakeRect(0,0,522,352)];v.numerical=p;if(h)v.callbacks=*h;[v refresh];return (__bridge_retained void*)v;}
extern "C" void vl_stereo_shaper_editor_attach(void*e,void*p){if(!NSThread.isMainThread||!e)return;auto*v=(__bridge VLStereoShaperEditorView*)e;[v removeFromSuperview];if(p)[(__bridge NSView*)p addSubview:v];}
extern "C" void vl_stereo_shaper_editor_refresh(void*e){if(NSThread.isMainThread&&e)[(__bridge VLStereoShaperEditorView*)e refresh];}
extern "C" void vl_stereo_shaper_editor_hint(void*e,int32_t index,int32_t raw){if(!NSThread.isMainThread||!e||index<0||index>=6||(index<4?(raw< -25600||raw>25600):(raw< -4096||raw>4096)))return;auto*v=(__bridge VLStereoShaperEditorView*)e;const auto h=v.callbacks;if(h.hint)h.hint(h.context,[NSString stringWithFormat:@"%@: %@",labels[size_t(index)],valueText(index,raw)].UTF8String);}
extern "C" int vl_stereo_shaper_editor_main_thread(void){return NSThread.isMainThread;}
extern "C" int vl_stereo_shaper_editor_destroy(void*e){if(!e)return 1;if(!NSThread.isMainThread)return 0;auto*v=(__bridge_transfer VLStereoShaperEditorView*)e;[v removeFromSuperview];v.numerical=nullptr;return 1;}
