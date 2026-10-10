-- Shipped editors launched by the actual BIOS and shell, not host load.
local Boot=require('__computer_core_2__.scripts.native.boot')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Events=require('__computer_core_2__.scripts.native.events')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Model=require('__computer_core_2__.scripts.filesystem')
local Terminal=require('__computer_core_2__.scripts.native.terminal')
local Display=require('__computer_core_2__.scripts.guest.terminal')
local TimerChecks=require('editor_timer_checks')
local M={}
local original='abcTAIL\nsecond\n'
local edited='abXM\nN\nO\nPZcTAIL\nsecond\n'
local identity_source=[[
local kind=...
local thread=require('rc.thread')
local h=assert(io.open('/identity.txt','r'))
assert(h:read(2)=='ha')
native_editor_identity={marker='editor-identity',handle=h,alias=h,coro=coroutine.running(),
 thread=thread.id(),tab=thread.getCurrentTab(),vars=thread.vars(),window=thread.getTerm()}
assert(loadfile('/rc/editors/'..kind..'.lua'))('/note.lua')
local result=native_editor_identity.alias:read(3)
assert(result=='ndl')
h:close()
local out=assert(io.open('/identity-after-'..kind,'w'))
out:write(result); out:close()
]]
local function identity(m)
 for id,value in pairs(m.heap) do
  if value.kind=='table' and value.values.smarker=='editor-identity' then
   local v=value.values
   local raw=Execution.get(m,v.shandle,'handle') -- Authentic rc.io wrapper.
   local service=m.heap[Execution.get(m,raw,'read').native_ref]
   return {proof=id,receiver=v.shandle.native_ref,alias=v.salias.native_ref,handle=service.data.handle.native_ref,
    coro=v.scoro.native_ref,thread=v.sthread,tab=v.stab,vars=v.svars.native_ref,window=v.swindow.native_ref,
    size_method=Execution.get(m,v.swindow,'getSize').native_ref}
  end
 end
 error('missing actual editor identity probe')
end
local function screen(m)
 local rows={}; for i,line in ipairs(m.display.lines) do rows[i]=line.text end
 return table.concat(rows,'\n')
