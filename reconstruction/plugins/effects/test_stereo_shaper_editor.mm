#import <Cocoa/Cocoa.h>
#include "stereo_shaper_editor.h"
#include <array>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
namespace{
void require(bool v){if(!v)throw std::runtime_error("Stereo editor check failed");}
struct Host{bool locked=false;int locks=0,unlocks=0,changes=0,hints=0,routes=0;int32_t index=-1,value=0,send=0,position=0;std::string hint;};
void lock(void*c){auto&h=*static_cast<Host*>(c);require(!h.locked);h.locked=true;++h.locks;}
void unlock(void*c){auto&h=*static_cast<Host*>(c);require(h.locked);h.locked=false;++h.unlocks;}
void changed(void*c,int32_t i,int32_t v){auto&h=*static_cast<Host*>(c);require(!h.locked);h.index=i;h.value=v;++h.changes;}
void hint(void*c,const char*t){auto&h=*static_cast<Host*>(c);require(!h.locked&&t);h.hint=t;++h.hints;}
void routing(void*c,int32_t send,int32_t p){auto&h=*static_cast<Host*>(c);require(!h.locked);h.send=send;h.position=p;++h.routes;}
}
int main(int argc,char**argv){@autoreleasepool{try{
 [NSApplication sharedApplication];auto*p=vl_stereo_shaper_create();require(p);Host host{};VLStereoShaperEditorHost callbacks{&host,lock,unlock,changed,hint,routing};auto bad=callbacks;bad.unlock=nullptr;require(!vl_stereo_shaper_editor_create(p,&bad));void*editor=vl_stereo_shaper_editor_create(p,&callbacks);require(editor);
 auto*parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,600,400)];vl_stereo_shaper_editor_attach(editor,(__bridge void*)parent);auto*view=(__bridge NSView*)editor;std::array<NSSlider*,6>sliders{};NSPopUpButton*send=nil;NSSegmentedControl*position=nil;
 for(NSView*child in view.subviews){if([child isKindOfClass:NSSlider.class])sliders[size_t(((NSSlider*)child).tag)]=(NSSlider*)child;if([child isKindOfClass:NSPopUpButton.class])send=(NSPopUpButton*)child;if([child isKindOfClass:NSSegmentedControl.class])position=(NSSegmentedControl*)child;}
 require(send&&position&&send.indexOfSelectedItem==0&&position.selectedSegment==0);size_t displays=0;
 for(int i=0;i<6;++i){require(sliders[size_t(i)]);const int low=i<4?-25600:-4096,high=-low;require(sliders[size_t(i)].minValue==low&&sliders[size_t(i)].maxValue==high);for(int value:{low,low+1,-1,0,1,high-1,high}){int32_t result=0;require(vl_stereo_shaper_parameter(p,i,value,1,&result));vl_stereo_shaper_editor_refresh(editor);require(sliders[size_t(i)].integerValue==value);++displays;}sliders[size_t(i)].integerValue=low;[sliders[size_t(i)]sendAction:sliders[size_t(i)].action to:sliders[size_t(i)].target];int32_t value=0;require(host.index==i&&host.value==low&&vl_stereo_shaper_parameter(p,i,0,2,&value)&&value==low);}
 [send selectItemAtIndex:3];[send sendAction:send.action to:send.target];position.selectedSegment=1;[position sendAction:position.action to:position.target];int32_t sendValue=0,mode=0;require(vl_stereo_shaper_get_routing(p,&sendValue,&mode)&&sendValue==3&&mode==1&&host.routes==2&&host.send==3&&host.position==1);
 for(int s=0;s<4;++s)for(int m=0;m<2;++m){require(vl_stereo_shaper_routing(p,s,m));vl_stereo_shaper_editor_refresh(editor);require(send.indexOfSelectedItem==s&&position.selectedSegment==m);++displays;}
 const int locks=host.locks,hints=host.hints;void*workerEditor=editor;int destroyed=1;std::thread worker([&]{workerEditor=vl_stereo_shaper_editor_create(p,&callbacks);vl_stereo_shaper_editor_refresh(editor);vl_stereo_shaper_editor_hint(editor,0,0);vl_stereo_shaper_editor_attach(editor,nullptr);destroyed=vl_stereo_shaper_editor_destroy(editor);});worker.join();require(!workerEditor&&destroyed==0&&host.locks==locks&&host.hints==hints&&view.superview==parent);
 if(argc==2){for(int i=0;i<6;++i){int32_t unused=0;vl_stereo_shaper_parameter(p,i,i==1||i==2?12800:0,1,&unused);}vl_stereo_shaper_routing(p,0,0);vl_stereo_shaper_editor_refresh(editor);NSBitmapImageRep*bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];[[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];}
 vl_stereo_shaper_editor_attach(editor,nullptr);require(view.superview==nil);vl_stereo_shaper_editor_attach(editor,(__bridge void*)parent);require(vl_stereo_shaper_editor_destroy(editor)==1&&parent.subviews.count==0&&host.locks==host.unlocks);vl_stereo_shaper_destroy(p);
 std::cout<<"{\"status\":\"passed\",\"independently_written_appkit_editor\":true,\"parameter_control_changes\":"<<host.changes<<",\"routing_changes\":"<<host.routes<<",\"automation_display_cases\":"<<displays<<",\"notifications_after_unlock\":true,\"worker_ui_calls_skipped\":true,\"off_main_destroy_preserves_view\":true,\"native_editor_integration\":false}\n";
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}
