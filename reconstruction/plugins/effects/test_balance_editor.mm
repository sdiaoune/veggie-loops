#import <Cocoa/Cocoa.h>
#include "balance_editor.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

struct Host {bool locked=false;int locks=0,unlocks=0,changes=0,hints=0;int32_t index=-1,value=-1;};
void require(bool condition){if(!condition)throw std::runtime_error("Original Balance editor check failed");}
void lock(void* pointer){auto& h=*static_cast<Host*>(pointer);require(!h.locked);h.locked=true;++h.locks;}
void unlock(void* pointer){auto& h=*static_cast<Host*>(pointer);require(h.locked);h.locked=false;++h.unlocks;}
void changed(void* pointer,int32_t index,int32_t value){auto& h=*static_cast<Host*>(pointer);require(!h.locked);++h.changes;h.index=index;h.value=value;}
void hint(void* pointer,const char* text){auto& h=*static_cast<Host*>(pointer);require(!h.locked && text && *text);++h.hints;}
int main(){@autoreleasepool{try{
 [NSApplication sharedApplication];auto* numerical=vl_balance_create();require(numerical!=nullptr);
 Host host;VLBalanceEditorHost callbacks{&host,lock,unlock,changed,hint};
 void* editor=vl_balance_editor_create(numerical,&callbacks);require(editor!=nullptr);
 auto* parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,500,300)];vl_balance_editor_attach(editor,(__bridge void*)parent);
 auto* view=(__bridge NSView*)editor;require(view.superview==parent);
 NSSlider* pan=nil;NSSlider* volume=nil;
 for(NSView* child in view.subviews)if([child isKindOfClass:NSSlider.class]){auto* slider=(NSSlider*)child;if(slider.tag==0)pan=slider;else volume=slider;}
 require(pan && volume && pan.integerValue==0 && volume.integerValue==256);
 pan.integerValue=-128;[pan sendAction:pan.action to:pan.target];require(host.index==0 && host.value==-128 && host.changes==1 && host.hints==1);
 volume.integerValue=0;[volume sendAction:volume.action to:volume.target];require(host.index==1 && host.value==0 && host.changes==2 && host.hints==2);
 int32_t value=0;require(vl_balance_parameter(numerical,0,64,1,&value));require(vl_balance_parameter(numerical,1,320,1,&value));
 vl_balance_editor_refresh(editor);require(pan.integerValue==64 && volume.integerValue==320);
 require(host.locks==host.unlocks && !host.locked);
 vl_balance_editor_attach(editor,nullptr);require(view.superview==nil);
 vl_balance_editor_attach(editor,(__bridge void*)parent);
 int offMainResult=1;std::thread worker([&]{offMainResult=vl_balance_editor_destroy(editor);});worker.join();
 require(offMainResult==0 && parent.subviews.count==1);
 require(vl_balance_editor_destroy(editor)==1 && parent.subviews.count==0);
 vl_balance_destroy(numerical);
 std::cout<<"{\"status\":\"passed\",\"independently_written_appkit_editor\":true,\"control_changes\":2,\"host_callbacks_after_unlock\":true,\"off_main_destroy_refused\":true,\"native_fl_editor_integration\":false}\n";
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}}