end
local function footer(m,text) return m.display.lines[m.display.rows].text:sub(1,#text)==text end
local function editor_wait(m,kind)
 for _,object in pairs(m.heap) do
  if object.kind=='thread' and object.status=='suspended' then
   for _,frame in ipairs(object.frames) do
    local bundle=Execution.bundle_for(m,frame.bundle_id)
    if bundle.name=='=/rc/editors/'..kind..'.lua' then return true end
   end
  end
 end
 return false
end
local function fresh(m)
 for i=#m.display.lines,1,-1 do
  local text=m.display.lines[i].text
  if text:find('%S') then return text:match('^/>%s*$')~=nil end
 end
 return false
end
local function step(s) TimerChecks.step(s) end
local function pump(s,predicate,label)
 local m=s.machines[1]
 for _=1,3000 do
  if predicate(m) and m.status=='yield' then return end
  if m.host_request or m.status=='error' or m.status=='recovery' then
   log('CC2 NATIVE EDITOR FAILURE '..serpent.line({label=label,status=m.status,error=m.error,recovery=m.recovery,
    request=m.host_request,blocks=m.blocks,objects=m.objects,budget=s.budget.machines[1],screen=screen(m)}))
   error('native shipped editor failed: '..label)
  end
  step(s)
 end
 log('CC2 NATIVE EDITOR DEADLINE '..serpent.line({label=label,status=m.status,error=m.error,request=m.host_request,
  blocks=m.blocks,objects=m.objects,screen=screen(m),cursor={m.display.x,m.display.y}}))
 error('native shipped editor deadline: '..label)
end
local function send(s,event) assert(Events.admit(s.machines[1],event)) end
local function key(s,id) send(s,{n=2,'key',id}) end
local function command(s,text)
 for i=1,#text do send(s,{n=2,'char',text:sub(i,i)}); for _=1,16 do step(s) end end
 pump(s,function(m) return screen(m):find('/> '..text,1,true)~=nil end,'shell command '..text)
 key(s,257)
end
local function body(m)
 return m.display.lines[1].text:sub(1,4)=='abXM' and m.display.lines[2].text:match('^N%s*$')
  and m.display.lines[3].text:match('^O%s*$') and m.display.lines[4].text:sub(1,7)=='PZcTAIL'
  and m.display.lines[5].text:sub(1,6)=='second'
end
local function launch(s,kind)
 local command_text=kind=='basic' and '/rc/editors/basic.lua /note.lua' or 'edit /note.lua'
 command(s,command_text)
 pump(s,function(m) return editor_wait(m,kind) and footer(m,kind=='basic' and 'Press Control for menu' or 'Press Ctrl for menu') end,
  kind..' ready')
end
local ui={pump=pump,send=send,key=key,body=body,wait=editor_wait,footer=footer}
function M.run(check)
 local sessions={}
 for _,kind in ipairs({'basic','advanced'}) do
  local m=Boot.new({fs={['/']={type='dir'},['/note.lua']={type='file',text=original},
   ['/native_edit.lua']={type='file',text=identity_source},['/identity.txt']={type='file',text='handle-identity'}}})
  local s=Scheduler.new(); Scheduler.add(s,1,m)
  pump(s,fresh,kind..' BIOS shell boot'); launch(s,kind)
  check('native shipped '..kind..' editor loads committed file through real shell and suspended application frames',
   m.display.lines[1].text:sub(1,7)=='abcTAIL' and m.display.lines[2].text:sub(1,6)=='second' and editor_wait(m,kind))
  key(s,262); key(s,262) -- two right-arrow events, pinned lwjgl3
  send(s,{n=2,'char','X'})
  pump(s,function(m) return editor_wait(m,kind) and m.display.lines[1].text:sub(1,8)=='abXcTAIL' end,kind..' middle character')
  check('native shipped '..kind..' middle insertion preserves suffix and dirty disk',m.disk.fs['/note.lua'].text==original
   and m.display.x==4 and m.display.y==1)
  send(s,{n=2,'paste','M\r\nN\rO\nP'})
  pump(s,function(m) return editor_wait(m,kind) and m.display.lines[4].text:sub(1,6)=='PcTAIL' end,kind..' multiline CRLF paste')
  check('native shipped '..kind..' paste normalizes CRLF and CR without losing multiline suffix or cursor',
   m.display.lines[1].text:sub(1,4)=='abXM' and m.display.lines[2].text:match('^N%s*$')
   and m.display.lines[3].text:match('^O%s*$') and m.display.x==2 and m.display.y==4
   and m.disk.fs['/note.lua'].text==original)
  send(s,{n=2,'char','Z'})
  pump(s,function(m) return editor_wait(m,kind) and body(m) end,kind..' post-paste insertion')
  check('native shipped '..kind..' post-paste character follows new cursor and preserves shifted original line',
   m.display.x==3 and m.display.y==4 and m.disk.fs['/note.lua'].text==original)
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' dirty menu')
  send(s,{n=2,'char','e'})
  pump(s,function(m) return footer(m,'Lose unsaved work? E:yes C:no') and editor_wait(m,kind) end,kind..' dirty exit confirmation')
  check('native shipped '..kind..' editor retains dirty flag and protects unsaved work at exit',body(m) and m.disk.fs['/note.lua'].text==original)
  send(s,{n=2,'char','c'}); for _=1,40 do step(s) end
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' save menu')
  send(s,{n=2,'char','s'})
  pump(s,function(m) return m.disk.fs['/note.lua'].text==edited and footer(m,'Saved to /note.lua') and editor_wait(m,kind) end,kind..' save')
  check('native shipped '..kind..' save commits exact multiline edited bytes and closes handles',m.open_handles==0)
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' saved exit menu')
  send(s,{n=2,'char','e'}); pump(s,fresh,kind..' return to shell')
  launch(s,kind)
  check('native shipped '..kind..' editor reopens saved file through actual source loader and file iterators',body(m)
   and m.display.x==1 and m.display.y==1 and m.disk.fs['/note.lua'].text==edited)
  -- Labelled pressure setup: real disk capacity, real guest save and error path.
  local bytes=0; for _,node in pairs(m.disk.fs) do if node.type=='file' then bytes=bytes+#node.text end end
  m.disk.fs['/quota-fill']={type='file',text=string.rep('x',Model.max_bytes-bytes)}
  send(s,{n=2,'char','F'})
  pump(s,function(m) return editor_wait(m,kind) and m.display.lines[1].text:sub(1,5)=='FabXM' end,kind..' quota draft')
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' quota save menu')
  send(s,{n=2,'char','s'})
  pump(s,function(m) return footer(m,'Save failed: ') and editor_wait(m,kind) end,kind..' protected disk quota')
  check('native shipped '..kind..' protected save quota retains committed file and editable dirty draft without staged-prefix commit',
   m.disk.fs['/note.lua'].text==edited and m.display.lines[1].text:sub(1,5)=='FabXM' and m.open_handles==0 and m.handle_bytes==0)
  send(s,{n=2,'char','Q'})
  pump(s,function(m) return editor_wait(m,kind) and m.display.lines[1].text:sub(1,6)=='FQabXM' end,kind..' editable refused draft')
  check('native shipped '..kind..' quota failure does not terminate application or lose editing cursor',
   m.display.x==3 and m.display.y==1 and m.disk.fs['/note.lua'].text==edited)
  key(s,259); key(s,259)
  pump(s,function(m) return editor_wait(m,kind) and body(m) and m.display.x==1 end,kind..' quota retry draft')
  m.disk.fs['/quota-fill']=nil -- Release the labelled external pressure.
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' quota retry menu')
  send(s,{n=2,'char','s'})
  pump(s,function(m) return footer(m,'Saved to /note.lua') and editor_wait(m,kind) end,kind..' quota recovery save')
  check('native shipped '..kind..' editor saves again after quota pressure is removed with no leaked handles',
   m.disk.fs['/note.lua'].text==edited and m.open_handles==0 and m.handle_bytes==0)
  TimerChecks.run(s,kind,check,ui,edited)
  sessions[kind]=s
 end
 return sessions
