local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Events = require("__computer_core_2__.scripts.guest.events")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local function context(limit)
  return {computer = {used = 0, limit = Limits.compiler_work_per_computer}, event_computer = {used = 0, limit = limit}}
end
local function finish(vm, credits)
  for _ = 1, 30 do
    local status, result = VM.run(vm, 256, credits)
    if status == 'dead' then return result end
  end
  error('event-budget fixture did not complete')
end
function M.initial(check)
  for _, code in ipairs({"os.queueEvent('new')", "os.startTimer(1)", "os.cancelTimer(1)", "os.pullEventRaw()", "os.sleep(1)", "os.clock()"}) do
    local vm = VM.new(assert(Compiler.compile('return pcall(function() '..code..' end)')))
    assert(VM.queue(vm, table.pack('saved', nil, 7)))
    Events.start_timer(vm.events, 2)
    local queued, bytes, next_timer = vm.events.queue[1], vm.events.bytes, vm.events.next_timer
    local credits = context(0)
    local result = finish(vm, credits)
    check('zero-credit event service is atomic: '..code, result[1] == false and result[2] == 'per-computer event work limit exceeded'
      and #vm.events.queue == 1 and vm.events.queue[1] == queued and vm.events.bytes == bytes
      and vm.events.timer_count == 1 and vm.events.next_timer == next_timer and vm.events.dropped == 0
      and credits.event_computer.used == 0)
  end
  local aggregate_vm = VM.new(assert(Compiler.compile('return pcall(os.clock)')))
  local aggregate_credits = context(Limits.event_work_per_computer)
  aggregate_credits.event_aggregate = {used = 0, limit = 0}
  local aggregate_result = finish(aggregate_vm, aggregate_credits)
  check('aggregate event refusal preserves both counters', aggregate_result[1] == false
    and aggregate_result[2] == 'aggregate event work limit exceeded' and aggregate_credits.event_computer.used == 0
    and aggregate_credits.event_aggregate.used == 0)
  local sleeping = VM.new(assert(Compiler.compile('return pcall(os.sleep, 1)')))
  assert(VM.queue(sleeping, table.pack('saved')))
  local partial = context(1)
  local refused = finish(sleeping, partial)
  check('sleep reserves creation and polling atomically', refused[1] == false and sleeping.events.timer_count == 0
    and sleeping.events.next_timer == 1 and #sleeping.events.queue == 1 and partial.event_computer.used == 0)
  sleeping = VM.new(assert(Compiler.compile('return pcall(os.sleep, 1)')))
  assert(VM.queue(sleeping, table.pack('timer', 2)))
  partial = context(6)
  refused = finish(sleeping, partial)
  check('sleep reserves filter byte work before retaining its timer', refused[1] == false
    and sleeping.events.timer_count == 0 and sleeping.events.next_timer == 1 and #sleeping.events.queue == 1
    and partial.event_computer.used == 0)
  local name = string.rep('n', 1024)
  local function filtered(credits)
    local vm = VM.new(assert(Compiler.compile('local name=...; return pcall(os.pullEventRaw,name)')), table.pack(name))
    assert(VM.queue(vm, table.pack(name)))
    local result = finish(vm, credits)
    return vm, result
  end
  local byte_credits = context(2053)
  local filtered_vm, filtered_result = filtered(byte_credits)
  check('filter byte refusal preserves queue and credits', filtered_result[1] == false
    and filtered_result[2] == 'per-computer event work limit exceeded' and #filtered_vm.events.queue == 1
    and filtered_vm.events.bytes == #name and byte_credits.event_computer.used == 0)
  byte_credits = context(2054)
  byte_credits.event_aggregate = {used = 0, limit = 2053}
  filtered_vm, filtered_result = filtered(byte_credits)
  check('aggregate filter byte refusal is atomic', filtered_result[1] == false
    and filtered_result[2] == 'aggregate event work limit exceeded' and #filtered_vm.events.queue == 1
    and byte_credits.event_computer.used == 0 and byte_credits.event_aggregate.used == 0)
  byte_credits = context(2054)
  filtered_vm, filtered_result = filtered(byte_credits)
  check('matching filter precharges pairwise name bytes', filtered_result[1] == true and filtered_result[2] == name
    and #filtered_vm.events.queue == 0 and filtered_vm.events.bytes == 0 and byte_credits.event_computer.used == 2054)
  for _, names in ipairs({{'other','match'}, {'match','other'}}) do
    local state = Events.new()
    for _, event_name in ipairs(names) do assert(Events.admit(state, table.pack(event_name))) end
    local quote = 1 + 4 * #names + #names * (1 + 2 * #'match')
    local queue, bytes, charged = state.queue, state.bytes, 0
    local ok = pcall(Events.poll, state, 'match', true, nil, function(amount)
      assert(amount == quote)
      error('test comparison refusal', 0)
    end)
    check('filter reservation covers nonmatch and later records: '..names[1], not ok and state.queue == queue and #queue == #names and state.bytes == bytes)
    local event = Events.poll(state, 'match', true, nil, function(amount) charged = charged + amount end)
    check('filter preserves survivor order after byte admission: '..names[1], event[1] == 'match' and charged == quote
      and #queue == (names[1] == 'match' and 1 or 0) and (#queue == 0 or queue[1].tuple[1] == 'other'))
  end
  for _, raw in ipairs({false,true}) do
    local state = Events.new()
    assert(Events.admit(state, table.pack('terminate')))
    local quote = 1 + 4 + 1 + 2 * #'terminate'
    local ok = pcall(Events.poll, state, 'terminate', raw, nil, function(amount) assert(amount == quote); error('test termination refusal', 0) end)
    check('termination byte refusal preserves queue raw='..tostring(raw), not ok and #state.queue == 1 and state.bytes == #'terminate')
    local charged = 0
    local event, err = Events.poll(state, 'terminate', raw, nil, function(amount) charged = amount end)
    check('termination semantics survive exact byte admission raw='..tostring(raw), charged == quote and #state.queue == 0 and state.bytes == 0
      and ((raw and event and event[1] == 'terminate' and err == nil) or (not raw and event == nil and err == 'terminated')))
  end
  local waiting = VM.new(assert(Compiler.compile('return pcall(os.pullEventRaw)')))
  VM.run(waiting, 256)
  assert(waiting.wait and VM.queue(waiting, table.pack('saved')))
  refused = finish(waiting, context(0))
  check('resumed wait reports budget refusal through guest pcall', refused[1] == false
    and refused[2] == 'per-computer event work limit exceeded' and #waiting.events.queue == 1
    and waiting.wait == nil and not waiting.objects[waiting.main.ref].failed)
  local state = Events.new()
  for i = 1, Limits.events do assert(Events.admit(state, table.pack('skip', i))) end
  local queue, bytes = state.queue, state.bytes
  local ok, err = pcall(Events.poll, state, 'never', false, nil, function() error('test event work refused', 0) end)
  check('filtered polling refuses before discarding queue', not ok and err == 'test event work refused'
    and state.queue == queue and #queue == Limits.events and state.bytes == bytes)
  local work = 0
  check('full filtered discard uses one linear-work reservation', Events.poll(state, 'never', false, nil,
    function(amount) work = work + amount end) == nil and #queue == 0 and state.bytes == 0 and work == 1 + 4 * Limits.events)
  for i = 1, 8 do assert(Events.admit(state, table.pack(i % 2 == 0 and 'timer' or 'keep', i % 2 == 0 and 1 or i))) end
  local timer = Events.start_timer(state, 2)
  local before = state.bytes
  ok, err = pcall(Events.cancel_timer, state, timer, function() error('test event work refused', 0) end)
  check('timer cancellation refuses before removing active or queued timers', not ok and err == 'test event work refused'
    and state.timer_count == 1 and #state.queue == 8 and state.bytes == before)
  work = 0
  Events.cancel_timer(state, timer, function(amount) work = work + amount end)
  local ordered = state.timer_count == 0 and #state.queue == 4 and work == 25
  for i, record in ipairs(state.queue) do ordered = ordered and record.tuple[1] == 'keep' and record.tuple[2] == 2 * i - 1 end
  check('linear cancellation preserves survivor order and byte accounting', ordered and state.bytes == 48)

  local prototype = assert(Compiler.compile([[while true do
    local ok, err = pcall(os.cancelTimer, -1)
    if not ok then last_event_error = err; return end
  end]], '=event-work-loop'))
  local single = VM.new(prototype)
  for i = 1, Limits.events do assert(VM.queue(single, table.pack('saved', i))) end
  local credits = context(Limits.event_work_per_computer)
  finish(single, credits)
  check('per-computer event credits persist across run quanta', single.objects[single.env.ref].entries['s:last_event_error'].value
    == 'per-computer event work limit exceeded' and credits.event_computer.used > 0
    and credits.event_computer.used <= Limits.event_work_per_computer and #single.events.queue == Limits.events)
  local scheduler = Scheduler.new()
  for id = 1, 4 do
    local vm = VM.new(prototype)
    for i = 1, Limits.events do assert(VM.queue(vm, table.pack('saved', i))) end
    Scheduler.add(scheduler, id, vm)
  end
  for _ = 1, 60 do Scheduler.tick(scheduler, 70) end
  local aggregate, preempted = false, true
  for id, vm in pairs(scheduler.machines) do
    assert(not vm.objects[vm.main.ref].failed and #vm.events.queue == Limits.events)
    local record = vm.objects[vm.env.ref].entries['s:last_event_error']
    local err = record and record.value
    if record then preempted = false end
    if not record then assert(scheduler.execution_budget.machines[id].instructions == Limits.instructions_per_computer) end

    aggregate = aggregate or err == 'aggregate event work limit exceeded'
    assert(scheduler.event_budget.machines[id].used <= Limits.event_work_per_computer)
  end
  check('repeated cancellation shares scheduler event credits or preempts first', (aggregate or preempted) and scheduler.event_budget.used > 0
    and scheduler.event_budget.used <= Limits.event_work_per_tick)
  local saved = scheduler.event_budget.used
  Scheduler.tick(scheduler, 70)
  check('same-tick event credits do not refresh', scheduler.event_budget.used == saved)
  storage.event_budget_scheduler, storage.event_budget_used = scheduler, saved
  local vm = scheduler.machines[1]
  check('host priority ingress remains admissible despite guest exhaustion', VM.queue(vm, table.pack('term_resize'), true)
    and vm.events.queue[1].tuple[1] == 'term_resize' and #vm.events.queue == Limits.events)
end
function M.resume(check)
  local state, saved = storage.event_budget_scheduler, storage.event_budget_used
  check('event credits survive separate-process reload', state.event_budget.tick == 70 and state.event_budget.used == saved)
  local counters = state.event_budget
  Scheduler.tick(state, 70)
  check('reload retains same-tick event counters', state.event_budget == counters and counters.used == saved)
  local vm = VM.new(assert(Compiler.compile("return os.startTimer(1)")))
  Scheduler.add(state, 5, vm)
  local _, _, _, _, _, _, _, work = Scheduler.tick(state, 71)
  check('later tick restores bounded event service', state.event_budget.tick == 71 and work > 0
    and work <= Limits.event_work_per_tick and vm.events.timer_count == 1 and not vm.objects[vm.main.ref].failed)
end
return M
