// Original host-only fixture for the explicitly GPL Vial1.0.6 source build.
// No GPL implementation, installed commercial code or captured state is linked.
#define main reference_host_entry
#include "../common/vst2_probe.mm"
#undef main
#include <iomanip>

int main(int argc,char** argv){
 @autoreleasepool {try{
  require(argc==7,"usage: vial_matrix_probe source-built.vst prefix rate block rounds source-version");
  const int rate=parsePositive(argv[3],8000,192000);
  blockSize=parsePositive(argv[4],1,8192);
  const int rounds=parsePositive(argv[5],1,20);
  require(std::strcmp(argv[6],"1.0.6")==0,"Explicit source-version provenance required");
  transport.sampleRate=rate;transport.tempo=120;transport.numerator=transport.denominator=4;
  transport.flags=(1<<1)|(1<<9)|(1<<10)|(1<<13);
  Bundle bundle;
  auto url=CFURLCreateFromFileSystemRepresentation(nullptr,reinterpret_cast<const UInt8*>(argv[1]),std::strlen(argv[1]),true);
  require(url,"URL creation");bundle.value=CFBundleCreate(nullptr,url);CFRelease(url);
  require(bundle.value && CFBundleLoadExecutable(bundle.value),"Source-built bundle load");
  using Entry=Effect*(*)(Dispatch);
  auto entry=reinterpret_cast<Entry>(CFBundleGetFunctionPointerForName(bundle.value,CFSTR("VSTPluginMain")));
  require(entry,"Source-built legacy factory");
  Instance instance;instance.value=entry(host);auto* effect=instance.value;
  require(effect && effect->magic==0x56737450 && effect->dispatcher,"Effect ABI");
  require(effect->uniqueID==0x5669616c && effect->version==0x10006 && effect->parameters==772,
          "Source1.0.6 identity differs");
  require(effect->inputs==0 && effect->outputs==2 && effect->replacing && (effect->flags&48)==48,"Stereo/chunk ABI");
  require(effect->dispatcher(effect,0,0,0,nullptr,0)==1,"Open");instance.opened=true;
  require(effect->dispatcher(effect,10,0,0,nullptr,float(rate))==1,"Rate accepted");
  require(effect->dispatcher(effect,11,0,blockSize,nullptr,0)==1,"Block accepted");
  auto state=chunk(effect);require(!state.empty(),"Generated valid initial state");
  const std::string prefix=argv[2];save(prefix+"-g0.bin",state);
  size_t byteEqualPairs=0;
  for(int generation=1;generation<=rounds;++generation){
   require(effect->dispatcher(effect,24,1,intptr_t(state.size()),state.data(),0)==1,"Valid generated state restore");
   auto next=chunk(effect);require(!next.empty(),"Generated state save");
   if(next==state)++byteEqualPairs;
   save(prefix+"-g"+std::to_string(generation)+".bin",next);state=std::move(next);
  }
  require(effect->dispatcher(effect,12,0,1,nullptr,0)==1,"Prepare");instance.powered=true;
  require(effect->dispatcher(effect,71,0,0,nullptr,0)==1,"Start");instance.started=true;
  std::vector<float> left(size_t(blockSize)+4,71),right(size_t(blockSize)+4,73);
  float* output[2]{left.data()+2,right.data()+2};
  size_t guardedCalls=0;
  const auto process=[&](int frames){
   std::fill(left.begin(),left.end(),71);std::fill(right.begin(),right.end(),73);
   effect->replacing(effect,nullptr,output,frames);
   require(left[0]==71 && left[1]==71 && right[0]==73 && right[1]==73,"Leading output guard");
   for(int i=frames+2;i<blockSize+4;++i)require(left[size_t(i)]==71 && right[size_t(i)]==73,"Trailing output guard");
   for(int i=0;i<frames;++i)require(std::isfinite(output[0][i]) && std::isfinite(output[1][i]),"Finite audio");
   ++guardedCalls;
  };
  const auto midi=[&](int offset,bool on){
   Midi note{};note.type=1;note.byteSize=32;note.deltaFrames=offset;
   note.data[0]=on?0x90:0x80;note.data[1]=69;note.data[2]=on?100:0;
   Events events{};events.count=1;events.events[0]=&note;
   require(effect->dispatcher(effect,25,0,0,&events,0)==1,"Valid MIDI input");
  };
  midi(0,true);process(0);process(1);
  require(output[0][0]==0 && output[1][0]==0,"Zero-frame render must clear queued MIDI");
  if(blockSize>1){
   midi(blockSize-1,true);process(1);process(blockSize);
   for(int i=0;i<blockSize;++i)require(output[0][i]==0 && output[1][i]==0,"Outside-short-block MIDI persisted");
  }
  const int musicalFrames=std::max((rate+3)/4,blockSize*2);
  const int noteOff=musicalFrames/2;double peak=0,energy=0;
  for(int offset=0;offset<musicalFrames;){
   const int frames=std::min(blockSize,musicalFrames-offset);
   {std::lock_guard<std::mutex> lock(transportMutex);transport.samplePos=offset;transport.ppqPos=double(offset)*2/rate;}
   if(offset==0)midi(0,true);
   if(noteOff>=offset && noteOff<offset+frames)midi(noteOff-offset,false);
   process(frames);
   for(int i=0;i<frames;++i)for(int channel=0;channel<2;++channel){const double x=output[channel][i];peak=std::max(peak,std::abs(x));energy+=x*x;}
   offset+=frames;
  }
  require(peak>0.000001 && energy>0.000001,"Valid note produced silent output");
  require(effect->dispatcher(effect,72,0,0,nullptr,0)==1,"Stop");instance.started=false;
  require(effect->dispatcher(effect,12,0,0,nullptr,0)==1,"Release");instance.powered=false;
  require(effect->dispatcher(effect,12,0,1,nullptr,0)==1,"Reprepare");instance.powered=true;
  process(1);process(blockSize);
  std::cout<<std::setprecision(17)<<"{\"status\":\"passed\",\"source_version\":\"Vial1.0.6\",\"installed_reference_rebuilt\":false,\"rate\":"<<rate
    <<",\"block\":"<<blockSize<<",\"state_rounds\":"<<rounds<<",\"exact_adjacent_state_pairs\":"<<byteEqualPairs
    <<",\"guarded_process_calls\":"<<guardedCalls<<",\"musical_frames\":"<<musicalFrames<<",\"peak\":"<<peak
    <<",\"energy\":"<<energy<<",\"short_zero_block_guards\":true,\"release_reprepare\":true,\"arbitrary_state_rejection\":false,\"realtime_certificate\":false}\n";
  return 0;
 }catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}}
}
