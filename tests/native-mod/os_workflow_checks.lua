-- Actual BIOS/shell application tests, with local guest programs as callers.
-- No replacement OS modules or host-loaded guest functions.
local Events=require('__computer_core_2__.scripts.native.events')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local M={}
local probe=[[
local rc=require('rc')
local thread=require('rc.thread')
local function mark(name,text)
 local f=assert(io.open('/probe-'..name,'w'))
 f:write(text or 'ready'); f:close()
end
local child=coroutine.create(function()
 local value,absent=coroutine.yield('private-child',nil,17)
 assert(value==23 and absent==nil)
 return value,nil
end)
local yielded=table.pack(coroutine.resume(child))
assert(yielded.n==4 and yielded[1] and yielded[2]=='private-child' and yielded[3]==nil and yielded[4]==17)
local resumed=table.pack(coroutine.resume(child,23,nil))
assert(resumed.n==3 and resumed[1] and resumed[2]==23 and resumed[3]==nil)
mark('nested')
thread.spawn(function()
 local id=rc.startTimer(0.05)
 local name,received=rc.pullEvent('timer')
 assert(name=='timer' and received==id)
 mark('peer-timer',tostring(id)..':'..tostring(received))
end,'native-timer-peer')
local own=rc.startTimer(0.05)
local cancelled=rc.startTimer(0)
rc.cancelTimer(cancelled)
local name,received=rc.pullEvent('timer')
assert(name=='timer' and received==own and received~=cancelled)
mark('timer',tostring(own)..':'..tostring(received)..':'..tostring(cancelled))
mark('normal-ready')
local sig=table.pack(rc.pullEvent('probe-normal'))
assert(sig.n==4 and sig[1]=='probe-normal' and sig[2]==false and sig[3]==29 and sig[4]==nil)
mark('normal-result')
mark('terminate-ready')
local ok,err=pcall(rc.pullEvent,'probe-never')
assert(not ok and err=='terminated')
mark('terminate-result')
mark('raw-ready')
sig=table.pack(rc.pullEventRaw('probe-raw'))
assert(sig.n==5 and sig[1]=='probe-raw' and sig[2]==false and sig[3]==nil and sig[4]==31 and sig[5]==nil)
mark('raw-result')
mark('raw-unfiltered-ready')
sig=table.pack(rc.pullEventRaw())
assert(sig.n==1 and sig[1]=='terminate')
mark('raw-unfiltered-result')
]]
function M.disk()
 return {fs={['/']={type='dir'},['/aaa.lua']={type='file',text='return 41\n'},
  ['/alpha.lua']={type='file',text='return 42\n'},['/alpine.lua']={type='file',text='return 43\n'},
  ['/native_wait_probe.lua']={type='file',text=probe},['/workspace']={type='dir'}}}
end
local function screen(m)
 local rows={}; for i,line in ipairs(m.display.lines) do rows[i]=line.text end
 return table.concat(rows,'\n')
end
local function fresh(m)
 for i=#m.display.lines,1,-1 do
  local text=m.display.lines[i].text
  if text:find('%S') then return text:match('^/>%s*$')~=nil end
 end
 return false
end
local function step(s)
 Scheduler.tick(s,s.budget.tick+1)
end
local function pump(s,condition,label)
 local m=s.machines[1]
 for _=1,3000 do
  if condition(m) and m.status=='yield' then return end
  assert(not m.host_request and m.status~='error' and m.status~='recovery',label..': '..tostring(m.error or m.recovery))
  step(s)
 end
 log('CC2 NATIVE OS WORKFLOW DEADLINE '..serpent.line({label=label,status=m.status,error=m.error,
  request=m.host_request,blocks=m.blocks,screen=screen(m),files=m.disk.fs}))
 error('native actual OS workflow deadline: '..label)
end
local function key(s,id)
 assert(Events.admit(s.machines[1],{n=2,'key',id}))
end
local function text(s,value,expected)
 local m=s.machines[1]
 for i=1,#value do assert(Events.admit(m,{n=2,'char',value:sub(i,i)})); for _=1,16 do step(s) end end
 pump(s,function(m) return screen(m):find(expected,1,true)~=nil end,'character input '..value)
end
local function no_queued(m,name)
 for _,record in ipairs(m.events.queue) do if record.tuple[1]==name then return false end end
 return true
end
local function marker(m,name) return m.disk.fs['/probe-'..name] end
local function wait_marker(s,name)
 pump(s,function(m) return marker(m,name)~=nil end,name)
