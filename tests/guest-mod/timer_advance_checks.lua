local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Events = require("__computer_core_2__.scripts.guest.events")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local function full(prototype)
  local vm = VM.new(prototype)
  for i = 1, Limits.events do assert(VM.queue(vm, table.pack('saved', i))) end
  for i = 1, Limits.timers do Events.start_timer(vm.events, 0) end
  return vm
end
function M.initial(check)
  for _, allowance in ipairs({0, 1 + 2 * Limits.timers, 1 + 2 * Limits.timers + 1}) do
    local state, admitted = Events.new(), 0
    for i = 1, Limits.timers do Events.start_timer(state, 0) end
    local ok, err = pcall(Events.advance, state, 70, function(amount)
      if amount > allowance - admitted then error('test timer advance refused', 0) end
      admitted = admitted + amount
    end)
    check('timer advancement refuses before publishing due tuples: '..allowance,
      not ok and err == 'test timer advance refused' and state.tick == 70
      and state.timer_count == Limits.timers and #state.queue == 0 and state.bytes == 0
      and state.next_timer == Limits.timers + 1 and state.dropped == 0 and admitted <= allowance)
  end
  local state, comparisons = Events.new(), 0
  for i = 1, Limits.timers do Events.start_timer(state, 0) end
  local ok, err = pcall(Events.advance, state, 70, function(amount)
    if amount == 12 * Limits.timers then error('test timer delivery refused', 0) end
    if amount == 1 then comparisons = comparisons + 1 end
  end)
  check('post-sort refusal leaves every timer pending', not ok and err == 'test timer delivery refused'
    and comparisons > 0 and state.timer_count == Limits.timers and #state.queue == 0 and state.bytes == 0 and state.dropped == 0)
  local prototype = assert(Compiler.compile('return os.clock()', '=timer-advance-work'))
  local scheduler, vm = Scheduler.new(), full(prototype)
  Scheduler.add(scheduler, 1, vm)
  for _ = 1, 80 do Scheduler.tick(scheduler, 70) end
  local budget = scheduler.advance_budget
  check('repeated advancement shares per-computer timer credits', budget and budget.deferred_per_computer > 0
    and budget.machines[1].used > 0 and budget.machines[1].used <= Limits.advance_work_per_computer
    and vm.events.timer_count == Limits.timers and #vm.events.queue == Limits.events)
  Scheduler.add(scheduler, 2, full(prototype))
  Scheduler.add(scheduler, 3, full(prototype))
  for _ = 1, 80 do Scheduler.tick(scheduler, 70) end
  check('many timers share aggregate advancement credits', budget.deferred_aggregate > 0
    and budget.used > 0 and budget.used <= Limits.advance_work_per_tick)
  local used = budget.used
  Scheduler.tick(scheduler, 70)
  check('same-tick timer advancement does not replenish credits', scheduler.advance_budget == budget and budget.used == used)
  for _, machine in pairs(scheduler.machines) do
    assert(machine.events.tick == 70 and machine.events.timer_count == Limits.timers and #machine.events.queue == Limits.events)
    assert(not machine.objects[machine.main.ref].failed)
  end
  check('timer deferral preserves wakeups and allows guest execution', vm.objects[vm.main.ref].status == 'dead'
    and vm.objects[vm.main.ref].result[1] == 70 / 60)
  local cursor = scheduler.cursor
  Scheduler.tick(scheduler, 70)
  check('aggregate deferral rotates the next dispatch', scheduler.cursor ~= cursor)
  local healthy = VM.new(assert(Compiler.compile([[local event, value = os.pullEventRaw('ready')
    return event, value, os.clock()]])))
  VM.run(healthy, 256)
  assert(healthy.wait and VM.queue(healthy, table.pack('ready', 7)))
  Scheduler.add(scheduler, 4, healthy)
  for _ = 1, 8 do Scheduler.tick(scheduler, 70) end
  local result = healthy.objects[healthy.main.ref].result
  check('input is serviced despite aggregate timer deferral', healthy.objects[healthy.main.ref].status == 'dead'
    and not healthy.objects[healthy.main.ref].failed and result[1] == 'ready' and result[2] == 7 and result[3] == 70 / 60)
  log('CC2 GUEST TIMER ADVANCE METRICS used='..budget.used..' computer='..budget.machines[1].used
    ..' per_computer_deferrals='..budget.deferred_per_computer..' aggregate_deferrals='..budget.deferred_aggregate)
  storage.timer_advance_scheduler, storage.timer_advance_used = scheduler, budget.used
end
function M.resume(check)
  local scheduler, used = storage.timer_advance_scheduler, storage.timer_advance_used
  local budget = scheduler.advance_budget
  check('timer advancement credits survive separate-process reload', budget.tick == 70 and budget.used == used)
  Scheduler.tick(scheduler, 70)
  check('reloaded timer credits retain same-tick identity', scheduler.advance_budget == budget and budget.used == used)
  local vm = scheduler.machines[1]
  -- Reconcile first: a later resize must not consume a slot we just freed for timers.
  VM.reconcile_configured(vm)
  Events.poll(vm.events, 'never', true)
  local _, _, _, _, _, _, _, _, work = Scheduler.tick(scheduler, 71)
  check('later tick retries pending timers with renewed bounded work', work > 0 and work <= Limits.advance_work_per_tick
    and scheduler.advance_budget.tick == 71 and vm.events.tick == 71 and vm.events.timer_count == 0 and #vm.events.queue == Limits.timers)
  local ordered = true
  for id, record in ipairs(vm.events.queue) do ordered = ordered and record.tuple[1] == 'timer' and record.tuple[2] == id end
  check('deferred timers retain original IDs and deadline ordering', ordered and vm.events.next_timer == Limits.timers + 1)
end
return M
