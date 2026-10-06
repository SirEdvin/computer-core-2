-- Required during parsing, never during an event or on_load.
local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Collector = require("__computer_core_2__.scripts.guest.collector")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local Events = require("__computer_core_2__.scripts.guest.events")
local terminal_checks = require("terminal_checks")
local Filesystem = require("__computer_core_2__.scripts.filesystem")
local fixtures = require("guest_fixtures")
local dimensions = require("guest_settings")
local Boot = require("__computer_core_2__.scripts.guest.boot")
local shell_probe = require("shell_probe")
local editor_checks = require("editor_checks")
local resize_checks = require("resize_checks")
local compiler_checks = require("compiler_checks")
local compile_budget_checks = require("compile_budget_checks")
local string_budget_checks = require("string_budget_checks")
local terminal_budget_checks = require("terminal_budget_checks")
local filesystem_budget_checks = require("filesystem_budget_checks")
local file_read_budget_checks = require("file_read_budget_checks")
local file_write_budget_checks = require("file_write_budget_checks")
local event_budget_checks = require("event_budget_checks")
local timer_advance_checks = require("timer_advance_checks")
local table_iteration_checks = require("table_iteration_checks")
local table_budget_checks = require("table_budget_checks")
local execution_budget_checks = require("execution_budget_checks")
local coroutine_error_checks = require("coroutine_error_checks")
local scalar_budget_checks = require("scalar_budget_checks")
local tuple_budget_checks = require("tuple_budget_checks")
local continuation_checks = require("continuation_checks")
local full_heap_checks = require("full_heap_checks")
local continuation_budget_checks = require("continuation_budget_checks")
local unwind_checks = require("unwind_checks")
local frame_cleanup_checks = require("frame_cleanup_checks")
local live_disk_checks = require("live_disk_checks")
local loaded = false
local load_checked = false
local function check(name, condition)
  assert(condition, "FAIL: " .. name)
  storage.checks = storage.checks + 1
  log("CC2 GUEST PASS " .. name)
