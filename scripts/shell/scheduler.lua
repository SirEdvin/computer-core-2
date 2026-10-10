-- Direct event-shell stepper; production VM/shell traversal supplies one ledger.
-- No independent aggregate allowance or persisted executable dispatcher.
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Events=require('__computer_core_2__.scripts.guest.events')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
local function callback(ledger,id)
  return function(cost) return Budget.admit(ledger,id,cost) end
end
function M.new(disk,columns,rows,ledger,id,tick)
  Budget.begin(ledger,tick)
  return Shell.new(disk,columns,rows,callback(ledger,id))
end
function M.push(state,ledger,id,tick,event)
  if not Shell.valid_event(event) or event[1]=='boot' or event[1]=='advance' or event[1]=='timer' then
    return false,'unsupported input event'
  end
  if state.status=='initializing' and (event[1]=='char' or event[1]=='paste' or event[1]=='key') then return false,'initializing' end
  if state.status=='initializing' and (event[1]=='reboot' or event[1]=='shutdown') then return false,'initializing' end
  if state.status=='stopped' and (event[1]=='char' or event[1]=='paste' or event[1]=='key') then return false,'stopped' end
  Budget.begin(ledger,tick)
  local bytes=0
  for i=1,event.n do
    if type(event[i])=='string' then bytes=bytes+#event[i]
    elseif type(event[i])=='number' then bytes=bytes+8 else bytes=bytes+1 end
  end
  local priority=event[1]=='term_resize' or event[1]=='terminate' or event[1]=='reboot' or event[1]=='shutdown'
  if priority then
    if #state.events.queue>=Limits.events or state.events.bytes+bytes>Limits.event_bytes then return false,'event queue full' end
    bytes=bytes+3*#state.events.queue -- Reserve insertion shifts before publication.
  end
  if not Budget.admit(ledger,id,{event=1+4*event.n+bytes}) then return false,'work deferred' end
  return Events.admit(state.events,event,nil,priority)
end
function M.start_timer(state,ledger,id,tick,seconds)
  Budget.begin(ledger,tick)
  assert(type(seconds)=='number' and seconds>=0 and seconds<=86400,'invalid shell timer duration')
  assert(state.events.timer_count<Limits.timers,'shell timer quota exceeded')
  assert(state.events.tick<=tick,'shell timer clock cannot move backwards')
  if not Budget.admit(ledger,id,{event=1}) then return nil,'work deferred' end
  state.events.tick=tick -- A timer starts at its admitted request tick, not the last powered dispatch.
  return Events.start_timer(state.events,seconds)
end
function M.cancel_timer(state,ledger,id,tick,timer)
  Budget.begin(ledger,tick)
  if not Budget.admit(ledger,id,{event=1+3*#state.events.queue}) then return false,'work deferred' end
  Events.cancel_timer(state.events,timer)
  return true
end
function M.step(state,ledger,id,tick,powered)
  Budget.begin(ledger,tick)
  if not Shell.compatible(state) then return Shell.handle(state,{n=1,'advance'},callback(ledger,id)) end
  local first=state.events.queue[1]
  local control=first and (first.tuple[1]=='term_resize' or first.tuple[1]=='terminate' or first.tuple[1]=='reboot' or first.tuple[1]=='shutdown')
  if powered==false or state.status=='stopped' and not control or state.status=='recovery' or Budget.remaining(ledger,id,'execution')==0 then return false end
  if state.status=='boot' or state.status=='initializing' and not control then return Shell.handle(state,{n=1,'boot'},callback(ledger,id)) end
  local refused={}
  local ok,err=pcall(Events.advance,state.events,tick,function(amount)
    if not Budget.admit(ledger,id,{advance=amount}) then error(refused,0) end
  end)
  if not ok and err~=refused then error(err,0) end
  -- Jobs own their immutable arguments; later ordinary input remains queued.
  local record=state.events.queue[1]
  if state.job and not control then
    return Shell.handle(state,{n=1,'advance'},callback(ledger,id))
  end
  if not record then return false end
  local count=#state.events.queue
  local events=state.events
  local handled,reason=Shell.handle(state,record.tuple,function(cost)
    cost.event=(cost.event or 0)+1+3*count
    return Budget.admit(ledger,id,cost)
  end)
  if handled and state.events==events then
    table.remove(state.events.queue,1)
    state.events.bytes=state.events.bytes-record.bytes
  end
  return handled,reason
end
return M
