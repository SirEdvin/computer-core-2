local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local cases = {
  {'yield resume nil arity', [[
local c=coroutine.create(function(a,b,c)
  local x,y,z=coroutine.yield(a,b,c,nil)
  return x,y,z,nil
end)
local s=coroutine.status(c)
local ok,a,b,c1,d=coroutine.resume(c,1,nil,3)
local waiting=coroutine.status(c)
local ok2,x,y,z,last=coroutine.resume(c,4,nil,6)
local dead=coroutine.status(c)
return s,ok,a,b,c1,d,waiting,ok2,x,y,z,last,dead
]]},
  {'parent child ownership', [[
local x=0
local child=coroutine.create(function()
 x=x+1
 local v=coroutine.yield(7,nil)
 x=x+v
 return x,nil
end)
local parent=coroutine.create(function()
 local ok,a,b=coroutine.resume(child)
 local v=coroutine.yield(ok,a,b,nil)
 local ok2,c,d=coroutine.resume(child,v)
 return ok2,c,d,nil
end)
local a,b,c,d,e=coroutine.resume(parent)
local f,g,h,i,j=coroutine.resume(parent,4)
return a,b,c,d,e,f,g,h,i,j,x
]]},
  {'running main identity', 'local a,main=coroutine.running(); return type(a),main,coroutine.status(a)'},
  {'running child identity', 'local c; c=coroutine.create(function() local r,m=coroutine.running(); return r==c,m,coroutine.status(r) end); return coroutine.resume(c)'},
  {'normal parent status', 'local parent; local child=coroutine.create(function() return coroutine.status(parent) end); parent=coroutine.create(function() return coroutine.resume(child) end); return coroutine.resume(parent)'},
  {'dead coroutine', 'local c=coroutine.create(function() return 1 end); local ok=coroutine.resume(c); local ok2,err=coroutine.resume(c); return ok,ok2,type(err),coroutine.status(c)'},
  {'non function child failure', 'local c=coroutine.create(function() local x=nil; x() end); local ok,err=coroutine.resume(c); return ok,type(err),coroutine.status(c)'},
  {'wrap nil arity', 'local f=coroutine.wrap(function(a) local b,c=coroutine.yield(a,nil,7,nil); return b,c,nil end); local a,b,c,d=f(2); local x,y,z=f(4,nil); return a,b,c,d,x,y,z'},
  {'deep tail recursion', 'local function f(n,s) if n==0 then return s,nil end; return f(n-1,s+1) end; return f(500,0)'},
}
-- Reference tuples are explicit because Factorio has no host coroutines. These
-- cases execute native-generated code, never a guest VM used as a fallback.
local results = {
  table.pack('suspended',true,1,nil,3,nil,'suspended',true,4,nil,6,nil,'dead'),
  table.pack(true,true,7,nil,nil,true,true,5,nil,nil,5),
  table.pack('thread',true,'running'),
  table.pack(true,true,false,'running'),
  table.pack(true,true,'normal'),
  table.pack(true,false,'string','dead'),
  table.pack(false,'string','dead'),
  table.pack(2,nil,7,nil,4,nil,nil),
  table.pack(500,nil),
}
local function equal(a,b)
  if not a or a.n~=b.n then return false end
  for i=1,a.n do if a[i]~=b[i] then return false end end
  return true
end
return {
 run=function(check)
  for i,case in ipairs(cases) do
   local bundle=assert(Compiler.compile(case[2],'=native-coroutine-'..case[1]))
   local m=Execution.new(bundle)
   Execution.install_core(m)
   local blocks=Execution.executable(bundle)
   local status, turns=m.status,0
   repeat status=Execution.run(m,bundle,blocks,31); turns=turns+1 until status~='running' or turns>1000
   assert(status~='error',m.error and m.error.message)
   check('native coroutine semantics '..case[1],status=='return' and equal(m.result,results[i]))
  end
  local b=assert(Compiler.compile('return coroutine.resume(1)','=native-invalid-thread'))
  local m=Execution.new(b); Execution.install_core(m)
  check('native coroutine resume rejects non-thread',Execution.run(m,b,Execution.executable(b),100)=='error')
  b=assert(Compiler.compile('local f=coroutine.wrap(function() local x=nil; return x() end); return f()','=native-wrap-error'))
  m=Execution.new(b); Execution.install_core(m)
  check('native wrapped errors propagate to caller',Execution.run(m,b,Execution.executable(b),100)=='error')
  b=assert(Compiler.compile('local c=coroutine.create(function(...) return coroutine.yield(...) end); return coroutine.resume(c,...)','=native-coroutine-maximum-tuple'))
  local args={n=1023}
  m=Execution.new(b,args); Execution.install_core(m)
  local status=Execution.run(m,b,Execution.executable(b),1000)
  check('native coroutine result prefix preserves maximum nil arity',status=='return' and m.result.n==1024 and m.result[1]==true and m.result[1024]==nil)
  b=assert(Compiler.compile('local c=coroutine.create(function(...) return coroutine.yield(1,...) end); return coroutine.resume(c,...)','=native-coroutine-prefix-refusal'))
  m=Execution.new(b,args); Execution.install_core(m)
  status=Execution.run(m,b,Execution.executable(b),1000)
  check('native coroutine oversized status prefix fails in child',status=='return' and m.result.n==2 and m.result[1]==false and type(m.result[2])=='string')
  b=assert(Compiler.compile('local c; c=coroutine.create(function() return coroutine.resume(c) end); return coroutine.resume(c)','=native-coroutine-self'))
  m=Execution.new(b); Execution.install_core(m)
  status=Execution.run(m,b,Execution.executable(b),1000)
  check('native coroutine refuses resuming itself without ownership change',status=='return' and m.result.n==3 and m.result[1]==true and m.result[2]==false)
 end,
 suspend=function(check)
  local bundle=assert(Compiler.compile([[
local x=2
local child=coroutine.create(function()
 local v=coroutine.yield(x,nil,7,nil)
 x=x+v
 return x,nil
end)
local parent=coroutine.create(function()
 local ok,a,b,c,d=coroutine.resume(child)
 local v=coroutine.yield(ok,a,b,c,d,nil)
 return coroutine.resume(child,v)
end)
local ok,a,b,c,d,e,f=coroutine.resume(parent)
local v=pause(ok,a,b,c,d,e,f,nil)
return coroutine.resume(parent,v)
]],'=native-coroutine-reload'))
  local m=Execution.new(bundle); Execution.install_core(m); Execution.service(m,'pause')
  local status=Execution.run(m,bundle,Execution.executable(bundle),1000,{pause=function(_,args) return 'yield',args end})
  check('native nested parent and child both suspended before save',status=='yield' and equal(m.yielded,table.pack(true,true,2,nil,7,nil,nil,nil)))
  return {machine=m,bundle=bundle}
 end,
 reload=function(state,check)
  local m=state.machine
  Execution.resume(m,table.pack(5,nil))
  local status=Execution.run(m,state.bundle,Execution.executable(state.bundle),1000)
  check('native coroutine ownership and nil tuple survive separate process',status=='return' and equal(m.result,table.pack(true,true,7,nil)))
 end,
}
