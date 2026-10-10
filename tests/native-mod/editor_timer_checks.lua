-- Observations of authentic BIOS/editor timers; no replacement guest modules.
local Execution=require('__computer_core_2__.scripts.native.execution')
local Events=require('__computer_core_2__.scripts.native.events')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local M={}
local audits=setmetatable({}, {__mode='k'})
function M.hold(s) audits[s]={starts={},cancelled={},freeze=true}; return audits[s] end
function M.step(s)
 local tick=(s.budget and s.budget.tick or 0)+1
 local audit=audits[s]; local services
 if audit then
  Scheduler.begin_tick(s,tick)
  if audit.freeze then
   -- Labelled maintenance-pressure setup, not relaxed guest/execution budgets.
   assert(Scheduler.consume(s,1,'advance',Scheduler.remaining(s,1,'advance')))
  end
  local real=Events.services(function(amount)
   assert(Scheduler.consume(s,1,'event',amount),'native event work quota exceeded')
  end)
  services={}
  services['os.startTimer']=function(m,args)
   local status,result=real['os.startTimer'](m,args)
   assert(#audit.starts<64,'editor timer observer bound exceeded')
   audit.starts[#audit.starts+1]={id=result[1],seconds=args[1],coro=m.active}
   return status,result
  end
  services['os.cancelTimer']=function(m,args)
   local status,result=real['os.cancelTimer'](m,args)
   audit.cancelled[args[1]]=(audit.cancelled[args[1]] or 0)+1
   return status,result
  end
 end
 Scheduler.tick(s,tick,services)
end
local function context(m,kind)
 local editor,shell,rc
 for id,value in pairs(m.heap) do
  if value.kind=='thread' then
   for _,frame in ipairs(value.frames) do
    if Execution.bundle_for(m,frame.bundle_id).name=='=/rc/editors/'..kind..'.lua' then editor=id end
   end
  elseif value.kind=='table' and value.values.s_NAME=='Recrafted' then rc={native_ref=id} end
 end
 assert(editor and rc,'missing actual editor/rc timer context')
 local editor_id,shell_id
 for _,value in pairs(m.heap) do
  if value.kind=='table' then
   local v=value.values
   if type(v.scoro)=='table' and v.sid then
    if v.scoro.native_ref==editor then editor_id=v.sid end
    if v.sname=='shell' then shell=v.scoro.native_ref; shell_id=v.sid end
   end
  end
 end
 assert(editor_id and shell and shell_id and editor_id~=shell_id,'missing distinct actual OS thread identities')
 local start=m.heap[Execution.get(m,rc,'startTimer').native_ref]
 local cancel=m.heap[Execution.get(m,rc,'cancelTimer').native_ref]
 local owners
 -- The BIOS start/cancel closures share precisely the real timer_filter cell.
 for _,a in ipairs(start.upvalues) do
  for _,b in ipairs(cancel.upvalues) do
   if a==b then
    local value=m.heap[a].value
    if type(value)=='table' and m.heap[value.native_ref].kind=='table' then
     assert(not owners,'ambiguous timer ownership cell'); owners=value.native_ref
    end
   end
  end
 end
 assert(owners,'missing authentic BIOS shared timer ownership table')
 return {editor=editor,editor_id=editor_id,shell=shell,shell_id=shell_id,owners=owners}
end
local function owner(m,c,id) return Execution.get(m,{native_ref=c.owners},id) end
local function queued(m,id)
 for _,record in ipairs(m.events.queue) do
  if record.tuple[1]=='timer' and record.tuple[2]==id then return true end
 end
 return false
end
local function owned(m,c,thread)
 for id in pairs(m.events.timers) do if owner(m,c,id)==thread then return id end end
 for _,record in ipairs(m.events.queue) do
  if record.tuple[1]=='timer' and owner(m,c,record.tuple[2])==thread then return record.tuple[2] end
 end
end
function M.run(s,kind,check,ui,edited)
 local m=s.machines[1]; local c=context(m,kind); local audit=M.hold(s)
 if not owned(m,c,c.shell_id) then
  local frames={}; for _,f in ipairs(m.heap[c.shell].frames) do frames[#frames+1]={name=Execution.bundle_for(m,f.bundle_id).name,pc=f.pc} end
  log('CC2 EDITOR TIMER CONTEXT '..serpent.line({kind=kind,context=c,timers=m.events.timers,
   queue=m.events.queue,owners=m.heap[c.owners].values,status=m.heap[c.shell].status,frames=frames}))
 end
 local peer=assert(owned(m,c,c.shell_id),'shell polling timer missing')
 for i=1,6 do
  ui.send(s,{n=2,'char',('local '):sub(i,i)})
  local expected=('local '):sub(1,i)..'abXM'
  ui.pump(s,function(m) return ui.wait(m,kind) and m.display.lines[1].text:sub(1,#expected)==expected end,
   kind..' timer ownership plaintext')
 end
 local own=owned(m,c,c.editor_id)
 -- An already queued shell wakeup may have been consumed while typing; use its real renewed timer.
 peer=assert(owned(m,c,c.shell_id),'renewed shell polling timer missing')
 local observed_peer=false
 for _,record in ipairs(audit.starts) do
  if record.id==peer then observed_peer=record.coro==c.shell and record.seconds==0.05 end
 end
 check('native actual '..kind..' editor peer timer originates in shipped shell polling on its distinct native coroutine',observed_peer)
 if kind=='advanced' then
  local created={}
  for _,record in ipairs(audit.starts) do
   if record.coro==c.editor then
    assert(record.seconds==0.2,'editor timer is not shipped debounce'); created[#created+1]=record.id
   end
  end
  local cancelled=#created==6
  for i=1,#created-1 do
   local id=created[i]
   cancelled=cancelled and audit.cancelled[id]==1 and m.events.timers[id]==nil and owner(m,c,id)==nil and not queued(m,id)
  end
  check('native actual advanced editor replaces and cancels each earlier highlight timer before publication',
   cancelled and own==created[#created] and owner(m,c,own)==c.editor_id)
  check('native actual advanced editor echoes keyword plaintext while highlight and shell timers remain distinct',
   own~=peer and owner(m,c,peer)==c.shell_id and m.display.lines[1].foreground:sub(1,5)=='00000')
 else
  check('native actual basic editor has no debounce timer and does not acquire shell timer ownership',
   own==nil and owner(m,c,peer)==c.shell_id)
 end
 audit.freeze=false
 ui.pump(s,function(m)
  return owner(m,c,peer)==nil and m.events.timers[peer]==nil and not queued(m,peer)
   and (not own or owner(m,c,own)==nil and m.events.timers[own]==nil and not queued(m,own))
   and ui.wait(m,kind) and (kind=='basic' or m.display.lines[1].foreground:sub(1,5)=='11111')
 end,kind..' actual owned timer delivery')
 check('native actual '..kind..' editor isolates shell polling while owned timers preserve dirty text cursor and disk',
  m.display.lines[1].text:sub(1,10)=='local abXM' and m.display.x==7 and m.display.y==1
  and m.disk.fs['/note.lua'].text==edited and owned(m,c,c.shell_id)~=nil)
 audits[s]=nil
 for _=1,6 do ui.key(s,259) end
 ui.pump(s,function(m) return ui.wait(m,kind) and ui.body(m) and m.display.x==1 end,kind..' timer restored text')
 ui.key(s,341)
 ui.pump(s,function(m) return ui.footer(m,'S:save  E:exit') and ui.wait(m,kind) end,kind..' timer restore menu')
 ui.send(s,{n=2,'char','s'})
 ui.pump(s,function(m) return ui.footer(m,'Saved to /note.lua') and ui.wait(m,kind) end,kind..' timer restored save')
end
function M.suspend(s,kind,check)
 local m=s.machines[1]; local c=context(m,kind)
 c.own=owned(m,c,c.editor_id); c.peer=assert(owned(m,c,c.shell_id),'saved shell timer missing')
 check('native shipped '..kind..' editor saves authentic timer ownership beside shell polling during collection',
  kind=='basic' and c.own==nil or kind=='advanced' and c.own~=nil and c.own~=c.peer)
 c.timers=serpent.line(m.events.timers,{sortkeys=true})
 c.owners_state=serpent.line(m.heap[c.owners].values,{sortkeys=true})
 audits[s]=nil
 return c
end
function M.loaded(m,c,kind,check)
 check('native cold shipped '..kind..' editor preserves pending timer deadlines and exact OS ownership without load-time consumption',
  serpent.line(m.events.timers,{sortkeys=true})==c.timers
  and serpent.line(m.heap[c.owners].values,{sortkeys=true})==c.owners_state
  and owner(m,c,c.peer)==c.shell_id and (not c.own or owner(m,c,c.own)==c.editor_id))
end
function M.reload(s,c,kind,check,ui,edited)
 local m=s.machines[1]
 ui.pump(s,function(m) return ui.wait(m,kind) and owner(m,c,c.peer)==nil and not queued(m,c.peer)
  and (not c.own or owner(m,c,c.own)==nil and not queued(m,c.own)) end,kind..' cold timer ownership delivery')
 check('native cold shipped '..kind..' editor consumes owned timers while shell polling renews and draft cursor remain stable',
  m.events.timers[c.peer]==nil and (not c.own or m.events.timers[c.own]==nil)
  and owned(m,c,c.shell_id)~=nil and m.display.x==3 and m.display.y==3
  and m.display.lines[3].text:sub(1,2)=='OQ' and m.disk.fs['/note.lua'].text==edited)
end
return M
