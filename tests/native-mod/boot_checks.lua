local Boot=require('__computer_core_2__.scripts.native.boot')
local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Events=require('__computer_core_2__.scripts.native.events')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Workflows=require('os_workflow_checks')
local Sandbox=require('sandbox_checks')
local function display(m)
 local rows={}; for i,line in ipairs(m.display.lines) do rows[i]=line.text end
 return table.concat(rows,'\n')
end
local function fresh_prompt(m)
 for i=#m.display.lines,1,-1 do
  local text=m.display.lines[i].text
  if text:find('%S') then return text:match('^/>%s*$')~=nil end
 end
 return false
end
local function advance(s,count)
 for _=1,count do Scheduler.tick(s,s.budget.tick+1) end
end
local function type_text(s,text,expected)
 local m=s.machines[1]
 for i=1,#text do Events.admit(m,{n=2,'char',text:sub(i,i)}); advance(s,16) end
 for _=1,1200 do
  if display(m):find(expected,1,true) and m.status=='yield' then return end
  advance(s,1)
 end
end
local function standalone(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-host-services')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
return {
run=function(check)
 local s,m=standalone([[
local identity={};local trace=debug.traceback
local ok,value=xpcall(function() error(identity) end,trace)
return trace(identity)==identity,not ok,value==identity,trace(),trace(false),trace(7),trace('message'),
 debug.getinfo,debug.sethook,debug.getregistry
]])
 Scheduler.tick(s,110)
 check('native traceback stub preserves protected reference identity and scalar results without privileged debug facilities',
  m.status=='return' and m.result.n==10 and m.result[1] and m.result[2] and m.result[3]
  and m.result[4]=='guest traceback' and m.result[5]==false and m.result[6]==7 and m.result[7]=='message'
  and m.result[8]==nil and m.result[9]==nil and m.result[10]==nil)
 local charge={}
 local trace=Helpers.services(function(domain,amount) charge[domain]=(charge[domain] or 0)+amount end)['debug.traceback']
 local maximum=string.rep('x',Limits.string_bytes)
 local _,result=trace(m,{n=1,maximum})
 check('native traceback stub admits maximum immutable message without host stringification',result[1]==maximum
  and charge.string==Limits.string_bytes and charge.continuation==5)
 check('native traceback stub rejects oversized message and exhausted admission',not pcall(trace,m,{n=1,maximum..'x'})
  and not pcall(Helpers.services(function() return false end)['debug.traceback'],m,{n=1,'refused'}))
 s,m=standalone('return os.clock(),os.getComputerID()')
 m.computer_id=17
 Scheduler.tick(s,120)
 check('native clock and computer identity use simulation time and trusted scalar identity',m.status=='return'
  and m.result[1]==2 and m.result[2]==17 and s.budget.used.event==2)
 for _,name in ipairs({'clock','getComputerID'}) do
  check('native '..name..' refuses exhausted event admission',not pcall(
   Events.services(function() error('fixture event credit refused') end)['os.'..name],m,{n=0}))
 end
 for _,request in ipairs({'shutdown','reboot'}) do
  s,m=standalone('os.'..request..'(); after=true; while true do end')
  Scheduler.tick(s,130)
  local blocks=m.blocks
  Scheduler.tick(s,131)
  check('native '..request..' request stops remaining guest work and subsequent admission',m.host_request==request
   and Execution.get(m,m.env,'after')==nil and m.blocks==blocks and s.budget.used.execution==0)
  local before=m.host_request
  local services=Events.services(function() error('fixture event credit refused') end)
  check('native '..request..' refuses before host request publication',not pcall(services['os.'..request],m,{n=0})
   and m.host_request==before)
 end
 m=Boot.new(Workflows.disk(),{columns=48,rows=18}); s=Scheduler.new(); Scheduler.add(s,1,m)
 local prompt=false
 for tick=1,3000 do
  Scheduler.tick(s,tick)
  local rows={}; for i,line in ipairs(m.display.lines) do rows[i]=line.text end
  if table.concat(rows,'\n'):find('/> ',1,true) then prompt=true; break end
  if m.status=='error' or m.status=='recovery' or m.host_request then break end
 end
 local rows={}; for i,line in ipairs(m.display.lines) do rows[i]=line.text end
 log('CC2 NATIVE OS BOOT '..serpent.line({status=m.status,error=m.error,recovery=m.recovery,request=m.host_request,
  blocks=m.blocks,objects=m.objects,tick=s.budget.tick,display=table.concat(rows,'\n')}))
 check('native actual shipped BIOS package scheduler and shell reach prompt',prompt)
 check('native actual OS retained source loading and allowed environment preserve ROM globals',m.bundles~=nil
  and Execution.get(m,m.env,'_RC_ROM_DIR')=='/rc' and Execution.get(m,m.env,'game')==nil)
 advance(s,20)
 Workflows.run(s,check)
 Sandbox.os(s,check)
 return s
end,
suspend=function(s,check)
 type_text(s,'mkdir /native','/> mkdir /native')
 local m=s.machines[1]
 log('CC2 NATIVE OS PARTIAL '..serpent.line({status=m.status,error=m.error,recovery=m.recovery,request=m.host_request,
  blocks=m.blocks,tick=s.budget.tick,display=display(m)}))
 check('native actual shell retains partial character-by-character command before save',display(m):find('/> mkdir /native',1,true)~=nil
  and m.disk.fs['/native-saved']==nil and not m.host_request and m.status=='yield')
 Collector.start(m); while m.collector do Collector.step(m,32) end
 return s
end,
reload=function(s,check)
 local m=s.machines[1]
 check('native actual shell cold reload preserves partial command display and has no completed command effects',
  display(m):find('/> mkdir /native',1,true)~=nil and m.disk.fs['/native-saved']==nil)
 type_text(s,'-saved','/> mkdir /native-saved')
 Events.admit(m,{n=2,'key',257}) -- pinned lwjgl3 enter
 for _=1,1200 do
  if m.disk.fs['/native-saved'] and m.status=='yield' and fresh_prompt(m) then break end
  advance(s,1)
 end
 log('CC2 NATIVE OS RESUMED '..serpent.line({status=m.status,error=m.error,recovery=m.recovery,request=m.host_request,
  blocks=m.blocks,tick=s.budget.tick,display=display(m),files=m.disk.fs}))
 check('native actual shell resumes saved readline and executes shipped directory command',m.disk.fs['/native-saved']~=nil
  and m.disk.fs['/native-saved'].type=='dir' and not m.host_request and display(m):find('/> mkdir /native-saved',1,true)~=nil)
 check('native actual BIOS scheduler returns to shell wait after resumed directory command',m.status=='yield'
  and fresh_prompt(m))
end
}
