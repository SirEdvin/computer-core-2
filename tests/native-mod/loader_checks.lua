local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Events=require('__computer_core_2__.scripts.native.events')
local FS=require('__computer_core_2__.scripts.native.filesystem')
local Loader=require('__computer_core_2__.scripts.native.loader')
local Dispatch=require('__computer_core_2__.scripts.native.dispatch')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function disk(text)
 return {fs={['/']={type='dir'},['/module.lua']={type='file',text=text or 'return {value=17},nil'}}}
end
local function create(source,input)
 local m=Execution.new(assert(Compiler.compile(source,'=native-loader')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m); FS.install(m,input or disk())
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,150 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('native loader fixture deadline exceeded')
end
local function load(m,source,env,admit)
 local _,result=Loader.services(admit or function() return true end).load(m,{n=4,source,'=loaded','t',env})
 return result
end
local function collect(m)
 Collector.start(m); while m.collector do Collector.step(m,32) end
end
return {
 run=function(check)
  local s,m=create([[
local env={value=4}
local first=assert(load('value=value+1; return function(n) value=value+n; return value,nil end','=one','t',env))()
local second=assert(load('return value','=two','bt',env))
local value,absent=first(3)
local module=dofile('/module.lua')
local fresh=assert(loadfile('/module.lua'))()
return value,absent,second(),module.value,fresh.value,env.value,game,require,package,debug.getinfo,type(debug.traceback)
]])
  finish(s,10)
  check('native dynamic load file and module execution use explicit shared guest environments',m.status=='return'
   and m.result.n==11 and m.result[1]==8 and m.result[2]==nil and m.result[3]==8 and m.result[4]==17
   and m.result[5]==17 and m.result[6]==8 and m.result[7]==nil and m.result[8]==nil
   and m.result[9]==nil and m.result[10]==nil and m.result[11]=='function')
  s,m=create([[
local module=assert(loadfile('/rc/modules/main/rc/copy.lua'))()
local value={a={leaf=7}}; value.b=value.a; value.self=value
local copy=module.copy(value)
return copy~=value,copy.a~=value.a,copy.a==copy.b,copy.self==copy,copy.a.leaf,type(module.copy)
]])
  finish(s,200)
  check('native ROM load executes real shipped copy module with closure and cycle semantics',m.status=='return'
   and m.result[1] and m.result[2] and m.result[3] and m.result[4] and m.result[5]==7 and m.result[6]=='function')
  s,m=create([[
local a,why=load('broken syntax ???','=bad')
local b,binary=load(string.char(27)..'Lua','=binary','bt')
local c=load('return 1','=mode','b')
local d=load(function() return 'return 1' end)
local e,missing=loadfile('/missing')
local f=pcall(dofile,'/missing')
local g=pcall(load,'return 1','=env','t',true)
return a,why,b,binary,c,d,e,missing,f,g,assert(load('return 9'))()
]])
  finish(s,400)
  check('native loader rejects syntax binary reader invalid environment and missing files then recovers',m.status=='return'
   and m.result[1]==nil and type(m.result[2])=='string' and m.result[3]==nil and type(m.result[4])=='string'
   and m.result[5]==nil and m.result[6]==nil and m.result[7]==nil and type(m.result[8])=='string'
   and m.result[9]==false and m.result[10]==false and m.result[11]==9)
  for _,domain in ipairs({'compiler','continuation'}) do
   s,m=create('return 1'); Scheduler.begin_tick(s,600)
   local before=m.objects
   assert(Scheduler.consume(s,1,domain,Scheduler.remaining(s,1,domain)))
   local result=load(m,'return 1',nil,function(kind,amount) return Scheduler.consume(s,1,kind,amount) end)
   check('native loader exhausted '..domain..' cannot publish closure or bundle',result[1]==nil and type(result[2])=='string'
    and m.objects==before and m.bundles==nil and Scheduler.remaining(s,1,domain)==0)
  end
  s,m=create('return 1'); local before=m.objects
  local result=load(m,string.rep('x',Limits.source_bytes+1))
  check('native oversized source rejects without allocation or execution',result[1]==nil and m.objects==before and m.bundles==nil)
  Scheduler.begin_tick(s,700)
  assert(Scheduler.consume(s,1,'filesystem',Scheduler.remaining(s,1,'filesystem')))
  local _,result=Loader.services(function(kind,amount) return Scheduler.consume(s,1,kind,amount) end).loadfile(m,{n=1,'/module.lua'})
  check('native file source admission is separate from compiler admission',result[1]==nil and m.bundles==nil
   and m.objects==before and (s.budget.used.compiler or 0)==0)
  s,m=create('return 1')
  local saved=load(m,'return 1')[1]; local kept=m.heap[saved.native_ref].bundle_id
  m.external_roots={saved}
  for i=1,20 do assert(load(m,'return '..i)[1]) end
  collect(m)
  check('native collection retains live source and removes unreachable loaded bundles',m.bundles[kept]~=nil and m.bundles[3]==nil)
  local ref=load(m,'return 29')[1]
  check('native bounded registry safely reuses reclaimed source slot',m.heap[ref.native_ref].bundle_id==3)
  -- Legacy collections lack a complete bundle-mark inventory; never discard
  -- sources whose closures may have been visited before the update.
  Collector.start(m); m.collector.bundles=nil
  while m.collector do Collector.step(m,32) end
  check('native legacy mid-collection source preservation is conservative',m.bundles[3]~=nil and m.bundles[kept]~=nil)
  collect(m)
  check('native subsequent full collection reclaims legacy-preserved dead source',m.bundles[3]==nil and m.bundles[kept]~=nil)
  s,m=create('return 1'); m.external_roots={}
  for i=2,Limits.call_frames do
   local ref=load(m,'return 1')[1]; assert(ref); m.external_roots[#m.external_roots+1]=ref
  end
  local count=m.objects; local refused=load(m,'return 2')
  check('native retained-source quota is bounded before publication',refused[1]==nil and m.objects==count
   and m.collect_at<=m.objects)
  m.external_roots=nil; collect(m)
  check('native source quota recovery releases unreachable registry entries',load(m,'return 2')[1]~=nil)
  s,m=create("return assert(load(\"coroutine.yield('frame-only'); return 31\"))()")
  finish(s,900); assert(m.status=='yield')
  local frame_id=m.frames[1].bundle_id; local frame_bundle=m.bundles[frame_id]
  collect(m)
  check('native loaded tail-call frame alone retains its source after closure reclamation',m.bundles[frame_id]==frame_bundle)
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,1100,true)
  check('native frame-only source resumes after collection without dangling bundle id',m.status=='return' and m.result[1]==31)
  s,m=create('return 1')
  local maximum=string.rep(' ',Limits.source_bytes-8)..'return 7'
  local accepted=load(m,maximum)
  check('native exact maximum source uses unchanged compiler byte allowance',accepted[1]~=nil
   and #m.bundles[m.heap[accepted[1].native_ref].bundle_id].source==Limits.source_bytes)
 end,
 suspend=function(check)
  local source="initial=(initial or 0)+1; local data={value=initial}; coroutine.yield('module-wait',data,nil); return data,initial,nil"
  local s,m=create("boot=(boot or 0)+1; local data,n,absent=dofile('/module.lua'); return data.value,n,boot,absent",disk(source))
  finish(s,game.tick); assert(m.status=='yield')
  local value=m.yielded[2]; local id=m.frames[#m.frames].bundle_id
  local original=m.bundles[id]
  -- Editing committed bytes while a source snapshot is active must affect
  -- only later loads, never the saved continuation.
  m.disk.fs['/module.lua']={type='file',text='return 99,nil'}
  assert(Scheduler.consume(s,1,'compiler',Scheduler.remaining(s,1,'compiler')))
  Collector.start(m)
  check('native dofile suspension retains active module source and nil yield arity',m.yielded.n==3
   and original.source==source and Execution.get(m,value,'value')==1)
  return {scheduler=s,tick=s.budget.tick,original=original,id=id,value=value,blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native source reload retains bundle aliases snapshots and no initializer replay',m.bundles[state.id]==state.original
   and m.blocks==state.blocks and m.yielded[2].native_ref==state.value.native_ref
   and Scheduler.remaining(s,1,'compiler')==0)
  Dispatch.clear_cache()
  local count=m.objects
  local refused=load(m,'return 2',nil,function(kind,amount) return Scheduler.consume(s,1,kind,amount) end)
  check('native same-tick reload cannot publish a newly compiled chunk',refused[1]==nil and m.objects==count
   and Scheduler.remaining(s,1,'compiler')==0)
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,state.tick+1,true)
  check('native collected dofile resumes cold snapshotted frames without reading edited file',m.status=='return'
   and m.result.n==4 and m.result[1]==1 and m.result[2]==1 and m.result[3]==1
   and m.result[4]==nil and m.bundles[state.id].source==state.original.source)
  Scheduler.begin_tick(s,state.tick+200)
  local _,result=Loader.services(function(kind,amount) return Scheduler.consume(s,1,kind,amount) end).loadfile(m,{n=1,'/module.lua'})
  check('native subsequent file load selects current edited bytes not active source snapshot',result[1]~=nil
   and m.bundles[m.heap[result[1].native_ref].bundle_id].source=='return 99,nil')
 end,
}
