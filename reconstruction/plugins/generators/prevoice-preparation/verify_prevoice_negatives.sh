#!/bin/sh
set -eu
python3 - <<'VL_VERIFY_ENV'
import os,sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")
if os.environ.get("VL_PREVOICE_REPAIR_EXECUTION_COPY") != "1":
    raise SystemExit("Run the published verify_public.py entrypoint.")
VL_VERIFY_ENV
candidate=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${VL_PREVOICE_REPAIR_PROJECT_ROOT:-$(CDPATH= cd -- "$candidate/../../../.." && pwd)}
source="$project/reconstruction/plugins/generators"
positive=${VL_PREVOICE_REPAIR_NATIVE_DIR:-"$candidate/work/canonical-native"}
work=${VL_PREVOICE_REPAIR_NEGATIVE_DIR:-"$candidate/work/negatives"}
[ -f "$positive/cache-result.json" ] && [ -f "$positive/handoff-result.json" ] || { echo 'Native positive prerequisite missing' >&2;exit 1; }
mkdir -p "$work/compiler-cache"
export CLANG_MODULE_CACHE_PATH="$work/compiler-cache"
python3 - "$candidate" "$source" "$work" <<'PY'
import pathlib,sys
c,s,w=map(pathlib.Path,sys.argv[1:])
for name in ['no-eager','erase-history','eager-PPQ','reprepare-import','round-time']:
 p=w/name;p.mkdir(exist_ok=True)
 for n in ['prevoice_cache.hpp','prevoice_channel.hpp','prevoice_channel.cpp','prevoice_factory.cpp']:
  text=(c/n).read_text().replace('../../../../reconstruction/plugins/generators/live-context/immediate_coefficients.hpp',str(s/'live-context/immediate_coefficients.hpp'))
  (p/n).write_text(text)
 pth=p/'prevoice_cache.hpp';text=pth.read_text()
 if name=='no-eager':
  a='for(size_t g=0;g<5;++g){preparedTempo[g]=tempo;preparedPPQ[g]=ppq;prepare(g);}return true;'
  assert text.count(a)==1;text=text.replace(a,'return true;')
 elif name=='erase-history':
  a='if(valid[group])immediate::prepareConfiguration('
  assert text.count(a)==1
  text=text.replace(a,'if(valid[group]){std::array<envelope::Curve*,3>curves{&groups[group].attack,&groups[group].decay,&groups[group].release};for(size_t i=0;i<3;++i)if(groups[group].raw[14+i]==0){curves[i]->inverse=0;curves[i]->logarithm=0;}}\n  if(valid[group])immediate::prepareConfiguration(')
 elif name=='eager-PPQ':
  a='ppq=value;return true;';assert text.count(a)==1
  text=text.replace(a,'ppq=value;preparedPPQ.fill(ppq);for(size_t g=0;g<5;++g)prepare(g);return true;')
 elif name=='reprepare-import':
  ch=p/'prevoice_channel.cpp';v=ch.read_text();a='for(size_t i=0;i<5;++i)next->prepared[i].lfoTable='
  assert v.count(a)==1;v=v.replace(a,'next->preparedTempo.fill(next->tempo);next->preparedPPQ.fill(next->ppq);prepareAll(*next);\n  '+a);ch.write_text(v)
 elif name=='round-time':
  v=(s/'live-context/immediate_coefficients.hpp').read_text();assert 'namespace veggie_loops::three_osc::immediate' in v and 'std::rint(' in v
  v=v.replace('namespace veggie_loops::three_osc::immediate','namespace veggie_loops::three_osc::immediate_rounded').replace('std::rint(','std::round(');(p/'mutant_coefficients.hpp').write_text(v)
  text=text.replace(str(s/'live-context/immediate_coefficients.hpp'),'mutant_coefficients.hpp').replace('immediate::','immediate_rounded::')
  ch=p/'prevoice_channel.cpp';ch.write_text(ch.read_text().replace('immediate::','immediate_rounded::'))
 pth.write_text(text)
PY
for name in no-eager erase-history eager-PPQ reprepare-import round-time;do
 python3 - "$work" <<'PY'
import os,sys
s=os.statvfs(sys.argv[1]);assert s.f_bavail*s.f_frsize>=32*1024*1024,'Insufficient headroom; preserve outputs and stop'
PY
 p="$work/$name"
 # Exact core.cpp is included once by the cloned factory, never linked twice.
 clang++ -arch arm64 -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -I "$p" -I "$source" -dynamiclib -framework Accelerate "$p/prevoice_factory.cpp" "$p/prevoice_channel.cpp" "$source/three_osc_sync_lfo.cpp" "$source/three_osc_voice_lifecycle.cpp" "$source/three_osc_declick.cpp" "$source/three_osc_engine.cpp" -o "$p/mutant.dylib" > "$p/compile.stdout" 2> "$p/compile.stderr"
 codesign --force --sign - "$p/mutant.dylib" > "$p/sign.stdout" 2> "$p/sign.stderr"
 codesign --verify --strict "$p/mutant.dylib" > "$p/strict-signature.stdout" 2> "$p/strict-signature.stderr"
 harness="$positive/test_prevoice_cache";[ "$name" != reprepare-import ] || harness="$positive/test_prevoice_handoff"
 set +e
 "$harness" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$p/mutant.dylib" "$p/" > "$p/stdout" 2> "$p/stderr"
 code=$?
 set -e
 python3 - "$p" "$name" "$code" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);name=sys.argv[2];code=int(sys.argv[3]);s=(p/'stderr').read_text()
assert code==1,(name,code,s)
assert not (p/'stdout').read_bytes()
assert not any(t in s for t in ['runtime error:','AddressSanitizer','UndefinedBehaviorSanitizer','SUMMARY:'])
expected={'no-eager':['Immediate no-voice FE masks differ'],'erase-history':['Immediate parent coefficients differ','First-trigger cached history differs'],'eager-PPQ':['Immediate parent coefficients differ','Immediate no-voice FE masks differ'],'reprepare-import':['Handoff defined coefficients/history differ','First-trigger cache recomputed from current context'],'round-time':['Native FRINTX prepared boundary differs','Immediate parent coefficients differ','Immediate no-voice FE masks differ']}
assert any(t in s for t in expected[name]),(name,s)
r={'status':'passed_expected_source_mutant_rejection','name':name,'exit':code,'actual_failing_stage':'first specific assertion retained verbatim in stderr','stderr':s,'full_plugin_equivalence':False,'inputs':[{ 'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(p.iterdir()) if f.is_file() and f.name not in ['result.json']]}
(p/'result.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'name':name,'exit':code,'stderr':s}))
PY
done
