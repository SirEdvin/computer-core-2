local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local FS=require('__computer_core_2__.scripts.native.filesystem')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-tostring')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m); FS.install(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,150 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('native tostring fixture deadline exceeded')
end
local sentinel=[[
local file=assert(fs.open('/rc/apis/textutils.lua','r'))
local source=file.readAll(); file.close()
local first=assert(source:find('local function mk_',1,true))
local after=assert(source:find('serialize',first,true)) - #('local function ')
local factory=assert(load('local tu={}\n'..source:sub(first,after-1)..'\nreturn tu','=ROM-json-sentinels','t',_ENV))
local tu=factory()
return tostring(tu.empty_json_array),tostring(tu.json_null),pcall(function() tu.json_null.value=1 end)
]]
return {
 run=function(check)
  local s,m=create([[
local count=0
local meta={__tostring=function(value) count=count+1; return value.name,nil,27 end,__metatable='locked'}
local value=setmetatable({name='leaf'},meta)
local first=tostring(value)
meta.__tostring=function() return 'replaced' end
return first,tostring(value),count,getmetatable(value),type(tostring(value)),select('#',tostring(value))
]])
  finish(s,10)
  check('native tostring invokes protected guest metamethod once and scalar-adjusts result',m.status=='return'
   and m.result[1]=='leaf' and m.result[2]=='replaced' and m.result[3]==1 and m.result[4]=='locked'
   and m.result[5]=='string' and m.result[6]==1)
  s,m=create([[
local err={name='sentinel-error'}
local first=setmetatable({},{__tostring=function() error(err,0) end})
local ok,returned=pcall(tostring,first)
local bad=setmetatable({},{__tostring=function() return {} end})
local invalid,why=pcall(tostring,bad)
local empty=setmetatable({},{__tostring=function() end})
local missing=pcall(tostring,empty)
local callable=setmetatable({},{__call=function(_,value) return value.name end})
local wrapped=setmetatable({name='callable'},{__tostring=callable})
return ok,returned==err,invalid,why,missing,tostring(wrapped)
]])
  finish(s,200)
  check('native tostring keeps reference errors validates output and supports guest callable transfer',m.status=='return'
   and m.result[1]==false and m.result[2] and m.result[3]==false and type(m.result[4])=='string'
   and m.result[4]:find('__tostring must return a string',1,true)~=nil and m.result[5]==false and m.result[6]=='callable')
  s,m=create([[
local effects=0
local value=setmetatable({},{__tostring=function(v)
 effects=effects+1
 coroutine.yield('converted',v,nil)
 return 'resumed'
end})
local child=coroutine.create(function() return pcall(tostring,value) end)
local ok,tag,alias,gap=coroutine.resume(child)
local status,protected,text=coroutine.resume(child)
return ok,tag,alias==value,gap,status,protected,text,effects
]])
  finish(s,350)
  check('native protected tostring child callback yields to immediate resumer without replay',m.status=='return'
   and m.result.n==8 and m.result[1] and m.result[2]=='converted' and m.result[3] and m.result[4]==nil
   and m.result[5] and m.result[6] and m.result[7]=='resumed' and m.result[8]==1)
  s,m=create([[
local value=setmetatable({},{__tostring=function(v) return tostring(v) end})
local ok,why=pcall(tostring,value)
return ok,why
]])
  finish(s,500)
  check('native recursive tostring helper nesting fails within existing continuation ceiling',m.status=='return'
   and m.result[1]==false and type(m.result[2])=='string' and m.result[2]:find('native helper nesting quota exceeded',1,true)~=nil)
  s,m=create(sentinel); finish(s,650)
  check('native unchanged ROM JSON sentinel constructors execute through guest source loader',m.status=='return'
   and m.result[1]=='[]' and m.result[2]=='null' and m.result[3]==false)
  s,m=create('return 1'); Scheduler.begin_tick(s,800)
  local value=Execution.table_value(m); local meta=Execution.table_value(m)
  Execution.set(m,meta,'__tostring',Execution.get(m,m.env,'tostring'))
  m.heap[value.native_ref].metatable=meta
  local services=Helpers.services(function(domain,amount) return Scheduler.consume(s,1,domain,amount) end)
  assert(Scheduler.consume(s,1,'table',Scheduler.remaining(s,1,'table')))
  local blocks,objects=m.blocks,m.objects
  check('native zero-credit tostring lookup cannot start guest callback',not pcall(services.tostring,m,table.pack(value))
   and m.blocks==blocks and m.objects==objects and s.budget.used.table==Limits.table_work_per_computer)
  Scheduler.begin_tick(s,801)
  assert(Scheduler.consume(s,1,'string',Scheduler.remaining(s,1,'string')))
  local p={kind='helper',phase='result',values={n=2,'leaf',false}}
  check('native tostring output refusal preserves pending callback result for protected recovery',not pcall(services['native.tostring.step'],m,p)
   and p.phase=='result' and p.values[1]=='leaf' and p.values.n==2)
  Scheduler.begin_tick(s,802)
  local _,result=services['native.tostring.step'](m,p)
  check('native admitted callback output has exact one-string arity',result.n==1 and result[1]=='leaf')
  local maximum=string.rep('x',Limits.string_bytes)
  local _,accepted=services['native.tostring.step'](m,{phase='result',values={n=1,maximum}})
  check('native maximum tostring callback output fits unchanged byte credits',accepted.n==1 and accepted[1]==maximum)
  check('native oversized private tostring result is refused before output publication',not pcall(services['native.tostring.step'],m,
   {phase='result',values={n=1,maximum..'x'}}))
  s,m=create([[
local value={saved=9}
local meta={__index=function() return 'fallback' end}
local protect,set,get,setmeta,getmeta=pcall,rawset,rawget,setmetatable,getmetatable
coroutine.yield('core-ready',value,meta)
return protect(set,value,'saved',99),protect(get,value,'saved'),protect(setmeta,value,meta),protect(getmeta,value)
]])
  finish(s,900); assert(m.status=='yield')
  local value,meta=m.yielded[2],m.yielded[3]
  assert(Scheduler.consume(s,1,'table',Scheduler.remaining(s,1,'table')))
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,s.budget.tick,true)
  check('native zero-credit core table services fail through guest protection without metadata mutation',m.status=='return'
   and m.result[1]==false and m.result[2]==false and m.result[3]==false and m.result[4]==false
   and Execution.get(m,value,'saved')==9 and m.heap[value.native_ref].metatable==nil
   and not m.heap[meta.native_ref].used_as_metatable and s.budget.used.table==Limits.table_work_per_computer)
  s,m=create([[
local value={}
local meta={__tostring=function() return 'leaf' end}
local protect,setmeta=pcall,setmetatable
coroutine.yield('meta-ready',value,meta)
return protect(setmeta,value,meta)
]])
  finish(s,1100); assert(m.status=='yield')
  value,meta=m.yielded[2],m.yielded[3]
  assert(Scheduler.consume(s,1,'string',Scheduler.remaining(s,1,'string')))
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,s.budget.tick,true)
  check('native refused metamethod name scan cannot publish target or used-metatable flags',m.status=='return'
   and m.result[1]==false and m.heap[value.native_ref].metatable==nil and not m.heap[meta.native_ref].used_as_metatable)
  s,m=create([[
local value={}
local meta={__tostring=function() return 'leaf' end}
coroutine.yield('maximum-meta',value,meta)
return setmetatable(value,meta)==value,tostring(value)
]])
  finish(s,1300); assert(m.status=='yield')
  value,meta=m.yielded[2],m.yielded[3]
  for i=1,Limits.table_keys-1 do Execution.set(m,meta,'key'..i,i) end
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,1500,true)
  check('native maximum metatable scan succeeds within unchanged bounded table credits',m.status=='return'
   and m.result[1] and m.result[2]=='leaf' and m.heap[meta.native_ref].used_as_metatable
   and s.budget.used.table>=16+4*Limits.table_keys and s.budget.used.table<=Limits.table_work_per_computer)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local value={name='saved-object'}
local alias=value
setmetatable(value,{__tostring=function(v)
 effects=(effects or 0)+1
 tostring=nil
 coroutine.yield('string-wait',v,nil)
 return v.name
end})
local ok,text=pcall(tostring,value)
return ok,text,alias.name,boot,effects,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  local value=m.yielded[2]
  assert(Scheduler.consume(s,1,'string',Scheduler.remaining(s,1,'string')))
  Collector.start(m)
  check('native tostring save retains object alias helper receiver and removed public callback entry',m.yielded.n==3
   and Execution.get(m,m.env,'tostring')==nil and Execution.get(m,value,'name')=='saved-object')
  return {scheduler=s,tick=s.budget.tick,value=value,blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native tostring load retains identity exhausted output credits and no callback replay',m.blocks==state.blocks
   and m.yielded[2].native_ref==state.value.native_ref and Scheduler.remaining(s,1,'string')==0)
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,state.tick+1,true)
  check('native collected protected tostring resumes once with exact alias result and nil tuple',m.status=='return'
   and m.result.n==6 and m.result[1] and m.result[2]=='saved-object' and m.result[3]=='saved-object'
   and m.result[4]==1 and m.result[5]==1 and m.result[6]==nil)
 end,
}
