#import <Cocoa/Cocoa.h>
#include "mute2_editor.h"
#include <algorithm>

@interface VLMute2EditorView : NSView
@property(nonatomic,assign) VLMute2Plugin* numerical;
@property(nonatomic,assign) VLMute2EditorHost callbacks;
@property(nonatomic,strong) NSButton* enabled;
@property(nonatomic,strong) NSSegmentedControl* channels;
- (void)refresh;
- (void)changed:(NSControl*)control;
@end
namespace {
int selector(int32_t value){return std::min(int(float(double(value)/1024.0)/(1.0f/3.0f)),2);}
NSString* valueText(int32_t index,int32_t value){
  if(index==0)return value>=512?@"Audio: Enabled":@"Audio: Muted";
  const auto choice=selector(value);return choice==0?@"Muted channels: Left":choice==1?@"Muted channels: Both":@"Muted channels: Right";
}
NSTextField* label(NSString* text,NSRect frame){auto* result=[NSTextField labelWithString:text];result.frame=frame;result.textColor=NSColor.whiteColor;return result;}
void lock(const VLMute2EditorHost& host){if(host.lock)host.lock(host.context);}
void unlock(const VLMute2EditorHost& host){if(host.unlock)host.unlock(host.context);}
}
@implementation VLMute2EditorView
- (instancetype)initWithFrame:(NSRect)frame {
  self=[super initWithFrame:frame];if(!self)return nil;
  self.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  self.wantsLayer=YES;self.layer.backgroundColor=[NSColor colorWithRed:.08 green:.12 blue:.10 alpha:1].CGColor;
  auto* title=label(@"VL Mute 2",NSMakeRect(18,105,250,26));title.font=[NSFont systemFontOfSize:19 weight:NSFontWeightSemibold];[self addSubview:title];
  auto* enabled=[NSButton checkboxWithTitle:@"Audio enabled" target:self action:@selector(changed:)];
  enabled.frame=NSMakeRect(18,72,265,24);enabled.tag=0;enabled.accessibilityLabel=@"Audio enabled";[self addSubview:enabled];self.enabled=enabled;
  [self addSubview:label(@"Muted channels",NSMakeRect(18,30,108,24))];
  auto* channels=[NSSegmentedControl segmentedControlWithLabels:@[@"Left",@"Both",@"Right"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changed:)];
  channels.frame=NSMakeRect(127,29,178,26);channels.tag=1;channels.accessibilityLabel=@"Muted channels";[self addSubview:channels];self.channels=channels;
  return self;
}
- (void)refresh {
  if(!NSThread.isMainThread || !self.numerical)return;
  int32_t values[2]{};const auto callbacks=self.callbacks;lock(callbacks);
  for(int32_t i=0;i<2;++i)vl_mute2_parameter(self.numerical,i,0,2,&values[i]);unlock(callbacks);
  self.enabled.state=values[0]>=512?NSControlStateValueOn:NSControlStateValueOff;
  self.channels.selectedSegment=selector(values[1]);
}
- (void)changed:(NSControl*)control {
  if(!NSThread.isMainThread || !self.numerical)return;
  const auto index=int32_t(control.tag);if(index<0 || index>1)return;
  const auto value=index==0?(self.enabled.state==NSControlStateValueOn?1024:0):int32_t(self.channels.selectedSegment)*512;
  int32_t result=0;const auto callbacks=self.callbacks;lock(callbacks);
  const auto accepted=vl_mute2_parameter(self.numerical,index,value,1,&result);unlock(callbacks);if(!accepted)return;
  if(callbacks.changed)callbacks.changed(callbacks.context,index,result);
  if(callbacks.hint)callbacks.hint(callbacks.context,valueText(index,result).UTF8String);
}
@end
extern "C" void* vl_mute2_editor_create(VLMute2Plugin* plugin,const VLMute2EditorHost* host){
  if(!NSThread.isMainThread || !plugin || (host && bool(host->lock)!=bool(host->unlock)))return nullptr;
  auto* view=[[VLMute2EditorView alloc]initWithFrame:NSMakeRect(0,0,322,145)];view.numerical=plugin;
  if(host)view.callbacks=*host;[view refresh];return (__bridge_retained void*)view;
}
extern "C" void vl_mute2_editor_attach(void* editor,void* parent){
  if(!NSThread.isMainThread || !editor)return;
  auto* view=(__bridge VLMute2EditorView*)editor;[view removeFromSuperview];if(parent)[(__bridge NSView*)parent addSubview:view];
}
extern "C" void vl_mute2_editor_refresh(void* editor){if(NSThread.isMainThread && editor)[(__bridge VLMute2EditorView*)editor refresh];}
extern "C" void vl_mute2_editor_hint(void* editor,int32_t index,int32_t value){
  if(!NSThread.isMainThread || !editor || index<0 || index>1 || value<0 || value>1024)return;
  auto* view=(__bridge VLMute2EditorView*)editor;const auto callbacks=view.callbacks;
  if(callbacks.hint)callbacks.hint(callbacks.context,valueText(index,value).UTF8String);
}
extern "C" int vl_mute2_editor_main_thread(void){return NSThread.isMainThread;}
extern "C" int vl_mute2_editor_destroy(void* editor){
  if(!editor)return 1;if(!NSThread.isMainThread)return 0;
  auto* view=(__bridge_transfer VLMute2EditorView*)editor;[view removeFromSuperview];view.numerical=nullptr;view.callbacks={};view.enabled.target=nil;view.channels.target=nil;return 1;
}
