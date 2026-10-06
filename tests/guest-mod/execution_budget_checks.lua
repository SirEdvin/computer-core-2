local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Collector = require("__computer_core_2__.scripts.guest.collector")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
function M.initial(check)
  local prototype = assert(Compiler.compile('local n=0; while true do n=n+1 end', '=execution-credit-loop'))
  local state = Scheduler.new()
  for id = 1, 20 do
    local vm = VM.new(prototype)
    VM.run(vm, 1000)
    Scheduler.add(state, id, vm)
  end
  local work = Scheduler.tick(state, 200)
  check('explicit tick enforces aggregate execution credits', work == Limits.instructions_per_tick
    and state.execution_budget.instructions == work and state.cursor == 17)
  local saved = state.execution_budget
  for _ = 1, 20 do assert(Scheduler.tick(state, 200) == 0) end
  check('same-tick dispatch cannot renew instruction credits', state.execution_budget == saved
    and saved.instructions == Limits.instructions_per_tick and state.cursor == 17)
  for _, credits in pairs(saved.machines) do assert(credits.instructions <= Limits.instructions_per_computer) end
  check('looping computers share per-machine instruction ceilings', saved.machines[1].instructions == Limits.instructions_per_computer
    and saved.machines[16].instructions == Limits.instructions_per_computer and saved.machines[17] == nil)
  storage.execution_credit_scheduler = state

  local collecting = Scheduler.new()
  prototype = assert(Compiler.compile("os.pullEvent('stay')", '=collection-credit-wait'))
  for id = 1, 18 do
    local vm = VM.new(prototype)
    VM.run(vm, 1000)
    assert(vm.wait)
    Collector.start(vm)
    Scheduler.add(collecting, id, vm)
  end
  local _, _, collection_work = Scheduler.tick(collecting, 300)
  check('explicit tick enforces aggregate collection credits', collection_work == Limits.collection_work_per_tick
    and collecting.execution_budget.collection == collection_work and collecting.cursor == 17)
  local counter = collecting.execution_budget
  for _ = 1, 20 do
    local _, _, repeated = Scheduler.tick(collecting, 300)
    assert(repeated == 0)
  end
  check('same-tick collection credits cannot refresh', collecting.execution_budget == counter and counter.collection == collection_work)
  for _, credits in pairs(counter.machines) do assert(credits.collection <= Limits.collection_work_per_computer) end
  storage.collection_credit_scheduler = collecting
  local single = Scheduler.new()
  local vm = VM.new(prototype)
  VM.run(vm, 1000)
  Collector.start(vm)
  Scheduler.add(single, 1, vm)
  local _, _, first = Scheduler.tick(single, 310)
  for _ = 1, 20 do local _, _, extra = Scheduler.tick(single, 310); assert(extra == 0) end
  check('per-machine collection ceiling holds with aggregate capacity available', first == Limits.collection_work_per_computer
    and single.execution_budget.collection == first and first < Limits.collection_work_per_tick and vm.collection ~= nil)
  storage.single_collection_credit_scheduler = single
end
function M.resume(check)
  local state = storage.execution_credit_scheduler
  local saved = state.execution_budget
  check('instruction ceilings survive separate-process reload', saved.tick == 200 and saved.instructions == Limits.instructions_per_tick)
  check('same-tick reload cannot resume exhausted execution', Scheduler.tick(state, 200) == 0 and state.execution_budget == saved)
  local work = Scheduler.tick(state, 201)
  check('later tick resumes unserved machines fairly', work == Limits.instructions_per_tick
    and state.execution_budget.tick == 201 and state.execution_budget.machines[17].instructions == Limits.instructions_per_computer)
  local collecting = storage.collection_credit_scheduler
  saved = collecting.execution_budget
  check('collection ceilings survive separate-process reload', saved.tick == 300 and saved.collection == Limits.collection_work_per_tick)
  local _, _, repeated = Scheduler.tick(collecting, 300)
  check('same-tick reload cannot renew collection work', repeated == 0 and collecting.execution_budget == saved)
  local _, _, renewed = Scheduler.tick(collecting, 301)
  check('later tick resumes deferred collection fairly', renewed > 0 and renewed <= Limits.collection_work_per_tick
    and collecting.execution_budget.tick == 301 and collecting.execution_budget.machines[17].collection > 0)
  local single = storage.single_collection_credit_scheduler
  local _, _, extra = Scheduler.tick(single, 310)
  check('per-machine collection exhaustion survives reload without aggregate exhaustion', extra == 0
    and single.execution_budget.collection == Limits.collection_work_per_computer and single.machines[1].collection ~= nil)
  local _, _, next_work = Scheduler.tick(single, 311)
  check('later tick restores independent per-machine collection', next_work > 0 and next_work <= Limits.collection_work_per_computer)
end
return M
