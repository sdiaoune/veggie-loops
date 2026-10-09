#pragma once
// Private experiment: independent C++ Fruity generator interface around the
// published bounded channel. Not the original Pascal class or complete plugin.
// GetName/name requires caller-owned writable output storage of at least 256
// bytes. Original GUI/name equivalence remains open.
#include "three_osc_multimode_channel.h"
namespace vl_private_osc {
struct Plugin;
#pragma pack(push,4)
struct Info {int32_t version;const char*long_name;const char*short_name;int32_t flags,parameters,polyphony,output_controls,output_voices,reserved[30];};
#pragma pack(pop)
struct Functions {
 void(*destroy)(Plugin*);intptr_t(*dispatch)(Plugin*,intptr_t,intptr_t,intptr_t);void(*idle)(Plugin*);
 void(*state)(Plugin*,void*,int32_t);void(*name)(Plugin*,int32_t,int32_t,int32_t,char*);
 int32_t(*event)(Plugin*,int32_t,int32_t,int32_t);int32_t(*parameter)(Plugin*,int32_t,int32_t,int32_t);
 void(*effect)(Plugin*,const float*,float*,int32_t);void(*generator)(Plugin*,float*,int32_t&);
 intptr_t(*trigger)(Plugin*,void*,intptr_t);void(*release)(Plugin*,intptr_t);void(*kill)(Plugin*,intptr_t);
 int32_t(*voice_event)(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t);int32_t(*raw_render)(Plugin*,intptr_t,float*,int32_t&);
 void(*tick)(Plugin*);void(*midi_tick)(Plugin*);void(*midi)(Plugin*,int32_t&);void(*message)(Plugin*,intptr_t);
 int32_t(*output_event)(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t);void(*output_kill)(Plugin*,intptr_t);
 void(*complete_destructor)(Plugin*);void(*deleting_destructor)(Plugin*);
};
struct Plugin {const Functions*functions;intptr_t tag;const Info*info;intptr_t editor;int32_t mono,reserved[32];};
static_assert(sizeof(Plugin)==168&&offsetof(Plugin,info)==16);
static_assert(offsetof(Info,flags)==20&&offsetof(Info,parameters)==24);
}
extern "C" vl_private_osc::Plugin* CreatePlugInstance(void*,intptr_t);
// Explicit fixed prepared context; no current voices; independently generated
// table bank retained by instance. No real host clock/table production claim.
extern "C" int vl_private_osc_prepare(vl_private_osc::Plugin*,int32_t,double,uint32_t);
extern "C" vl_osc_multimode_channel* vl_private_osc_channel(vl_private_osc::Plugin*);
