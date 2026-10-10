-- Guest-authored adversarial inputs, executed by generated code and the real OS.
local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Events=require('__computer_core_2__.scripts.native.events')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Filesystem=require('__computer_core_2__.scripts.native.filesystem')
local Terminal=require('__computer_core_2__.scripts.native.terminal')
local M={}
local program=[[
sandbox_stage='host-globals'
local forbidden={'game','script','remote','storage','defines','prototypes','helpers','commands','rendering','rcon'}
for _,key in ipairs(forbidden) do assert(_G[key]==nil) end
assert(debug.getregistry==nil and debug.getinfo==nil and debug.sethook==nil and debug.getupvalue==nil)
assert(getfenv==nil and setfenv==nil and collectgarbage==nil)
assert(io.popen==nil and io.tmpfile==nil and os.execute==nil and os.getenv==nil and os.exit==nil)
sandbox_stage='load-environment'
local f=assert(load('return game,script,remote,storage,defines,prototypes','=escape','t',setmetatable({},{__index=_G})))
local values=table.pack(f()); assert(values.n==6)
for i=1,6 do assert(values[i]==nil) end
local private={value=17}
local g=assert(load('value=value+1; return value,game,_G','=private','t',private))
local value,host,global=g(); assert(value==18 and host==nil and global==nil and private.value==18)
sandbox_stage='load-rejections'
local binary=load(string.char(27)..'Lua','=binary','bt'); assert(binary==nil)
local reader=load(function() return 'return game' end); assert(reader==nil)
assert(not pcall(string.dump,f))
sandbox_stage='metatables'
local guarded=setmetatable({},{__metatable=false,__index=function() return game end})
assert(getmetatable(guarded)==false and guarded.hidden==nil)
assert(not pcall(setmetatable,guarded,{}) and not pcall(rawset,term.write,'data',{}))
assert(getmetatable(term.write)==nil and not pcall(function() return term.write.name end))
local fake={native_ref=1}; fake.native_ref=999999
assert(type(fake)=='table' and rawget(fake,'native_ref')==999999 and fake.game==nil)
sandbox_stage='handles'
local h=assert(fs.open('/sandbox-local','w'))
assert(type(h.write)=='function' and getmetatable(h.write)==nil)
assert(not pcall(rawget,h.write,'data'))
h.write('local-only'); h.close()
local rows=fs.list('/'); rows[1]='changed-by-guest'
assert(fs.exists('/sandbox-local') and not fs.exists('/changed-by-guest'))
assert(not fs.open('/rc/bios.lua','w'))
return true
]]
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-sandbox')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 Execution.set(m,m.env,'_G',m.env)
 Filesystem.install(m,{fs={['/']={type='dir'}}}); Terminal.install(m,51,19)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
function M.run(check)
 local s,m=create(program)
 for tick=1,200 do Scheduler.tick(s,tick); if m.status~='running' then break end end
 if m.status~='return' then log('CC2 NATIVE SANDBOX FAILURE '..serpent.line({stage=Execution.get(m,m.env,'sandbox_stage'),status=m.status,error=m.error,recovery=m.recovery})) end
 check('native compiled adversarial load environment metatable handle and helper probes expose no host state',
  m.status=='return' and m.result[1]==true and m.disk.fs['/sandbox-local'].text=='local-only')
 local b=assert(Compiler.compile('return pcall(probe)','=native-return-boundary'))
 local cases={
  {'function',function() return function() end end},
  {'engine-object',function() return game end},
  {'raw-host-table',function() return {game=game} end},
  {'forged-reference',function() return {native_ref=999999999} end},
  {'reference-with-host-fields',function(m) return {native_ref=m.env.native_ref,payload=game} end},
  {'metatable-reference',function(m) return setmetatable({},{__index=function() return m.env.native_ref end}) end},
 }
 for _,case in ipairs(cases) do
  local machine=Execution.new(b); Execution.install_core(machine); Execution.service(machine,'probe')
  local _,spent=Execution.run(machine,b,Execution.executable(b),1000,{probe=function() return 'return',{n=1,case[2](machine)} end})
  check('native protected service return rejects '..case[1]..' without retaining privileged value',
   spent<=1000 and machine.status=='return' and machine.result[1]==false and type(machine.result[2])=='string')
 end
 local machine=Execution.new(b); Execution.install_core(machine); Execution.service(machine,'probe')
 local private
 -- Use a genuine nonpublic environment cell, not a fabricated private ID.
 for id,obj in pairs(machine.heap) do if obj.kind=='cell' then private=id; break end end
 assert(private,'fixture has no real environment cell')
 Execution.run(machine,b,Execution.executable(b),1000,{probe=function() return 'return',{n=1,{native_ref=private}} end})
 check('native service return cannot expose private heap cells',machine.status=='return' and machine.result[1]==false)
 local tuples={
  {'extra-host-field',function() return {n=1,true,payload=game} end},
  {'metatable',function() return setmetatable({n=1,true},{__index=function() return game end}) end},
 }
 for _,case in ipairs(tuples) do
  local target=Execution.new(b); Execution.install_core(target); Execution.service(target,'probe')
  Execution.run(target,b,Execution.executable(b),1000,{probe=function() return 'return',case[2]() end})
  check('native protected service tuple rejects '..case[1]..' without guest-visible host metadata',
   target.status=='return' and target.result[1]==false and type(target.result[2])=='string')
 end
end
local function prompt(m)
 for i=#m.display.lines,1,-1 do
  local text=m.display.lines[i].text
  if text:find('%S') then return text:match('^/[%w_/%-]*>%s*$')~=nil end
 end
 return false
end
function M.os(s,check)
 local m=s.machines[1]
 local source="local fs=require('fs'); local term=require('term'); local io=require('rc.io')\nlocal ok,why=pcall(function()\n"..program:gsub('return true\n?$','')..[[
assert(package.loadlib==nil and package.cpath=='')
for _,name in ipairs({'ffi','socket','__computer_core_2__.control','../../control'}) do
 local ok,value=pcall(require,name); assert(not ok and type(value)=='string')
end
local result=assert(io.open('/sandbox-result','w')); result:write('confined'); result:close()
end)
if not ok then
 local report=assert(fs.open('/sandbox-error','w')); report.write(tostring(sandbox_stage)..':'..tostring(why)); report.close()
 error(why,0)
end
]]
 -- Labelled local application fixture, loaded by the shipped shell/package path.
 m.disk.fs['/native_sandbox.lua']={type='file',text=source}
 local command='/native_sandbox.lua'
 for i=1,#command do
  assert(Events.admit(m,{n=2,'char',command:sub(i,i)}))
  for _=1,16 do Scheduler.tick(s,s.budget.tick+1) end
 end
 assert(Events.admit(m,{n=2,'key',257}))
 for _=1,3000 do
  Scheduler.tick(s,s.budget.tick+1)
  if m.disk.fs['/sandbox-result'] and prompt(m) and m.status=='yield' then break end
  assert(m.status~='error' and m.status~='recovery' and not m.host_request,'actual OS sandbox probe failed')
 end
 if not m.disk.fs['/sandbox-result'] then log('CC2 NATIVE SANDBOX OS FAILURE '..serpent.line({diagnostic=m.disk.fs['/sandbox-error'],status=m.status})) end
 check('native actual shipped shell modules and late IO remain confined under adversarial guest loading',
  m.disk.fs['/sandbox-result'] and m.disk.fs['/sandbox-result'].text=='confined' and prompt(m) and m.open_handles==0)
end
return M
