local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Collector = require('__computer_core_2__.scripts.native.collector')
local Dispatch = require('__computer_core_2__.scripts.native.dispatch')
local Helpers = require('__computer_core_2__.scripts.native.helpers')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local legacy_bundle=require('legacy_temp_bundle')
local M={}
local function run(m,b,quantum,services)
 local blocks=Execution.executable(b)
 local turns=0
 while m.status=='running' do
  local status,spent=Execution.run(m,b,blocks,quantum,services)
  assert(status~='error',m.error and m.error.message)
  assert(spent<=quantum)
  turns=turns+1; assert(turns<20000,'temporary lease fixture stalled')
 end
end
function M.run(check)
 local adjusted=assert(Compiler.compile('local function f() return 1,nil,false end; return (f())','=native-scalar-result-publisher'))
 check('native scalar call adjustment uses existing result publisher',adjusted.generated:find('{mode="scalar",slot=',1,true)~=nil)
 local scalar=Execution.new(adjusted)
 run(scalar,adjusted,1)
 check('native parenthesized call retains exactly one result',scalar.result.n==1 and scalar.result[1]==1)
  local source='local n=0; '..string.rep('n=n+1;',100)..' return n,nil,false'
 local metrics={}
 local b=assert(Compiler.compile(source,'=native-temporary-lease',metrics))
 check('native sequential statements share bounded temporary leases',b.prototypes[1].temps<=16 and (metrics.temp_reuses or 0)>100)
 local small,large=Execution.new(b),Execution.new(b)
 run(small,b,1); run(large,b,97)
 check('native temporary reuse preserves quanta and nil arity',small.blocks==large.blocks and small.result.n==3
  and small.result[1]==100 and small.result[2]==nil and small.result[3]==false and large.result[1]==100)
 local cases={
  'local n=0; for i=1,7,2 do for j=2,6,2 do n=n+i*j end end; return n',
  'local n=0; for i,v in ipairs({2,3,4}) do for j,w in ipairs({5,6}) do n=n+i*j+v*w end end; return n',
  'local n=0; while n<8 do if n%2==0 then n=n+1 else n=n+3 end end; repeat n=n-1 until n==2; return n',
  'local n=0; ::again:: n=n+1; if n<7 then goto again end; return n',
  'local t={}; local old=t; local i=1; t[i],i=9,2; return old[1],i',
  'local x=3; local function f(n) return n+x,nil end; return f(2)*100+f(4)*10+f(6)',
  'local x=0; local function f() x=x+1; return x,nil end; local a,b,c=f(),f(),f(); return a,b,c,x',
  'local x={v=4}; function x:add(n) return self.v+n,nil end; return x:add(3)*x:add(5)',
  'local x=0; local function f() x=x+1; return x end; return false and f(),true or f(),nil or f(),x',
  'local t={}; setmetatable(t,{__index=function(_,k) return #k+3 end}); return t.alpha+t.beta',
  'local t={}; setmetatable(t,{__newindex=function(o,k,v) rawset(o,k,v+2) end}); t.x,t.y=3,5; return t.x,t.y',
  'return "t[999]=nil; f.pc=2; a.o(t[1])",nil,false',
 }
 local env={ipairs=ipairs,setmetatable=setmetatable,rawset=rawset}
 for i,source in ipairs(cases) do
  local expected=table.pack(assert(load(source,'=temporary-reference','t',env))())
  b=assert(Compiler.compile(source,'=native-temporary-case-'..i))
  local m=Execution.new(b); Execution.install_core(m); Helpers.install(m)
  local used={}
  local services=Helpers.services(function(domain,amount)
   local limit=assert(Limits[domain..'_work_per_computer'])
   assert(amount<=limit-(used[domain] or 0))
   used[domain]=(used[domain] or 0)+amount
  end)
  run(m,b,1,services)
  assert(m.status=='return' and m.result.n==expected.n)
  for j=1,expected.n do assert(m.result[j]==expected[j],'temporary value mismatch '..i..':'..j) end
  check('native temporary lease reference case '..i,true)
 end
end
local suspended_source=[[
local t={n=7}
local effects=0
local function f(n)
 effects=effects+1
 return pause(n,t,nil,false)
end
local a,b=f(2),f(3)
local result=a*100+b*10+t.n
for i=1,7 do local unused=i+2 end
return result,effects,t,nil,false
]]
function M.suspend(check)
 local b=assert(Compiler.compile(suspended_source,'=native-temporary-reload'))
 local m=Execution.new(b); Execution.install_core(m); Execution.service(m,'pause')
 local services={pause=function(_,args) return 'yield',args end}
 run(m,b,1,services)
 assert(m.status=='yield' and m.yielded[1]==2)
 local alias=m.yielded[2]
 Execution.resume(m,{n=4,2,alias,nil,false})
 run(m,b,1,services)
 assert(m.status=='yield' and m.yielded[1]==3 and m.yielded[2].native_ref==alias.native_ref)
 local before=serpent.line(m,{sortkeys=true})
 Execution.run(m,b,nil,0)
 check('native leased call operands stay unchanged at zero credit',serpent.line(m,{sortkeys=true})==before)
 Collector.start(m); Collector.step(m,19)
 local legacy=Execution.new(legacy_bundle); Execution.install_core(legacy); Execution.service(legacy,'pause')
 -- Exercise the synchronized path, including genuine compiler-1 reconstruction.
 while legacy.status=='running' do Dispatch.run(legacy,17,function() return true end,services) end
 assert(legacy.status=='yield' and legacy_bundle.source_version.compiler==1)
 Collector.start(legacy); Collector.step(legacy,7)
 return {machine=m,bundle=b,alias=alias,frame=m.frames[1],temps=m.frames[1].t,blocks=m.blocks,collection=m.collection_work,
  legacy={machine=legacy,bundle=legacy_bundle,alias=legacy.yielded[1],blocks=legacy.blocks,collection=legacy.collection_work}}
end
function M.reload(state,check)
 local m=state.machine
 check('native cold load retains leased receiver and counters',m.status=='yield' and m.frames[1]==state.frame and state.frame.t==state.temps
  and m.blocks==state.blocks and m.collection_work==state.collection and m.collector~=nil)
 while m.collector do Collector.step(m,11) end
 Execution.resume(m,{n=4,3,state.alias,nil,false})
 run(m,state.bundle,1)
 check('native suspended leases retain earlier RHS and reference once',m.status=='return' and m.result.n==5
  and m.result[1]==2*100+3*10+7 and m.result[2]==2 and m.result[3].native_ref==state.alias.native_ref
  and m.result[4]==nil and m.result[5]==false)
 local old=state.legacy
 m=old.machine
 check('native compiler-1 cold graph remains unmodified',m.status=='yield' and m.bundle==old.bundle and old.bundle.source_version.compiler==1
  and m.blocks==old.blocks and m.collection_work==old.collection and m.collector~=nil)
 while m.collector do Collector.step(m,11) end
 Execution.resume(m,{n=0})
 Dispatch.clear_cache()
 while m.status=='running' do Dispatch.run(m,1,function() return true end) end
 check('native compiler-1 continuation resumes retained generated layout',m.status=='return' and m.result.n==4
  and m.result[1]==7 and m.result[2]==nil and m.result[3]==false and m.result[4].native_ref==old.alias.native_ref)
end
return M
