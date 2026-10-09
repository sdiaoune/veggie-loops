#import <Cocoa/Cocoa.h>
#include "phase_inverter_editor.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
namespace {
void require(bool value){if(!value)throw std::runtime_error("Independent Phase Inverter editor check failed");}
struct Host{bool locked=false;int locks=0,unlocks=0,changes=0,hints=0;int32_t value=-1;std::string text;};
void lock(void* context){auto& host=*static_cast<Host*>(context);require(!host.locked);host.locked=true;++host.locks;}
void unlock(void* context){auto& host=*static_cast<Host*>(context);require(host.locked);host.locked=false;++host.unlocks;}
void changed(void* context,int32_t index,int32_t value){auto& host=*static_cast<Host*>(context);require(!host.locked && index==0);++host.changes;host.value=value;}
void hint(void* context,const char* text){auto& host=*static_cast<Host*>(context);require(!host.locked && text);++host.hints;host.text=text;}
}
int main(){@autoreleasepool{try{
 [NSApplication sharedApplication];auto* plugin=vl_phase_inverter_create();require(plugin!=nullptr);
 Host host;VLPhaseInverterEditorHost callbacks{&host,lock,unlock,changed,hint};auto invalid=callbacks;invalid.unlock=nullptr;require(!vl_phase_inverter_editor_create(plugin,&invalid));
 void* editor=vl_phase_inverter_editor_create(plugin,&callbacks);require(editor!=nullptr);
 auto* parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,500,300)];vl_phase_inverter_editor_attach(editor,(__bridge void*)parent);
 auto* view=(__bridge NSView*)editor;require(view.superview==parent);NSSegmentedControl* inversion=nil;
 for(NSView* child in view.subviews)if([child isKindOfClass:NSSegmentedControl.class])inversion=(NSSegmentedControl*)child;
 require(inversion && inversion.selectedSegment==2);
 for(int choice=0;choice<3;++choice){inversion.selectedSegment=choice;[inversion sendAction:inversion.action to:inversion.target];require(host.value==choice*512 && host.changes==choice+1);}
 require(host.text=="Inversion: Right");
 // Compare every raw automation display with actual rendered channel polarity.
 const float input[2]{1,2};float output[2]{};int32_t result=0;
 for(int32_t value=0;value<=1024;++value){require(vl_phase_inverter_parameter(plugin,0,value,1,&result) && vl_phase_inverter_render(plugin,input,output,1));vl_phase_inverter_editor_refresh(editor);
   const int audibleChoice=output[0]<0?1:output[1]<0?2:0;require(inversion.selectedSegment==audibleChoice);
 }
 const int beforeLocks=host.locks,beforeHints=host.hints;int workerDestroy=1;void* workerEditor=editor;
 std::thread worker([&]{workerEditor=vl_phase_inverter_editor_create(plugin,&callbacks);vl_phase_inverter_editor_refresh(editor);vl_phase_inverter_editor_hint(editor,0,0);workerDestroy=vl_phase_inverter_editor_destroy(editor);});worker.join();
 require(!workerEditor && workerDestroy==0 && host.locks==beforeLocks && host.hints==beforeHints && view.superview==parent);
 vl_phase_inverter_editor_hint(editor,0,0);require(host.text=="Inversion: Bypass" && host.hints==4);
 vl_phase_inverter_editor_attach(editor,nullptr);require(view.superview==nil);vl_phase_inverter_editor_attach(editor,(__bridge void*)parent);
 require(vl_phase_inverter_editor_destroy(editor)==1 && parent.subviews.count==0 && host.locks==host.unlocks && !host.locked);vl_phase_inverter_destroy(plugin);
 std::cout<<"{\"status\":\"passed\",\"independently_written_appkit_editor\":true,\"control_changes\":3,\"automation_display_cases\":1025,\"host_notifications_after_unlock\":true,\"worker_gui_calls_skipped\":true,\"off_main_destroy_preserves_view\":true,\"native_fl_editor_integration\":false}\n";
 }catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}}}