end
function M.suspend(sessions,check)
 local snapshots={}
 for _,kind in ipairs({'basic','advanced'}) do
  local s=sessions[kind]; local m=s.machines[1]
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' identity launch menu')
  send(s,{n=2,'char','e'}); pump(s,fresh,kind..' identity launch shell')
  command(s,'native_edit '..kind)
  pump(s,function(m) return editor_wait(m,kind) and footer(m,kind=='basic' and 'Press Control for menu' or 'Press Ctrl for menu') end,
   kind..' actual identity caller ready')
  send(s,{n=2,'char','!'})
  pump(s,function(m) return editor_wait(m,kind) and m.display.lines[1].text:sub(1,5)=='!abXM' end,kind..' dirty reopen')
  key(s,264); key(s,264); key(s,262)
  -- Moving down preserves the horizontal column; right is clamped by redraw.
  pump(s,function(m) return editor_wait(m,kind) and m.display.y==3 and m.display.x==2 end,kind..' saved cursor movement')
  TimerChecks.hold(s)
  send(s,{n=2,'char','Q'})
  pump(s,function(m) return editor_wait(m,kind) and m.display.lines[3].text:sub(1,2)=='OQ' end,kind..' unsaved collected snapshot')
  check('native shipped '..kind..' editor snapshot retains unsaved multiline draft and moved cursor separately from disk',
   m.disk.fs['/note.lua'].text==edited and m.display.x==3 and m.display.y==3)
  Collector.start(m)
  snapshots[kind]={scheduler=s,tick=s.budget.tick,blocks=m.blocks,screen=screen(m),next_timer=m.events.next_timer,
   columns=m.display.columns,rows=m.display.rows,identity=identity(m),timers=TimerChecks.suspend(s,kind,check)}
  local ids=snapshots[kind].identity
  check('native shipped '..kind..' suspended caller retains actual coroutine tab window alias and open handle offset',
   ids.receiver==ids.alias and m.heap[ids.handle].offset==2 and m.open_handles==1 and m.heap[ids.coro].kind=='thread')
 end
 return snapshots
