-- Durable guest scheduler shared by live computers and isolated tests.
local VM = require("__computer_core_2__.scripts.guest.vm")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local Collector = require("__computer_core_2__.scripts.guest.collector")
local M = {}

function M.new()
  return {version = 1, machines = {}, order = {}, cursor = 1}
end

function M.add(state, id, vm, backend)
  assert(backend==nil or backend=='vm' or backend=='event-shell','unsupported scheduled backend')
  assert(type(id) == "number" and id > 0 and id == math.floor(id), "invalid machine id")
  assert(not state.machines[id], "machine already admitted")
  assert(#state.order < Limits.active_computers, "active computer limit exceeded")
  state.machines[id] = vm
  if backend=='event-shell' then
    state.backends=state.backends or {}
    state.backends[id]=backend
  elseif state.backends then state.backends[id]=nil end
  state.order[#state.order + 1] = id
  table.sort(state.order)
end

function M.remove(state, id)
  if not state.machines[id] then return end
  state.machines[id] = nil
  if state.backends then state.backends[id]=nil end
  for i, candidate in ipairs(state.order) do
    if candidate == id then
      table.remove(state.order, i)
      if i < state.cursor then state.cursor = state.cursor - 1 end
      break
    end
  end
  if state.cursor > #state.order then state.cursor = 1 end
end

function M.tick(state, tick, shell_step)
  assert(state.version == 1, "incompatible scheduler state")
  if tick ~= nil then assert(type(tick) == "number" and tick >= 0 and tick < 9007199254740992 and tick == math.floor(tick), "invalid scheduler tick") end
  if tick ~= nil and state.compile_budget and state.compile_budget.tick ~= nil then
    assert(tick >= state.compile_budget.tick, "scheduler tick cannot move backwards")
  end
  -- Explicit simulation ticks retain credits across repeated dispatch/reload.
  -- Untimed standalone harness calls each define a fresh dispatch budget.
  if not state.execution_budget or tick == nil or state.execution_budget.tick ~= tick then
    state.execution_budget = {tick = tick, instructions = 0, collection = 0, machines = {}}
  end
  local execution = state.execution_budget
  if not state.compile_budget or tick == nil or state.compile_budget.tick ~= tick then
    state.compile_budget = {tick = tick, used = 0, limit = Limits.compiler_work_per_tick, machines = {}}
  end
  if not state.string_budget or tick == nil or state.string_budget.tick ~= tick then
    state.string_budget = {tick = tick, used = 0, limit = Limits.string_work_per_tick, machines = {}}
  end
  local aggregate = state.compile_budget
  if not state.terminal_budget or tick == nil or state.terminal_budget.tick ~= tick then
    state.terminal_budget = {tick = tick, used = 0, limit = Limits.terminal_work_per_tick, machines = {}}
  end
  local terminals = state.terminal_budget
  if not state.filesystem_budget or tick == nil or state.filesystem_budget.tick ~= tick then
    state.filesystem_budget = {tick = tick, used = 0, limit = Limits.filesystem_work_per_tick, machines = {}}
  end
  local filesystems = state.filesystem_budget
  if not state.event_budget or tick == nil or state.event_budget.tick ~= tick then
    state.event_budget = {tick = tick, used = 0, limit = Limits.event_work_per_tick, machines = {}}
  end
  local events = state.event_budget
  if not state.advance_budget or tick == nil or state.advance_budget.tick ~= tick then
    state.advance_budget = {tick = tick, used = 0, limit = Limits.advance_work_per_tick, machines = {},
      deferred_per_computer = 0, deferred_aggregate = 0}
  end
  local advances = state.advance_budget
  if not state.table_budget or tick == nil or state.table_budget.tick ~= tick then
    state.table_budget = {tick = tick, used = 0, limit = Limits.table_work_per_tick, machines = {}}
  end
  local tables = state.table_budget
  if not state.continuation_budget or tick == nil or state.continuation_budget.tick ~= tick then
    state.continuation_budget = {tick = tick, used = 0, limit = Limits.continuation_work_per_tick, machines = {}}
  end
  local continuations = state.continuation_budget
  local continuations_before = continuations.used
  local tables_before = tables.used
  local advances_before = advances.used
  local events_before = events.used
  local filesystems_before = filesystems.used
  local terminals_before = terminals.used
  local strings = state.string_budget
  local before = aggregate.used
  local strings_before = strings.used
  local used, visited, collection_work = 0, 0, 0
  while visited < #state.order and execution.instructions < Limits.instructions_per_tick do
    if state.cursor > #state.order then state.cursor = 1 end
    local id = state.order[state.cursor]
    local vm = state.machines[id]
    local backend=state.backends and state.backends[id]
    if (backend==nil or backend=='vm') and vm.collection and execution.collection >= Limits.collection_work_per_tick then break end
    state.cursor = state.cursor + 1
    visited = visited + 1
    local work = execution.machines[id]
    if not work then
      work = {instructions = 0, collection = 0}
      execution.machines[id] = work
    end
    if backend=='event-shell' then
      -- The sole alternative is a trusted host-only stepper, never a saved
      -- callback or executable identity from the machine's files/session.
      assert(type(shell_step)=='function','event-shell stepper unavailable')
      local previous=execution.instructions
      shell_step(vm,state,id,tick)
      used=used+execution.instructions-previous
    else
    assert(backend==nil or backend=='vm','unsupported scheduled backend')
    VM.reconcile_configured(vm)
    local aggregate_deferred = false
    if tick then
      local computer = advances.machines[id]
      if not computer then
        computer = {used = 0, limit = Limits.advance_work_per_computer}
        advances.machines[id] = computer
      end
      -- Refusal identity is ephemeral; never catch unrelated host failures here.
      local refusal = {}
      local ok, err = pcall(VM.advance, vm, tick, function(amount)
        assert(type(amount) == "number" and amount >= 0 and amount < math.huge and amount == math.floor(amount), "invalid timer advancement charge")
        if amount > computer.limit - computer.used then
          refusal.scope = "computer"
          error(refusal, 0)
        end
        if amount > advances.limit - advances.used then
          refusal.scope = "aggregate"
          error(refusal, 0)
        end
        computer.used = computer.used + amount
        advances.used = advances.used + amount
      end)
      if not ok then
        if err ~= refusal then error(err, 0) end
        aggregate_deferred = refusal.scope == "aggregate"
        if aggregate_deferred then advances.deferred_aggregate = (advances.deferred_aggregate or 0) + 1
        else advances.deferred_per_computer = (advances.deferred_per_computer or 0) + 1 end
      end
    end
    if not vm.collection and vm.allocations_since_collection >= Limits.collection_interval then Collector.start(vm) end
    if vm.collection then
      local quantum = math.min(Limits.collection_work_per_computer - work.collection, Limits.collection_work_per_tick - execution.collection)
      local _, count = Collector.step(vm, quantum)
      collection_work = collection_work + count
      work.collection = work.collection + count
      execution.collection = execution.collection + count
    else
      local quantum = math.min(Limits.instructions_per_computer - work.instructions, Limits.instructions_per_tick - execution.instructions)
      local computer = aggregate.machines[id]
      if not computer then
        computer = {used = 0, limit = Limits.compiler_work_per_computer}
        aggregate.machines[id] = computer
      end
      local string_computer = strings.machines[id]
      if not string_computer then
        string_computer = {used = 0, limit = Limits.string_work_per_computer}
        strings.machines[id] = string_computer
      end
      local terminal_computer = terminals.machines[id]
      if not terminal_computer then
        terminal_computer = {used = 0, limit = Limits.terminal_work_per_computer}
        terminals.machines[id] = terminal_computer
      end
      local filesystem_computer = filesystems.machines[id]
      if not filesystem_computer then
        filesystem_computer = {used = 0, limit = Limits.filesystem_work_per_computer}
        filesystems.machines[id] = filesystem_computer
      end
      local event_computer = events.machines[id]
      if not event_computer then
        event_computer = {used = 0, limit = Limits.event_work_per_computer}
        events.machines[id] = event_computer
      end
      local table_computer = tables.machines[id]
      if not table_computer then
        table_computer = {used = 0, limit = Limits.table_work_per_computer}
        tables.machines[id] = table_computer
      end
      local continuation_computer = continuations.machines[id]
      if not continuation_computer then
        continuation_computer = {used = 0, limit = Limits.continuation_work_per_computer}
        continuations.machines[id] = continuation_computer
      end
      local _, _, count = VM.run(vm, quantum, {computer = computer, aggregate = aggregate,
        continuation_computer = continuation_computer, continuation_aggregate = continuations,
        string_computer = string_computer, string_aggregate = strings,
        terminal_computer = terminal_computer, terminal_aggregate = terminals,
        filesystem_computer = filesystem_computer, filesystem_aggregate = filesystems,
        event_computer = event_computer, event_aggregate = events,
        table_computer = table_computer, table_aggregate = tables})
      used = used + count
      work.instructions = work.instructions + count
      execution.instructions = execution.instructions + count
    end
    -- Keep the cursor after this machine rather than revisiting the same prefix.
    -- The selected guest still receives service when timer maintenance defers.
    if aggregate_deferred or execution.collection >= Limits.collection_work_per_tick then break end
    end
  end
  return used, visited, collection_work, aggregate.used - before, strings.used - strings_before, terminals.used - terminals_before, filesystems.used - filesystems_before, events.used - events_before, advances.used - advances_before, tables.used - tables_before, continuations.used - continuations_before
end

return M
