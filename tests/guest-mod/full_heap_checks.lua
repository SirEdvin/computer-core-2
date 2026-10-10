local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Collector = require("__computer_core_2__.scripts.guest.collector")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local prototype = assert(Compiler.compile([[leaf=coroutine.create(os.pullEventRaw)
  middle=coroutine.create(function() local a,b,c=coroutine.resume(leaf,'go'); return a,b,c end)
  upper=coroutine.create(function() local a,b,c=coroutine.resume(middle); return a,b,c end)
  top=coroutine.create(function() local a,b,c=coroutine.resume(upper); return a,b,c end)
  local a,b,c=coroutine.resume(top); return a,b,c]], '=full-heap-recovery'))
local function allocate(vm, data)
  assert(vm.object_count < Limits.heap_objects)
  local id = vm.next_id
  vm.next_id = id + 1
  vm.objects[id] = data
  vm.object_count = vm.object_count + 1
  vm.allocations_since_collection = vm.allocations_since_collection + 1
  return {ref=id}
end
local function table_(vm)
  return allocate(vm,{kind='table',entries={},known={},order={},sequence_length=0})
end
local function set(vm, ref, key, value)
  local data = vm.objects[ref.ref]
  local encoded = type(key) == 'number' and ('n:'..string.format('%.17g',key)) or ('s:'..key)
  data.order[#data.order+1] = encoded
  data.known[encoded] = #data.order
  data.entries[encoded] = {key=key,value=value}
  if type(key) == 'number' then data.sequence_length = key end
end
local function prepare(custom)
  local vm = VM.new(custom or prototype,nil,nil,{columns=51,rows=19})
  VM.run(vm,1000)
  assert(vm.wait)
  vm.disk.fs['/keep.lua'] = {type='file',text='return 73'}
  -- Synthetic, valid quota fixture: conservatively captured active registers
  -- cannot be recycled. Padding is real data-only heap objects rooted in the
  -- environment, not a forged object_count or a substituted engine response.
  vm.free_cells = {}
  for _, object in pairs(vm.objects) do
    if object.kind == 'cell' then object.captured = true end
  end
  local root = table_(vm)
  set(vm,vm.env,'heap_padding',root)
  local groups = {table_(vm),table_(vm)}
  for i, group in ipairs(groups) do set(vm,root,i,group) end
  for _, group in ipairs(groups) do
    local i = 0
    while vm.object_count < Limits.heap_objects and i < Limits.table_keys do
      i = i + 1
      set(vm,group,i,table_(vm))
    end
  end
  assert(vm.object_count == Limits.heap_objects)
  -- Remove pre-fixture garbage before filling the last space with live padding.
  Collector.start(vm)
  while vm.collection do Collector.step(vm,1024) end
  for _, group in ipairs(groups) do
    local i = #vm.objects[group.ref].order
    while vm.object_count < Limits.heap_objects and i < Limits.table_keys do
      i = i + 1
      set(vm,group,i,table_(vm))
    end
  end
  assert(vm.object_count == Limits.heap_objects)
  return vm
end
local function exercise(vm, check, phase)
  if vm.wait then assert(VM.queue(vm,table.pack('go',9))) end
  local staged, escaped = vm.pending_operation ~= nil and vm.pending_operation.kind == 'failure', nil
  for _ = 1, 100 do
    local before = vm.instructions
    local ok, status, _, used = pcall(VM.run,vm,1)
    if not ok then escaped = status; break end
    assert(used <= 1 and vm.instructions - before == used)
    if vm.pending_operation and vm.pending_operation.kind == 'failure' then staged = true end
    if status == 'dead' then break end
  end
  check('full-heap secondary recovery stays inside guest execution '..phase..(escaped and (': '..tostring(escaped)) or ''), escaped == nil)
  local main = vm.objects[vm.main.ref]
  local ownership = main.status == 'dead' and main.failed and main.error == 'guest allocation limit exceeded'
    and vm.current == nil and vm.pending_operation == nil
  for _, object in pairs(vm.objects) do
    if object.kind == 'coroutine' then ownership = ownership and object.status == 'dead' and object.resumer == nil end
  end
  check('full-heap refusal leaves no stranded resumer '..phase, ownership and staged)
  check('full-heap error recovery preserves disk content '..phase, vm.disk.fs['/keep.lua'].text == 'return 73')
end
function M.initial(check)
  exercise(prepare(),check,'initial')
  storage.full_heap_recovery = prepare()
  local vm = prepare()
  assert(VM.queue(vm,table.pack('go',9)))
  for _ = 1,100 do
    VM.run(vm,1)
    if vm.pending_operation and vm.pending_operation.kind == 'failure' then break end
  end
  check('secondary heap failure can save before recovery completes', vm.pending_operation ~= nil
    and vm.pending_operation.kind == 'failure' and vm.pending_operation.co.ref == vm.current
    and vm.object_count == Limits.heap_objects)
  storage.full_heap_pending = vm
  storage.full_heap_pending_instructions = vm.instructions

  local handler = assert(Compiler.compile([[return xpcall(function() os.pullEventRaw('go'); return {} end,
    function(err) return err end)]], '=full-heap-handler'))
  vm = prepare(handler)
  assert(VM.queue(vm,table.pack('go')))
  local status, result
  for _ = 1,100 do status,result = VM.run(vm,1); if status == 'dead' then break end end
  check('heap-refused xpcall handler returns a protected error', status == 'dead' and not vm.objects[vm.main.ref].failed
    and result.n == 2 and result[1] == false and result[2] == 'error in error handling' and vm.current == nil)

  local state = Scheduler.new()
  vm = prepare()
  assert(VM.queue(vm,table.pack('go',9)))
  Scheduler.add(state,1,vm)
  local healthy = VM.new(assert(Compiler.compile('os.pullEventRaw("go"); return 73')),nil,nil,{columns=51,rows=19})
  VM.run(healthy,1000)
  assert(VM.queue(healthy,table.pack('go')))
  Scheduler.add(state,2,healthy)
  local ok, _, visited = pcall(Scheduler.tick,state,800)
  check('heap-refused computer cannot crash or starve its healthy neighbour', ok and visited == 2
    and vm.objects[vm.main.ref].failed and healthy.objects[healthy.main.ref].result[1] == 73)
end
function M.resume(check)
  local vm = storage.full_heap_recovery
  check('full heap and suspended resumers survive reload', vm.wait ~= nil and vm.object_count == Limits.heap_objects)
  exercise(vm,check,'reloaded')
  local pending = storage.full_heap_pending
  check('secondary heap recovery resumes without on_load execution', pending.pending_operation ~= nil
    and pending.pending_operation.kind == 'failure' and pending.instructions == storage.full_heap_pending_instructions)
  exercise(pending,check,'pending-reloaded')
  Collector.start(vm)
  while vm.collection do Collector.step(vm,1024) end
  check('failed frames remain reclaimable without losing live heap roots', vm.object_count < Limits.heap_objects
    and vm.objects[vm.objects[vm.env.ref].entries['s:heap_padding'].value.ref] ~= nil)
end
return M