end
function M.reload(snapshots,check)
 local final='!abXM\nN\nOQR\nPZcTAIL\nsecond\n'
 for _,kind in ipairs({'basic','advanced'}) do
  local snapshot=snapshots[kind]; local s=snapshot.scheduler; local m=s.machines[1]
  check('native cold shipped '..kind..' editor load preserves dirty display cursor disk frames and timer counter',
   m.blocks==snapshot.blocks and screen(m)==snapshot.screen and m.display.x==3 and m.display.y==3
   and m.disk.fs['/note.lua'].text==edited and m.events.next_timer==snapshot.next_timer and m.collector~=nil)
  check('native cold shipped '..kind..' editor preserves actual coroutine tab vars window methods and handle identities',
   serpent.line(identity(m),{sortkeys=true})==serpent.line(snapshot.identity,{sortkeys=true})
   and m.heap[snapshot.identity.handle].offset==2 and m.open_handles==1)
  TimerChecks.loaded(m,snapshot.timers,kind,check)
  local columns,rows=Display.dimensions()
  Scheduler.begin_tick(s,snapshot.tick+1)
  local changed=Terminal.reconcile_configured(m,function(domain,amount) return Scheduler.consume(s,1,domain,amount) end)
  check('native shipped '..kind..' reconciles actual startup geometry without guest execution or replacing display identity',
   changed==(columns~=snapshot.columns or rows~=snapshot.rows) and m.display.columns==columns and m.display.rows==rows
   and m.blocks==snapshot.blocks and m.heap[snapshot.identity.handle].offset==2)
  if changed then
   pump(s,function(m) return editor_wait(m,kind) and footer(m,kind=='basic' and 'Press Control for menu' or 'Press Ctrl for menu')
    and m.display.lines[1].text:sub(1,5)=='!abXM' and m.display.lines[3].text:sub(1,2)=='OQ' end,kind..' event-only settings resize')
   check('native shipped '..kind..' settings resize redraws dirty editor at new footer without a character event',
    m.display.x==3 and m.display.y==3 and m.disk.fs['/note.lua'].text==edited
    and serpent.line(identity(m),{sortkeys=true})==serpent.line(snapshot.identity,{sortkeys=true}))
  end
  TimerChecks.reload(s,snapshot.timers,kind,check,ui,edited)
  send(s,{n=2,'char','R'})
  pump(s,function(m) return editor_wait(m,kind) and m.display.lines[3].text:sub(1,3)=='OQR' end,kind..' cold dirty cursor resume')
  check('native collected shipped '..kind..' editor resumes input at saved cursor without replay or draft loss',
   m.display.x==4 and m.display.y==3 and m.display.lines[1].text:sub(1,5)=='!abXM'
   and m.disk.fs['/note.lua'].text==edited)
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' cold dirty exit menu')
  send(s,{n=2,'char','e'})
  pump(s,function(m) return footer(m,'Lose unsaved work? E:yes C:no') and editor_wait(m,kind) end,kind..' cold dirty flag')
  check('native cold shipped '..kind..' editor retains unsaved exit protection',m.disk.fs['/note.lua'].text==edited)
  send(s,{n=2,'char','c'}); for _=1,40 do step(s) end
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' cold save menu')
  send(s,{n=2,'char','s'})
  pump(s,function(m) return m.disk.fs['/note.lua'].text==final and footer(m,'Saved to /note.lua') and editor_wait(m,kind) end,
   kind..' cold draft save')
  check('native shipped '..kind..' editor commits saved dirty draft and new input exactly once after cold reload',m.open_handles==1)
  key(s,341)
  pump(s,function(m) return footer(m,'S:save  E:exit') and editor_wait(m,kind) end,kind..' identity readback exit menu')
  send(s,{n=2,'char','e'})
  pump(s,function(m) return fresh(m) and m.disk.fs['/identity-after-'..kind]~=nil end,kind..' held offset readback')
  check('native shipped '..kind..' actual caller resumes held handle at saved offset and releases it after editor exit',
   m.disk.fs['/identity-after-'..kind].text=='ndl' and m.open_handles==0 and m.handle_bytes==0)
 end
end
return M