end
function M.run(s,check)
 local m=s.machines[1]
 pump(s,fresh,'initial shell wait')
 text(s,'copy ','/> copy aaa.lua ')
 check('native actual shell empty filename prefix produces a candidate without corrupting the command',
  screen(m):find('/> copy aaa.lua ',1,true)~=nil and not m.host_request)
 key(s,258) -- pinned lwjgl3 Tab, accept candidate into the actual readline buffer
 for _=1,80 do step(s) end
 text(s,'/copied-empty.lua','/> copy aaa.lua /copied-empty.lua')
 key(s,257)
 pump(s,function(m) return m.disk.fs['/copied-empty.lua'] and fresh(m) end,'empty prefix copy')
 check('native actual shell Tab accepts empty-prefix candidate and shipped copy executes exact source',
  m.disk.fs['/copied-empty.lua'].text==m.disk.fs['/aaa.lua'].text)
 text(s,'copy al','/> copy alpha.lua ')
 key(s,258)
 for _=1,80 do step(s) end
 text(s,'/copied-prefix.lua','/> copy alpha.lua /copied-prefix.lua')
 key(s,257)
 pump(s,function(m) return m.disk.fs['/copied-prefix.lua'] and fresh(m) end,'nonempty prefix copy')
 check('native actual shell character-by-character nonempty filename completion preserves source and destination',
  m.disk.fs['/copied-prefix.lua'].text==m.disk.fs['/alpha.lua'].text)
 text(s,'cd /workspace','/> cd /workspace')
 key(s,257)
 pump(s,function(m)
  for i=#m.display.lines,1,-1 do
   local value=m.display.lines[i].text
   if value:find('%S') then return value:match('^/workspace>%s*$')~=nil end
  end
 end,'changed working directory')
 check('native actual shell builtin cd updates thread directory and prompt',screen(m):find('/workspace> ',1,true)~=nil)
 text(s,'cd /','/workspace> cd /')
 key(s,257)
 pump(s,fresh,'restored root directory')
 check('native actual shell builtin cd restores root before subsequent source loading',fresh(m))
 text(s,'native_wait_probe','/> native_wait_probe')
 key(s,257)
 wait_marker(s,'normal-ready'); wait_marker(s,'peer-timer')
 check('native actual OS nested application yields return to their resumer rather than host event filters',marker(m,'nested')~=nil)
 local own,received,cancelled=marker(m,'timer').text:match('^(%d+):(%d+):(%d+)$')
 local peer,peer_received=marker(m,'peer-timer').text:match('^(%d+):(%d+)$')
 local cancelled_queued=false
 for _,record in ipairs(m.events.queue) do
  if record.tuple[1]=='timer' and tostring(record.tuple[2])==cancelled then cancelled_queued=true end
 end
 check('native actual Recrafted timer ownership separates application peers and shell polling and cancels pending timer',
  own and own==received and peer==peer_received and own~=peer and cancelled~=own
  and m.events.timers[tonumber(cancelled)]==nil and not cancelled_queued)
 assert(Events.admit(m,{n=2,'probe-other','ignored'}))
 pump(s,function(m) return no_queued(m,'probe-other') end,'normal unrelated event')
 check('native actual Recrafted normal wait rejects unrelated event',marker(m,'normal-result')==nil)
 assert(Events.admit(m,{n=4,'probe-normal',false,29,nil}))
 wait_marker(s,'terminate-ready')
 check('native actual Recrafted normal filtered wait preserves false and trailing nil arity',marker(m,'normal-result')~=nil)
 assert(Events.admit(m,{n=1,'terminate'}))
 wait_marker(s,'raw-ready')
 check('native actual Recrafted normal wait terminates before applying its filter under protected recovery',marker(m,'terminate-result')~=nil)
 assert(Events.admit(m,{n=1,'terminate'}))
 pump(s,function(m) return no_queued(m,'terminate') end,'raw filtered termination')
 check('native actual Recrafted raw filtered wait ignores unmatched termination rather than throwing',marker(m,'raw-result')==nil)
 assert(Events.admit(m,{n=5,'probe-raw',false,nil,31,nil}))
 wait_marker(s,'raw-unfiltered-ready')
 check('native actual Recrafted raw matching wait preserves interior and trailing nil arity',marker(m,'raw-result')~=nil)
 assert(Events.admit(m,{n=1,'terminate'}))
 wait_marker(s,'raw-unfiltered-result')
 pump(s,fresh,'shell after raw termination')
 check('native actual Recrafted unfiltered raw wait returns termination and shell polling survives application recovery',
  marker(m,'raw-unfiltered-result')~=nil and fresh(m) and not m.host_request)
end
return M
