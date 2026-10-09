#import <Cocoa/Cocoa.h>
#include "phase_inverter_editor.h"

@interface VLPhaseInverterEditorView : NSView
@property(nonatomic,assign) VLPhaseInverterPlugin* numerical;
@property(nonatomic,assign) VLPhaseInverterEditorHost callbacks;
@property(nonatomic,strong) NSSegmentedControl* inversion;
- (void)refresh;
- (void)changed:(NSControl*)control;
@end
namespace {
int selector(int32_t value){return value<=341?0:value<=682?1:2;}
NSString* valueText(int32_t value){const auto choice=selector(value);return choice==0?@"Inversion: Bypass":choice==1?@"Inversion: Left":@"Inversion: Right";}
NSTextField* label(NSString* text,NSRect frame){auto* result=[NSTextField labelWithString:text];result.frame=frame;result.textColor=NSColor.whiteColor;return result;}
void lock(const VLPhaseInverterEditorHost& host){if(host.lock)host.lock(host.context);}
void unlock(const VLPhaseInverterEditorHost& host){if(host.unlock)host.unlock(host.context);}
}
@implementation VLPhaseInverterEditorView
- (instancetype)initWithFrame:(NSRect)frame {
  self=[super initWithFrame:frame];if(!self)return nil;
  self.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  self.wantsLayer=YES;self.layer.backgroundColor=[NSColor colorWithRed:.08 green:.12 blue:.10 alpha:1].CGColor;
  auto* title=label(@"VL Phase Inverter",NSMakeRect(18,76,305,26));title.font=[NSFont systemFontOfSize:19 weight:NSFontWeightSemibold];[self addSubview:title];
  [self addSubview:label(@"Invert channel",NSMakeRect(18,30,99,24))];
  auto* inversion=[NSSegmentedControl segmentedControlWithLabels:@[@"Bypass",@"Left",@"Right"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changed:)];
  inversion.frame=NSMakeRect(119,29,190,26);inversion.tag=0;inversion.accessibilityLabel=@"Invert channel";[self addSubview:inversion];self.inversion=inversion;
  return self;
}
- (void)refresh {
  if(!NSThread.isMainThread || !self.numerical)return;
  int32_t value=0;const auto callbacks=self.callbacks;lock(callbacks);vl_phase_inverter_parameter(self.numerical,0,0,2,&value);unlock(callbacks);
  self.inversion.selectedSegment=selector(value);
}
- (void)changed:(NSControl*)control {
  if(!NSThread.isMainThread || !self.numerical || control.tag!=0)return;
  const auto value=int32_t(self.inversion.selectedSegment)*512;
  int32_t result=0;const auto callbacks=self.callbacks;lock(callbacks);
  const auto accepted=vl_phase_inverter_parameter(self.numerical,0,value,1,&result);unlock(callbacks);if(!accepted)return;
  if(callbacks.changed)callbacks.changed(callbacks.context,0,result);
  if(callbacks.hint)callbacks.hint(callbacks.context,valueText(result).UTF8String);
}
@end
extern "C" void* vl_phase_inverter_editor_create(VLPhaseInverterPlugin* plugin,const VLPhaseInverterEditorHost* host){
  if(!NSThread.isMainThread || !plugin || (host && bool(host->lock)!=bool(host->unlock)))return nullptr;
  auto* view=[[VLPhaseInverterEditorView alloc]initWithFrame:NSMakeRect(0,0,330,115)];view.numerical=plugin;
  if(host)view.callbacks=*host;[view refresh];return (__bridge_retained void*)view;
}
extern "C" void vl_phase_inverter_editor_attach(void* editor,void* parent){
  if(!NSThread.isMainThread || !editor)return;
  auto* view=(__bridge VLPhaseInverterEditorView*)editor;[view removeFromSuperview];if(parent)[(__bridge NSView*)parent addSubview:view];
}
extern "C" void vl_phase_inverter_editor_refresh(void* editor){if(NSThread.isMainThread && editor)[(__bridge VLPhaseInverterEditorView*)editor refresh];}
extern "C" void vl_phase_inverter_editor_hint(void* editor,int32_t index,int32_t value){
  if(!NSThread.isMainThread || !editor || index!=0 || value<0 || value>1024)return;
  auto* view=(__bridge VLPhaseInverterEditorView*)editor;const auto callbacks=view.callbacks;
  if(callbacks.hint)callbacks.hint(callbacks.context,valueText(value).UTF8String);
}
extern "C" int vl_phase_inverter_editor_main_thread(void){return NSThread.isMainThread;}
extern "C" int vl_phase_inverter_editor_destroy(void* editor){
  if(!editor)return 1;if(!NSThread.isMainThread)return 0;
  auto* view=(__bridge_transfer VLPhaseInverterEditorView*)editor;[view removeFromSuperview];view.numerical=nullptr;view.callbacks={};view.inversion.target=nil;return 1;
}
