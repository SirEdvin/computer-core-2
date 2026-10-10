-- Durable native-only scheduling. The later backend facade must share these
-- caps with VM scheduling; a second independent live-game allowance is forbidden.
local Dispatch = require('__computer_core_2__.scripts.native.dispatch')
local Events = require('__computer_core_2__.scripts.native.events')
local Helpers = require('__computer_core_2__.scripts.native.helpers')
local Terminal = require('__computer_core_2__.scripts.native.terminal')
local Filesystem = require('__computer_core_2__.scripts.native.filesystem')
local Loader = require('__computer_core_2__.scripts.native.loader')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
local caps = {
  execution = {Limits.instructions_per_computer, Limits.instructions_per_tick},
  collection = {Limits.collection_work_per_computer, Limits.collection_work_per_tick},
  compiler = {Limits.compiler_work_per_computer, Limits.compiler_work_per_tick},
  event = {Limits.event_work_per_computer, Limits.event_work_per_tick},
  advance = {Limits.advance_work_per_computer, Limits.advance_work_per_tick},
  continuation = {Limits.continuation_work_per_computer, Limits.continuation_work_per_tick},
  string = {Limits.string_work_per_computer, Limits.string_work_per_tick},
  table = {Limits.table_work_per_computer, Limits.table_work_per_tick},
  terminal = {Limits.terminal_work_per_computer, Limits.terminal_work_per_tick},
  filesystem = {Limits.filesystem_work_per_computer, Limits.filesystem_work_per_tick},
}
local function integer(value, message)
  assert(type(value) == 'number' and value >= 0 and value < 9007199254740992
    and value == math.floor(value), message)
end
function M.new() return {version = 1, machines = {}, order = {}, cursor = 1} end
function M.add(state, id, machine)
  integer(id, 'invalid native scheduler identity')
  assert(id > 0 and not state.machines[id], 'native scheduler identity unavailable')
  assert(#state.order < Limits.active_computers, 'native scheduler machine quota exceeded')
  Events.install(machine)
  state.machines[id] = machine
  state.order[#state.order + 1] = id
  table.sort(state.order)
end
function M.remove(state, id)
  if not state.machines[id] then return end
  state.machines[id] = nil
  for i, candidate in ipairs(state.order) do
    if candidate == id then
      table.remove(state.order, i)
      if i < state.cursor then state.cursor = state.cursor - 1 end
      break
    end
  end
  if state.cursor > #state.order then state.cursor = 1 end
  -- Retain same-tick identity credits, even if that identity is readmitted.
end
function M.begin_tick(state, tick)
  assert(state.version == 1, 'incompatible native scheduler version')
  integer(tick, 'invalid native scheduler tick')
  assert(not state.budget or tick >= state.budget.tick, 'native scheduler tick cannot move backwards')
  if not state.budget or state.budget.tick ~= tick then
    state.budget = {tick = tick, used = {execution = 0, collection = 0, compiler = 0, event = 0, advance = 0, continuation = 0}, machines = {}}
  end
end
function M.remaining(state, id, domain)
  local limits = assert(caps[domain], 'invalid native budget domain')
  local work = state.budget.machines[id]
  return math.min(limits[1] - (work and work[domain] or 0), limits[2] - (state.budget.used[domain] or 0))
end
function M.consume(state, id, domain, amount)
  integer(amount, 'invalid native work charge')
  assert(state.machines[id], 'native budget identity not registered')
  if amount > M.remaining(state, id, domain) then return false end
  if amount == 0 then return true end
  local budget = state.budget
  budget.machines[id] = budget.machines[id] or {}
  local work = budget.machines[id]
  work[domain] = (work[domain] or 0) + amount
  budget.used[domain] = (budget.used[domain] or 0) + amount
  return true
end
function M.tick(state, tick, extra_services)
  M.begin_tick(state, tick)
  local used, visited, collected = 0, 0, 0
  while visited < #state.order and (state.budget.used.execution or 0) < Limits.instructions_per_tick do
    if state.cursor > #state.order then state.cursor = 1 end
    local id = state.order[state.cursor]
    local machine = state.machines[id]
    local compatible = Dispatch.compatible(machine)
    local collecting = machine.status ~= 'recovery' and compatible and (machine.collector or machine.objects >= machine.collect_at)
    local domain = collecting and 'collection' or 'execution'
    local quantum = M.remaining(state, id, domain)
    -- Aggregate collection deferral preserves the selected cursor. Per-machine
    -- exhaustion still rotates, so an exhausted machine cannot block a neighbor.
    if collecting and quantum == 0 and (state.budget.used.collection or 0) >= Limits.collection_work_per_tick then break end
    state.cursor, visited = state.cursor + 1, visited + 1
    if quantum > 0 and machine.status ~= 'recovery' and not machine.host_request then
      local admit = function(amount) return M.consume(state, id, 'compiler', amount) end
      if not compatible then
        Dispatch.run(machine, 1, admit)
      else
        local refusal = {}
        local ok, err = pcall(Events.advance, machine, tick, function(amount)
          if not M.consume(state, id, 'advance', amount) then error(refusal, 0) end
        end)
        if not ok and err ~= refusal then error(err, 0) end
        local spend = function(amount)
          if not M.consume(state, id, 'event', amount) then error('native event work quota exceeded', 0) end
        end
        if not collecting then
          -- Waiting delivery is host work. Admission refusal retains the queue,
          -- not a guest error or synthetic yield on the saved receiver.
          ok, err = pcall(Events.deliver, machine, quantum, function(amount)
            if not M.consume(state, id, 'event', amount) then error(refusal, 0) end
          end, function(amount)
            if not M.consume(state, id, 'continuation', amount) then error(refusal, 0) end
          end)
          if not ok and err ~= refusal then error(err, 0) end
          if ok then
            -- pcall returns delivery's boolean first; the one paid delivery is
            -- independently counted before executing its retained continuation.
            if err then assert(M.consume(state, id, 'execution', 1)); used = used + 1 end
            quantum = M.remaining(state, id, 'execution')
          end
        end
        local services = Events.services(spend)
        for name, service in pairs(Helpers.services(function(helper_domain, amount)
          return M.consume(state, id, helper_domain, amount)
        end)) do services[name] = service end
        if extra_services then for name, service in pairs(extra_services) do services[name] = service end end
        if machine.terminal_installed then
          for name, service in pairs(Terminal.services(function(amount)
            return M.consume(state, id, 'terminal', amount)
          end)) do services[name] = service end
        end
        if machine.filesystem_installed then
          for name, service in pairs(Filesystem.services(function(amount)
            return M.consume(state, id, 'filesystem', amount)
          end)) do services[name] = service end
        end
        if machine.loader_installed then
          for name, service in pairs(Loader.services(function(loader_domain, amount)
            return M.consume(state, id, loader_domain, amount)
          end)) do services[name] = service end
        end
        local _, count = Dispatch.run(machine, quantum, admit, services)
        assert(M.consume(state, id, domain, count), 'native dispatcher exceeded admitted quantum')
        if collecting then collected = collected + count else used = used + count end
      end
    end
  end
  return used, visited, collected
end
return M
