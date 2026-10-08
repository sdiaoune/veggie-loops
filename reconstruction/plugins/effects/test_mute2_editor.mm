#import <Cocoa/Cocoa.h>
#include "mute2_editor.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
namespace {
void require(bool condition){if(!condition)throw std::runtime_error("Independent Mute 2 editor check failed");}
struct Host{bool locked=false;int locks=0,unlocks=0,changes=0,hints=0;int32_t index=-1,value=-1;std::string text;};
void lock(void* context){auto& host=*static_cast<Host*>(context);require(!host.locked);host.locked=true;++host.locks;}
void unlock(void* context){auto& host=*static_cast<Host*>(context);require(host.locked);host.locked=false;++host.unlocks;}
void changed(void* context,int32_t index,int32_t value){auto& host=*static_cast<Host*>(context);require(!host.locked);++host.changes;host.index=index;host.value=value;}
void hint(void* context,const char* value){auto& host=*static_cast<Host*>(context);require(!host.locked && value);++host.hints;host.text=value;}
}
int main(){@autoreleasepool{try{
 [NSApplication sharedApplication];auto* plugin=vl_mute2_create();require(plugin!=nullptr);
 Host host;VLMute2EditorHost callbacks{&host,lock,unlock,changed,hint};auto invalid=callbacks;invalid.unlock=nullptr;require(!vl_mute2_editor_create(plugin,&invalid));
 void* editor=vl_mute2_editor_create(plugin,&callbacks);require(editor!=nullptr);
 auto* parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,500,300)];vl_mute2_editor_attach(editor,(__bridge void*)parent);
 auto* view=(__bridge NSView*)editor;require(view.superview==parent);
 NSButton* enabled=nil;NSSegmentedControl* channels=nil;
 for(NSView* child in view.subviews){if([child isKindOfClass:NSButton.class])enabled=(NSButton*)child;if([child isKindOfClass:NSSegmentedControl.class])channels=(NSSegmentedControl*)child;}
 require(enabled && channels && enabled.state==NSControlStateValueOn && channels.selectedSegment==1);
 enabled.state=NSControlStateValueOff;[enabled sendAction:enabled.action to:enabled.target];require(host.index==0 && host.value==0 && host.changes==1 && host.text=="Audio: Muted");
 channels.selectedSegment=2;[channels sendAction:channels.action to:channels.target];require(host.index==1 && host.value==1024 && host.changes==2 && host.text=="Muted channels: Right");
 int32_t result=0;require(vl_mute2_parameter(plugin,0,512,1,&result) && vl_mute2_parameter(plugin,1,341,1,&result));
 vl_mute2_editor_refresh(editor);require(enabled.state==NSControlStateValueOn && channels.selectedSegment==0);
 // Compare automation display against audible API behavior throughout both
 // recovered ranges, without repeating the editor's threshold calculation.
 const float input[2]{1,2};float output[2]{};
 require(vl_mute2_parameter(plugin,0,0,1,&result));
 for(int32_t value=0;value<=1024;++value){
   require(vl_mute2_parameter(plugin,1,value,1,&result) && vl_mute2_render(plugin,input,output,1));vl_mute2_editor_refresh(editor);
   const int audibleChoice=output[0]==0?(output[1]==0?1:0):2;require(channels.selectedSegment==audibleChoice);
 }
 require(vl_mute2_parameter(plugin,1,512,1,&result));
 for(int32_t value=0;value<=1024;++value){
   require(vl_mute2_parameter(plugin,0,value,1,&result) && vl_mute2_render(plugin,input,output,1));vl_mute2_editor_refresh(editor);
   require((enabled.state==NSControlStateValueOn)==(output[0]!=0));
 }
 const int beforeLocks=host.locks,beforeHints=host.hints;int workerDestroy=1;void* workerEditor=editor;
 std::thread worker([&]{workerEditor=vl_mute2_editor_create(plugin,&callbacks);vl_mute2_editor_refresh(editor);vl_mute2_editor_hint(editor,0,0);workerDestroy=vl_mute2_editor_destroy(editor);});worker.join();
 require(!workerEditor && workerDestroy==0 && host.locks==beforeLocks && host.hints==beforeHints && view.superview==parent);
 vl_mute2_editor_hint(editor,1,683);require(host.text=="Muted channels: Right" && host.hints==3);
 vl_mute2_editor_attach(editor,nullptr);require(view.superview==nil);vl_mute2_editor_attach(editor,(__bridge void*)parent);
 require(vl_mute2_editor_destroy(editor)==1 && parent.subviews.count==0 && host.locks==host.unlocks && !host.locked);vl_mute2_destroy(plugin);
 std::cout<<"{\"status\":\"passed\",\"independently_written_appkit_editor\":true,\"control_changes\":2,\"automation_display_cases\":2050,\"host_notifications_after_unlock\":true,\"worker_gui_calls_skipped\":true,\"off_main_destroy_preserves_view\":true,\"native_fl_editor_integration\":false}\n";
 }catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}}}
