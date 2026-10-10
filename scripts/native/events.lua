-- Native identities over the existing data-only ordered queue/timer machinery.
-- Recrafted owns application filters and timer routing in guest code; only a
-- root coroutine yield is a host wait. Nested yields keep their Lua resumer.
local Core = require('__computer_core_2__.scripts.guest.events')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
function M.install(machine)
  machine.events = machine.events or Core.new()
end
function M.admit(machine, event, priority, spend)
  M.install(machine)
  if type(event) ~= 'table' or getmetatable(event) ~= nil or type(event.n) ~= 'number'
    or event.n < 1 or event.n > Limits.tuple_values or event.n ~= math.floor(event.n)
    or type(event[1]) ~= 'string' then return false, 'invalid native event tuple' end
  if spend then spend(1 + 4 * event.n + (machine.collector and 10 + #machine.events.queue or 0)) end
  local values = {n = event.n}
  for i = 1, event.n do
    local value = event[i]
    local ok = pcall(Execution.validate_value, machine, value)
    if not ok then return false, 'invalid native event value' end
    if machine.collector and type(value) == 'table' then return false, 'native object ingress paused during collection' end
    values[i] = type(value) == 'table' and {ref = value.native_ref} or value
  end
  local state = machine.events
  if machine.collector then
    -- A collector may be traversing the old queue. Scalar host input can use
    -- bounded copy-on-write; existing reference records stay conservatively
    -- rooted in that snapshot, and no new native heap edge is introduced.
    state = {}
    for key, value in pairs(machine.events) do state[key] = value end
    state.queue = {}
    for i, record in ipairs(machine.events.queue) do state.queue[i] = record end
  end
  local ok, err = Core.admit(state, values, machine.heap, priority)
  if not ok then machine.events.dropped = state.dropped; return false, err end
  machine.events = state
  -- Core already reserved/copied a bounded tuple. Convert its private reference
  -- spelling before publication to the native collector or event consumers.
  local record = machine.events.queue[priority and 1 or #machine.events.queue]
  for i = 1, record.tuple.n do
    local value = record.tuple[i]
    if type(value) == 'table' then record.tuple[i] = {native_ref = value.ref} end
  end
  return true
end
function M.start_timer(machine, seconds, spend)
  assert(not machine.collector, 'native timer creation paused during collection')
  M.install(machine)
  assert(machine.events.next_timer < 9007199254740992, 'native timer identity exhausted')
  return Core.start_timer(machine.events, seconds, spend)
end
function M.cancel_timer(machine, id, spend)
  assert(not machine.collector, 'native timer cancellation paused during collection')
  M.install(machine)
  assert(type(id) == 'number' and id >= 1 and id < 9007199254740992 and id == math.floor(id), 'invalid native timer identity')
  Core.cancel_timer(machine.events, id, spend)
end
function M.advance(machine, tick, spend)
  M.install(machine)
  if machine.collector then
    assert(type(tick) == 'number' and tick == math.floor(tick) and tick >= machine.events.tick
      and tick < 9007199254740992, 'invalid simulation tick')
    machine.events.tick = tick
    return false, 'collection'
  end
  Core.advance(machine.events, tick, spend)
  return true
end
function M.deliver(machine, credits, spend, move_spend)
  assert(type(credits) == 'number' and credits >= 0 and credits < math.huge
    and credits == math.floor(credits), 'invalid native event delivery credits')
  if credits == 0 or machine.collector or machine.status ~= 'yield' or machine.active ~= machine.root then return false, 0 end
  M.install(machine)
  local first = machine.events.queue[1]
  if first and move_spend then move_spend(1 + 4 * first.tuple.n) end
  -- The shipped root scheduler yields without a filter. Do not consume a child
  -- yield or pre-filter events: rc.pullEvent{Raw} performs its own filtering and
  -- normal/raw termination policy inside the resumed application coroutine.
  local event = Core.poll(machine.events, nil, true, nil, spend)
  if not event then return false, 0 end
  Execution.resume(machine, event)
  machine.delivered_events = (machine.delivered_events or 0) + 1
  return true, 1
end
function M.services(spend)
  return {
    ['os.queueEvent'] = function(machine, args)
      local ok, err = M.admit(machine, args, false, spend)
      assert(ok, err)
      return 'return', {n = 0}
    end,
    ['os.startTimer'] = function(machine, args)
      return 'return', {n = 1, M.start_timer(machine, args[1], spend)}
    end,
    ['os.cancelTimer'] = function(machine, args)
      M.cancel_timer(machine, args[1], spend)
      return 'return', {n = 0}
    end,
    ['os.clock'] = function(machine)
      spend(1)
      return 'return', {n = 1, machine.events.tick / 60}
    end,
    ['os.getComputerID'] = function(machine)
      spend(1)
      return 'return', {n = 1, machine.computer_id or 0}
    end,
    ['os.shutdown'] = function(machine)
      spend(1)
      machine.host_request = 'shutdown'
      return 'return', {n = 0}
    end,
    ['os.reboot'] = function(machine)
      spend(1)
      machine.host_request = 'reboot'
      return 'return', {n = 0}
    end,
  }
end
function M.install_services(machine)
  M.install(machine)
  local library = Execution.table_value(machine)
  for _, name in ipairs({'queueEvent', 'startTimer', 'cancelTimer', 'clock', 'getComputerID', 'shutdown', 'reboot'}) do
    Execution.set(machine, library, name, Execution.service_value(machine, 'os.' .. name))
  end
  Execution.set(machine, machine.env, 'os', library)
end
return M