end
local function plain(value, seen)
  local kind = type(value)
  assert(kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" or kind == "table", "non-data value: " .. kind)
  if kind ~= "table" then return end
  assert(getmetatable(value) == nil, "host metatable in guest state")
  if seen[value] then return end
  seen[value] = true
  for key, child in pairs(value) do plain(key, seen); plain(child, seen) end
end

script.on_init(function()
  storage.checks = 0
  storage.prototypes = {}
  compiler_checks(check)
  compile_budget_checks.initial(check)
  string_budget_checks.initial(check)
  terminal_budget_checks.initial(check)
  filesystem_budget_checks.initial(check)
  file_read_budget_checks.initial(check)
  file_write_budget_checks.initial(check)
  event_budget_checks.initial(check)
  timer_advance_checks.initial(check)
  table_iteration_checks.initial(check)
  table_budget_checks.initial(check)
  execution_budget_checks.initial(check)
  coroutine_error_checks.initial(check)
  scalar_budget_checks.initial(check)
  tuple_budget_checks.initial(check)
  continuation_checks.initial(check)
  full_heap_checks.initial(check)
  continuation_budget_checks.initial(check)
  unwind_checks.initial(check)
  frame_cleanup_checks.initial(check)
  live_disk_checks.initial(check)
  terminal_checks(check)
  storage.resize_execution = resize_checks.initial(check)
  for _, fixture in ipairs(fixtures) do
    local proto, err = Compiler.compile(fixture.source, fixture.path)
    assert(proto, err)
    plain(proto, {})
    storage.prototypes[fixture.path] = proto
    check("compiled plain prototype " .. fixture.path, proto.version == Compiler.VERSION and #proto.instructions > 0)
    local disk = {fs = {['/local.lua'] = {type = "file", text = "return 'local-pass', nil, 7"}}}
    if fixture.path == "filesystem_quota.lua" then
      disk.fs = {['/old.txt'] = {type = "file", text = "old"}, ['/filler'] = {type = "file", text = string.rep("x", Filesystem.max_bytes - 3)}}
    end
    local vm = VM.new(proto, table.pack(dimensions.columns, dimensions.rows), disk)
    if disk.fs['/local.lua'] then disk.fs['/local.lua'].text = "error('host alias leaked')" end
    local fixture_scheduler = Scheduler.new()
    Scheduler.add(fixture_scheduler, 1, vm)
    local turns = 0
    repeat
      Scheduler.tick(fixture_scheduler)
      turns = turns + 1
    until vm.objects[vm.main.ref].status == "dead" or turns >= 2000
    local main = vm.objects[vm.main.ref]
    local status, result, failure = main.status, main.result, main.error
    if turns >= 2000 then
      log("CC2 GUEST TIMEOUT " .. fixture.path .. " instructions=" .. vm.instructions .. " objects=" .. vm.object_count .. " collection=" .. (vm.collection and vm.collection.phase or "none"))
    end
    assert(not vm.objects[vm.main.ref].failed, fixture.path .. ": " .. tostring(failure))
    check("executed guest fixture " .. fixture.path, status == "dead" and result and type(result[1]) == "string" and result[1]:find("pass", 1, true) ~= nil)
    plain(vm, {})
    if fixture.path == "register_pool.lua" then
      check("uncaptured register reuse avoids per-call heap churn", vm.next_id < 6000 and vm.free_cells and #vm.free_cells > 0 and #vm.free_cells <= Limits.register_pool)
      Collector.start(vm)
      while vm.collection do
        local _, work = Collector.step(vm, 256)
        assert(work <= 256)
      end
      local seen, count = {}, 0
      for id in pairs(vm.objects) do count = count + 1 end
      for _, id in ipairs(vm.free_cells) do
        local data = vm.objects[id]
        assert(data and data.kind == "cell" and data.captured == false and data.value == nil and not seen[id])
        seen[id] = true
      end
      check("pooled cells survive collection within the unchanged heap quota", count == vm.object_count and count <= Limits.heap_objects)
    end
    if fixture.path == "upstream_terminal.lua" then
      local row = vm.display.lines[2]
      check("real upstream nested window redraw reaches native display", row.text:sub(2, 9) == "xyzDEFGH" and row.foreground:sub(2, 9) == "23434567" and row.background:sub(2, 9) == "dcbcba98")
      check("real upstream paintutils paints independent color cells", row.text:sub(12, 14) == "   " and row.foreground:sub(12, 14) == "eee" and row.background:sub(12, 14) == "eee" and vm.display.lines[3].background:sub(12, 14) == "eee")
    end
  end
  check("host coroutines unavailable", coroutine == nil)
  local bios = Boot.new({fs = {['/probe.lua'] = {type = 'file', text = shell_probe}, ['/environment.lua'] = {type = 'file', text = 'return token'}}}, dimensions)
  local bios_scheduler = Scheduler.new()
  Scheduler.add(bios_scheduler, 1, bios)
  for _ = 1, 10000 do
    Scheduler.tick(bios_scheduler)
    if bios.wait or bios.objects[bios.main.ref].status == 'dead' then break end
  end
  local bios_main = bios.objects[bios.main.ref]
  local bios_frame = bios_main.frames[#bios_main.frames]

  log('CC2 BIOS METRICS instructions=' .. bios.instructions .. ' objects=' .. bios.object_count .. ' collection=' .. (bios.collection and bios.collection.phase or 'none') .. ' source=' .. (bios_frame and bios_frame.proto and bios_frame.proto.source or '?'))
  assert(not bios_main.failed, 'actual BIOS: ' .. tostring(bios_main.error))
  check("actual BIOS reaches its first scheduler event wait", bios.wait ~= nil)
  for _ = 1, 10000 do
    Scheduler.tick(bios_scheduler)
    if bios.wait and #bios.events.queue == 0 or bios.objects[bios.main.ref].status == 'dead' then break end
  end
  assert(not bios.objects[bios.main.ref].failed, 'actual shell startup: ' .. tostring(bios.objects[bios.main.ref].error))

  check("actual upstream shell renders its initial prompt", bios.wait ~= nil and bios.display.lines[2].text:sub(1, 2) == '/>')
  assert(VM.queue(bios, table.pack('paste', 'probe')))
  assert(VM.queue(bios, table.pack('key', 257, false)))
  for tick = 1, 10000 do
    Scheduler.tick(bios_scheduler, tick)
    if bios.disk.fs['/shell-result.txt'] or bios.objects[bios.main.ref].status == 'dead' then break end
  end
  if not bios.disk.fs['/shell-result.txt'] then
    for i, row in ipairs(bios.display.lines) do log('CC2 SHELL FAILURE ROW ' .. i .. ' ' .. row.text) end
  end
  check("actual shell command completes filenames and persists settings", bios.disk.fs['/shell-result.txt'] and bios.disk.fs['/shell-result.txt'].text == 'shell-completion-settings-pass')
  for _ = 1, 10000 do
    Scheduler.tick(bios_scheduler, bios.events.tick + 1)
    if bios.wait and #bios.events.queue == 0 and bios.events.timer_count == 0 then break end
  end
  check("actual shell returns to event wait after a forked command", bios.wait ~= nil and #bios.events.queue == 0 and bios.events.timer_count == 0)
  plain(bios, {})
  storage.bios_execution = bios
  editor_checks.initial(bios, check)
  plain(bios, {})
  check("binary source rejected", Compiler.compile("\27Lua", "binary") == nil)
  check("malformed source rejected", Compiler.compile("local =", "malformed") == nil)
  local timers = Events.new()
  local later, earlier = Events.start_timer(timers, 2/60), Events.start_timer(timers, 1/60)
  local canceled = Events.start_timer(timers, 0)
  Events.cancel_timer(timers, canceled)
  Events.advance(timers, 0)
  check("timers never fire inline", Events.poll(timers) == nil)
  Events.advance(timers, 2)
  local e1, e2 = Events.poll(timers), Events.poll(timers)
  check("timer deadlines and ids determine order", e1[2] == earlier and e2[2] == later and Events.poll(timers) == nil)
  local queued = Events.start_timer(timers, 0)
  Events.advance(timers, 3)
  Events.cancel_timer(timers, queued)
  check("cancel removes an undelivered timer tuple", Events.poll(timers) == nil and timers.timer_count == 0)
  for i = 1, Limits.events do assert(Events.admit(timers, table.pack("char", i))) end
  check("queue overflow rejects newest input without throwing", not Events.admit(timers, table.pack("char", "overflow")) and #timers.queue == Limits.events)
  assert(Events.admit(timers, table.pack("terminate"), nil, true))
  check("lifecycle control survives a saturated queue", Events.poll(timers, nil, true)[1] == "terminate" and #timers.queue == Limits.events - 1)
  local resized = VM.new(assert(Compiler.compile([[local first = os.pullEventRaw()
    assert(first == 'term_resize')
    local second, value = os.pullEventRaw()
    assert(second == 'char' and value == 'x')
    return 'resize-order-pass']])), nil, nil, {columns = 51, rows = 19})
  assert(VM.run(resized, 1000) == "waiting")
  assert(VM.queue(resized, table.pack("char", "x")))
  check("resize queues once before existing input", VM.reconcile(resized, 80, 24) and not VM.reconcile(resized, 80, 24) and #resized.events.queue == 2)
  local status, result = VM.run(resized, 1000)
  check("guest observes resize before input", status == "dead" and result[1] == "resize-order-pass")
  local scheduler = Scheduler.new()
  local loop = assert(Compiler.compile("while true do end", "infinite"))
  for id = 1, 64 do Scheduler.add(scheduler, id, VM.new(loop)) end
  local round_ticks = 2 * math.ceil(64 * Limits.instructions_per_computer / Limits.instructions_per_tick)
  for _ = 1, round_ticks do
    local used, _, work = Scheduler.tick(scheduler)
    assert(used <= Limits.instructions_per_tick and work <= Limits.collection_work_per_tick)
  end
  local maximum = 0
  for _, vm in pairs(scheduler.machines) do
    assert(vm.instructions == 2 * Limits.instructions_per_computer, "scheduler starvation or unfair quantum")
    maximum = math.max(maximum, vm.object_count)
  end
  check("64 infinite loops obey aggregate budget and round-robin fairness", maximum > 0)
  Scheduler.remove(scheduler, 17)
  Scheduler.add(scheduler, 65, VM.new(assert(Compiler.compile("return 'responsive-pass'"))))
  for _ = 1, round_ticks do Scheduler.tick(scheduler) end
  check("responsive machine finishes beside infinite loops", scheduler.machines[65].objects[scheduler.machines[65].main.ref].status == "dead")
  local allocating = VM.new(assert(Compiler.compile([[local keep = {value = 7}
    local alias = keep
    local function read() return keep.value end
    local co = coroutine.create(function() coroutine.yield(keep); return read() end)
    assert(coroutine.resume(co))
    for i = 1, 3000 do local discard = {i, i + 1} end
    assert(alias == keep and read() == 7)
    local ok, value = coroutine.resume(co)
    assert(ok and value == 7)
    return 'reclamation-pass', keep, alias]])))
  local allocation_scheduler = Scheduler.new()
  Scheduler.add(allocation_scheduler, 1, allocating)
  local ticks = 0
  repeat
    ticks = ticks + 1
    local used, _, work = Scheduler.tick(allocation_scheduler)
    assert(used <= Limits.instructions_per_tick and work <= Limits.collection_work_per_tick)
  until allocating.objects[allocating.main.ref].status == "dead" or ticks >= 2000
  local result = allocating.objects[allocating.main.ref].result
  check("incremental reclamation preserves closures, aliases and suspended coroutines", result and result[1] == "reclamation-pass" and result[2].ref == result[3].ref and allocating.object_count < allocating.next_id - 1)
  plain(allocating, {})
  log("CC2 GUEST RESOURCE METRICS machines=64 rounds=" .. round_ticks .. " allocation_ticks=" .. ticks .. " live_objects=" .. allocating.object_count .. " allocated_objects=" .. (allocating.next_id - 1))
  storage.execution = VM.new(assert(storage.prototypes['diagnostic.lua']))
  storage.pattern_execution = VM.new(assert(Compiler.compile([[local waiting = false
    local result, count = string.gsub('ab', '.', function(letter)
      if not waiting then
        waiting = true
        local event, marker = os.pullEventRaw('continue_pattern')
        assert(event == 'continue_pattern' and marker == 11)
      end
      return letter:upper()
    end)
    return result, count]])))
  check("guest replacement waits inside its callback frame", VM.run(storage.pattern_execution, 2000) == "waiting")
  plain(storage.pattern_execution, {})
  local pattern_scheduler = Scheduler.new()
  local stuck_pattern = VM.new(assert(Compiler.compile([[string.match(string.rep('a', 30), string.rep('a?', 30) .. 'b')]])))
  local pattern_neighbor = VM.new(assert(Compiler.compile([[return 'pattern-neighbor-pass']])))
  Scheduler.add(pattern_scheduler, 1, stuck_pattern)
  Scheduler.add(pattern_scheduler, 2, pattern_neighbor)
  for _ = 1, 16 do Scheduler.tick(pattern_scheduler) end
  check("adversarial pattern remains within guest instruction quanta", stuck_pattern.instructions == 16 * Limits.instructions_per_computer and stuck_pattern.objects[stuck_pattern.main.ref].status == "running")
  check("pattern backtracking does not block another computer", pattern_neighbor.objects[pattern_neighbor.main.ref].status == "dead" and pattern_neighbor.objects[pattern_neighbor.main.ref].result[1] == "pattern-neighbor-pass")
  storage.sort_execution = VM.new(assert(Compiler.compile([[local values = {8, 3, 7, 1, 6, 2, 5, 4}
    local waiting = false
    table.sort(values, function(a, b)
      if not waiting then
        waiting = true
        local event, marker = os.pullEventRaw('continue_sort')
        assert(event == 'continue_sort' and marker == 7)
      end
      return a < b
    end)
    return table.concat(values, ',')]])))
  check("guest sort suspends inside its comparison frame", VM.run(storage.sort_execution, 1000) == "waiting")
  plain(storage.sort_execution, {})
  local sort_scheduler = Scheduler.new()
  local stuck_sort = VM.new(assert(Compiler.compile([[table.sort({2, 1}, function() while true do end end)]])))
  local neighbor = VM.new(assert(Compiler.compile([[return 'sort-neighbor-pass']])))
  Scheduler.add(sort_scheduler, 1, stuck_sort)
  Scheduler.add(sort_scheduler, 2, neighbor)
  for _ = 1, 4 do Scheduler.tick(sort_scheduler) end
  check("infinite sort comparison respects guest quanta", stuck_sort.instructions == 4 * Limits.instructions_per_computer and stuck_sort.objects[stuck_sort.main.ref].status == "running")
  check("sort exhaustion does not block another computer", neighbor.objects[neighbor.main.ref].status == "dead" and neighbor.objects[neighbor.main.ref].result[1] == "sort-neighbor-pass")
  storage.event_execution = VM.new(assert(Compiler.compile([[local preserved = {value = 9}
    local handle = assert(io.open('/resume.txt', 'w+'))
    handle:write('abcdef')
    handle:seek('set', 2)
    local canceled = os.startTimer(1/60)
    os.cancelTimer(canceled)
    local id = os.startTimer(1/60)
    term.blit('SAVE', '0123', 'ffff')
    local resumed = table.pack(os.pullEvent('resume'))
    assert(resumed.n == 4 and resumed[2] == 3 and resumed[3] == nil and resumed[4] == 4)
    assert(preserved.value == 9)
    assert(handle:read(2) == 'cd' and handle:seek() == 4)
    handle:write('XY')
    handle:close()
    local event, timer = os.pullEvent('timer')
    assert(event == 'timer' and timer == id)
    os.sleep(0)
    assert(os.clock() >= 1/60)
    return 'events-reload-pass']])))
  check("event wait preserves live guest frames", VM.run(storage.event_execution, 1000) == "waiting")
  local event_loop = VM.new(assert(Compiler.compile([[local e = table.pack(coroutine.yield())
    assert(e.n == 3 and e[1] == 'host' and e[2] == nil and e[3] == 7)
    return 'root-event-loop-pass']])), nil, nil, nil, true)
  assert(VM.run(event_loop, 1000) == "waiting")
  assert(VM.queue(event_loop, table.pack("host", nil, 7)))
  local loop_status, loop_result = VM.run(event_loop, 1000)
  check("selected OS root yield uses the same event service", loop_status == "dead" and loop_result[1] == "root-event-loop-pass")
  log("CC2 GUEST BOOTSTRAP PASS")
end)

script.on_load(function()
  -- Ephemeral flag only: no storage writes and no compilation/guest execution.
  loaded = true
end)

local function check_load()
  local snapshot = storage.snapshot
  check('on_load neither executes guests nor reconciles saved displays', storage.bios_execution.instructions == snapshot.bios_instructions and storage.resize_execution.instructions == snapshot.resize_instructions and storage.bios_execution.display.revision == snapshot.bios_revision and storage.resize_execution.display.revision == snapshot.resize_revision)
  load_checked = true
end

script.on_configuration_changed(function()
  if loaded and storage.snapshot then
    check_load()
    -- The second probe deliberately waits for automatic input/dispatch repair.
    resize_checks.configuration(storage.bios_execution, check)
  end
end)

script.on_event(defines.events.on_tick, function()
  if loaded and storage.snapshot then
    if not load_checked then check_load() end
    loaded = false
    check("separate-process reload phase", storage.snapshot.phase == "first" and game.tick > storage.snapshot.tick)
    compile_budget_checks.resume(check)
    string_budget_checks.resume(check)
    terminal_budget_checks.resume(check)
    filesystem_budget_checks.resume(check)
    file_read_budget_checks.resume(check)
    file_write_budget_checks.resume(check)
    event_budget_checks.resume(check)
    timer_advance_checks.resume(check)
    table_iteration_checks.resume(check)
    table_budget_checks.resume(check)
    execution_budget_checks.resume(check)
    coroutine_error_checks.resume(check)
    tuple_budget_checks.resume(check)
    continuation_checks.resume(check)
    full_heap_checks.resume(check)
    continuation_budget_checks.resume(check)
    unwind_checks.resume(check)
    frame_cleanup_checks.resume(check)
    live_disk_checks.reload(check)
    for name, proto in pairs(storage.prototypes) do
      plain(proto, {})
      check("prototype survives reload " .. name, proto.version == Compiler.VERSION and #proto.instructions > 0)
    end
    plain(storage.execution, {})
    while storage.execution.collection do Collector.step(storage.execution, 256) end
    local bios = storage.bios_execution
    plain(bios, {})
    resize_checks.reload(storage.resize_execution, dimensions, check)
    editor_checks.reload(bios, check)
    check("actual BIOS and shell wait survive separate-process reload", bios.wait ~= nil and bios.disk.fs['/shell-result.txt'].text == 'shell-completion-settings-pass')
    local old_instructions = bios.instructions
    bios.disk.fs['/shell-result.txt'] = nil
    assert(VM.queue(bios, table.pack('paste', 'probe')))
    assert(VM.queue(bios, table.pack('key', 257, false)))
    local bios_scheduler = Scheduler.new()
    Scheduler.add(bios_scheduler, 1, bios)
    for _ = 1, 10000 do
      Scheduler.tick(bios_scheduler, bios.events.tick + 1)
      if bios.disk.fs['/shell-result.txt'] or bios.objects[bios.main.ref].status == 'dead' then break end
    end
    check("reloaded upstream shell executes another command without reboot", bios.instructions > old_instructions and bios.disk.fs['/shell-result.txt'] and bios.disk.fs['/shell-result.txt'].text == 'shell-completion-settings-pass')
    plain(storage.pattern_execution, {})
    check("replacement callback frames survive separate-process reload", storage.pattern_execution.wait ~= nil)
    assert(VM.queue(storage.pattern_execution, table.pack("continue_pattern", 11)))
    local pattern_status, pattern_result = VM.run(storage.pattern_execution, 20000)
    check("resumed replacement preserves output and exact count", pattern_status == "dead" and pattern_result.n == 2 and pattern_result[1] == "AB" and pattern_result[2] == 2)
    plain(storage.sort_execution, {})
    check("sorting comparison frames survive separate-process reload", storage.sort_execution.wait ~= nil)
    assert(VM.queue(storage.sort_execution, table.pack("continue_sort", 7)))
    local sort_status, sort_result = VM.run(storage.sort_execution, 20000)
    check("resumed guest sort preserves values and ordering", sort_status == "dead" and sort_result[1] == "1,2,3,4,5,6,7,8")
    plain(storage.event_execution, {})
    check("event wait and display survive reload", storage.event_execution.wait ~= nil and storage.event_execution.display.lines[1].text:sub(1, 4) == "SAVE")
    assert(VM.queue(storage.event_execution, table.pack("resume", 3, nil, 4)))
    VM.advance(storage.event_execution, game.tick)
    check("saved timer resumes and then sleep waits", VM.run(storage.event_execution, 1000) == "waiting")
    VM.advance(storage.event_execution, game.tick + 1)
    local event_status, event_result = VM.run(storage.event_execution, 1000)
    check("sleep resumes on simulation ticks after reload", event_status == "dead" and event_result[1] == "events-reload-pass")
    check("durable handle offset and staged content survive reload", storage.event_execution.disk.fs['/resume.txt'].text == 'abcdXY')
    local status, result, _, failure = VM.run(storage.execution, 100000)
    assert(not storage.execution.objects[storage.execution.main.ref].failed, tostring(failure))
    check("data-backed execution resumes after reload", status == "dead" and result.n == 4 and result[1] == "diagnostic-pass" and result[2] == 15 and result[3] == nil and result[4] == 9)
    log("CC2 GUEST COMPLETE RELOAD checks=" .. storage.checks)
  elseif not storage.snapshot then
    -- Loading the bootstrap map also runs on_load. Consume that flag here so
    -- waiting for the asynchronous save cannot masquerade as a second process.
    loaded = false
    check("diagnostic suspended by instruction budget", VM.run(storage.execution, 8) == "running")
    Collector.start(storage.execution)
    Collector.step(storage.execution, 1)
    check("guest execution pauses during incremental collection", not pcall(VM.run, storage.execution, 1))
    plain(storage.execution, {})
    storage.snapshot = {phase = "first", tick = game.tick,
      bios_instructions = storage.bios_execution.instructions, resize_instructions = storage.resize_execution.instructions,
      bios_revision = storage.bios_execution.display.revision, resize_revision = storage.resize_execution.display.revision}
    log("CC2 GUEST SNAPSHOT tick=" .. game.tick)
    game.server_save("cc2-resume")
    log("CC2 GUEST COMPLETE FIRST checks=" .. storage.checks)
  end
end)
