-- Bounded synchronized event admission. Tuples retain explicit nil arity.
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
function M.new()
  return {version = 1, queue = {}, bytes = 0, timers = {}, timer_count = 0, next_timer = 1, tick = 0, dropped = 0}
end
function M.admit(state, event, objects, priority, spend)
  if type(event) ~= "table" or type(event.n) ~= "number" or event.n < 1 or event.n > Limits.tuple_values or event.n ~= math.floor(event.n) or type(event[1]) ~= "string" then return false, "invalid event tuple" end
  if spend then spend(1 + 4 * event.n) end
  local copy, bytes = {n = event.n}, 0
  for i = 1, event.n do
    local value = event[i]
    if type(value) == "string" then bytes = bytes + #value
    elseif type(value) == "table" then
      if not objects or type(value.ref) ~= "number" or not objects[value.ref] or next(value) ~= "ref" or next(value, "ref") ~= nil then return false, "invalid guest event object" end
      value = {ref = value.ref}
      bytes = bytes + 16
    elseif value == nil or type(value) == "boolean" then bytes = bytes + 1
    elseif type(value) == "number" then
      if value ~= value or math.abs(value) == math.huge then return false, "non-finite event number" end
      bytes = bytes + 8
    else return false, "unsupported event value" end
    if bytes > Limits.event_bytes then return false, "event byte limit exceeded" end
    copy[i] = value
  end
  if #state.queue >= Limits.events or state.bytes + bytes > Limits.event_bytes then
    if not priority then state.dropped = state.dropped + 1; return false, "event queue full" end
    -- Host lifecycle control must stay admissible under guest-controlled pressure.
    while #state.queue > 0 and (#state.queue >= Limits.events or state.bytes + bytes > Limits.event_bytes) do
      local last = table.remove(state.queue)
      state.bytes = state.bytes - last.bytes
      state.dropped = state.dropped + 1
    end
  end
  local record = {tuple = copy, bytes = bytes}
  if priority then table.insert(state.queue, 1, record) else state.queue[#state.queue + 1] = record end
  state.bytes = state.bytes + bytes
  return true
end
function M.poll_work(state, filter)
  local work = 1 + 4 * #state.queue
  if type(filter) == "string" then
    -- Bounded metadata preflight; equal lengths can require a full byte scan.
    for _, record in ipairs(state.queue) do
      local name = record.tuple[1]
      if #name == #filter then work = work + 1 + 2 * #name end
    end
  end
  return work
end
function M.poll(state, filter, raw, timer, spend)
  local count = #state.queue
  if spend then spend(M.poll_work(state, filter)) end
  local consumed, bytes, result, err = 0, 0, nil, nil
  for i = 1, count do
    local record = state.queue[i]
    consumed, bytes = i, bytes + record.bytes
    local event = record.tuple
    if event[1] == "terminate" then
      if raw then result = event else err = "terminated" end
      break
    end
    if (not filter or event[1] == filter) and (not timer or event[2] == timer) then result = event; break end
  end
  -- Remove the consumed prefix in one pass rather than shifting once per event.
  for i = 1, count - consumed do state.queue[i] = state.queue[i + consumed] end
  for i = count - consumed + 1, count do state.queue[i] = nil end
  state.bytes = state.bytes - bytes
  return result, err
end
function M.start_timer(state, seconds, spend)
  assert(type(seconds) == "number" and seconds >= 0 and seconds <= 86400, "invalid timer duration")
  assert(state.timer_count < Limits.timers, "timer quota exceeded")
  if spend then spend(1) end
  local id = state.next_timer
  state.next_timer = id + 1
  -- Zero-duration timers fire at the next synchronized tick, never inline.
  state.timers[id] = state.tick + math.max(1, math.ceil(seconds * 60))
  state.timer_count = state.timer_count + 1
  return id
end
function M.cancel_timer(state, id, spend)
  local count = #state.queue
  if spend then spend(1 + 3 * count) end
  if state.timers[id] then state.timers[id] = nil; state.timer_count = state.timer_count - 1 end
  -- Cancellation also removes any timer tuple not yet delivered.
  local kept = 0
  for i = 1, count do
    local record = state.queue[i]
    if record.tuple[1] == "timer" and record.tuple[2] == id then
      state.bytes = state.bytes - record.bytes
    else
      kept = kept + 1
      state.queue[kept] = record
    end
  end
  for i = kept + 1, count do state.queue[i] = nil end
end
function M.advance(state, tick, spend)
  assert(type(tick) == "number" and tick == math.floor(tick) and tick >= state.tick and tick < 9007199254740992, "invalid simulation tick")
  state.tick = tick
  if spend then spend(1 + 2 * state.timer_count) end
  local due = {}
  for id, deadline in pairs(state.timers) do
    if deadline <= tick then due[#due + 1] = {id = id, deadline = deadline} end
  end
  table.sort(due, function(a, b)
    if spend then spend(1) end
    return a.deadline == b.deadline and a.id < b.id or a.deadline < b.deadline
  end)
  -- Sorting touches only temporary data; reserve every delivery before publishing.
  if spend then spend(12 * #due) end
  for _, timer in ipairs(due) do
    -- Retry at the next dispatch on queue pressure; do not lose a sleep wakeup.
    if not M.admit(state, {n = 2, "timer", timer.id}) then break end
    state.timers[timer.id] = nil
    state.timer_count = state.timer_count - 1
  end
end
return M
