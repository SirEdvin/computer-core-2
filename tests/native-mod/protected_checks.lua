local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local cases = {
 {'protected result nil arity','return pcall(function() return 1,nil,3,nil end)'},
 {'protected reference error','local e={}; local ok,err=pcall(function() error(e) end); return ok,err==e'},
 {'protected nil error','return pcall(function() error(nil) end)'},
 {'protected false error','return pcall(function() error(false) end)'},
 {'numeric level zero error','return pcall(error,1,0)'},
 {'nested protected errors','local e={}; return pcall(function() local ok,err=pcall(function() error(e) end); assert(not ok and err==e); return 7,nil end)'},
 {'handled reference error','local e={}; return xpcall(function() error(e) end,function(err) return err==e,7 end)'},
 {'handler failure','return xpcall(function() error("first") end,function() error("second") end)'},
 {'handler protected failure','return xpcall(function() error(1) end,function(e) local ok=pcall(function() error(2) end); return e,ok end)'},
 {'metatable table index','local base={x=7}; local t=setmetatable({},{__index=base}); return t.x,t.y'},
 {'metatable callback index','local n=0; local t=setmetatable({},{__index=function(_,k) n=n+1; return k,n end}); return t.x,t.y,n'},
 {'metatable callback setter','local n=0; local t=setmetatable({},{__newindex=function(obj,k,v) n=n+v; rawset(obj,k,v+1) end}); t.x=3; t.x=t.x+2; return t.x,n'},
 {'metatable setter table','local backing={}; local t=setmetatable({},{__newindex=backing}); t.x=4; return t.x,backing.x'},
 {'metatable callable','local t=setmetatable({v=4},{__call=function(self,x) return self.v+x,nil end}); return t(3)'},
 {'metatable protection false','local t=setmetatable({},{__metatable=false}); local ok=pcall(setmetatable,t,{}); return getmetatable(t),ok'},
 {'wrapped reference error','local e={}; local f=coroutine.wrap(function() error(e) end); local ok,err=pcall(f); return ok,err==e'},
}
local function equal(a,b)
 if not a or a.n~=b.n then return false end
 for i=1,a.n do if a[i]~=b[i] then return false end end
 return true
end
local function run(source, credits)
 local b=assert(Compiler.compile(source,'=native-protected'))
 local m=Execution.new(b); Execution.install_core(m)
 local blocks=Execution.executable(b)
 local turns=0
 repeat Execution.run(m,b,blocks,credits or 23); turns=turns+1 until m.status~='running' or turns>2000
 assert(m.status~='error',m.error and m.error.message)
 return m,b
end
return {
 run=function(check)
  for _,case in ipairs(cases) do
   -- Trusted fixed-source reference; not application loading.
   local env={pcall=pcall,xpcall=xpcall,error=error,assert=assert,setmetatable=setmetatable,getmetatable=getmetatable,rawset=rawset}
   local result
   if case[1]=='wrapped reference error' then result=table.pack(false,true)
   else result=table.pack(assert(load(case[2],'=native-protected','t',env))()) end
   local m=run(case[2])
   if not equal(m.result,result) then
    log('CC2 NATIVE PROTECTED MISMATCH '..case[1]..' native_n='..tostring(m.result and m.result.n)..' reference_n='..result.n)
    for i=1,math.max(m.result and m.result.n or 0,result.n) do
     log('CC2 NATIVE PROTECTED VALUE '..i..' native='..tostring(m.result and m.result[i])..' ('..type(m.result and m.result[i])..') reference='..tostring(result[i])..' ('..type(result[i])..')')
    end
   end
   check('native protected/metamethod semantics '..case[1],m.status=='return' and equal(m.result,result))
  end
  local source='local function f(n) if n==0 then error("deep") end; return f(n-1)+1 end; return pcall(f,200)'
  local b=assert(Compiler.compile(source,'=native-deep-cleanup'))
  local m=Execution.new(b); Execution.install_core(m)
  local blocks=Execution.executable(b)
  local turns,cleanup=0,0
  repeat
   local c=m.heap[m.active]
   local before=m.cleanup_work or 0
   if c.pending and c.pending.kind=='unwind' then
    local old=c.pending.cursor
    Execution.run(m,b,blocks,0)
    assert(c.pending.cursor==old)
    cleanup=cleanup+1
   end
   Execution.run(m,b,blocks,1)
   assert((m.cleanup_work or 0)-before<=256)
   turns=turns+1
  until m.status~='running' or turns>20000
  check('native deep exception cleanup spans bounded paid steps',m.status=='return' and m.result[1]==false and type(m.result[2])=='string' and cleanup>200)
  local m2=run('local t={}; setmetatable(t,{__index=t}); local ok,e=pcall(function() return t.x end); return ok,type(e)')
  check('native cyclic index delegation is bounded and protected',m2.result[1]==false and m2.result[2]=='string')
  m2=run('local ok=pcall(setmetatable,{},{__eq=function() return true end}); return ok')
  check('native unsupported metamethod refuses rather than changing semantics',m2.result[1]==false)
  m2=run('local mt={}; setmetatable({},mt); local ok=pcall(rawset,mt,"__eq",function() return true end); return ok,rawget(mt,"__eq")')
  check('native late metatable mutation cannot install unsupported behavior',m2.result.n==2 and m2.result[1]==false and m2.result[2]==nil)
 end,
 suspend=function(check)
  local b=assert(Compiler.compile([[
local e={value=7}
local effects=0
local t=setmetatable({}, {__index=function(_,key)
 effects=effects+1
 local extra=pause("index",key,nil)
 error(e)
end})
local ok,result=xpcall(function() return t.missing end,function(err)
 assert(err==e)
 local v=pause("handler",err,nil)
 effects=effects+v
 return err
end)
return ok,result==e,effects,nil
]],'=native-protected-reload'))
  local m=Execution.new(b); Execution.install_core(m); Execution.service(m,'pause')
  local services={pause=function(_,args) return 'yield',args end}
  Execution.run(m,b,Execution.executable(b),1000,services)
  check('native protected index callback yields with ownership retained',m.status=='yield' and equal(m.yielded,table.pack('index','missing',nil)))
  Execution.resume(m,table.pack(2))
  Execution.run(m,b,Execution.executable(b),1000,services)
  check('native error handler suspends with reference-valued error',m.status=='yield' and m.yielded.n==3 and m.yielded[1]=='handler' and Execution.get(m,m.yielded[2],'value')==7)
  return {machine=m,bundle=b}
 end,
 reload=function(state,check)
  local m=state.machine
  check('native saved protected handler boundary stays live',m.status=='yield' and m.heap[m.active].boundaries[1].phase=='handler')
  Execution.resume(m,table.pack(3,nil))
  local status=Execution.run(m,state.bundle,Execution.executable(state.bundle),1000)
  check('native protected handler resumes reference identity exactly once',status=='return' and equal(m.result,table.pack(false,true,4,nil)))
 end,
}
