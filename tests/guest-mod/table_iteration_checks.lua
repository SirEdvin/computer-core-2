local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
function M.initial(check)
  local prototype = assert(Compiler.compile([[local long = ...
    local target = {[long] = 1}
    for i = 1, 512 do target[i] = i end
    target[10] = nil
    target[10] = 10
    iteration_target = target
    os.pullEvent('iterate')
    assert(rawlen(target) == 512)
    assert(next(target, long) == 1)
    assert(next(target, 10) == 11)
    target[10] = nil
    assert(next(target, 9) == 11)
    target[10] = 10
    assert(next(target, 9) == 10)
    assert(not pcall(next, target, 'missing'))
    local count = 0
    for key, value in pairs(target) do
      count = count + 1
      if key == long then assert(value == 1) else assert(value == key) end
    end
    assert(next(target, 512) == nil)
    return count
  ]], '=table-iteration-history'))
  local vm = VM.new(prototype, table.pack(string.rep('k', Limits.string_bytes)))
  for _ = 1, 200 do
    VM.run(vm, 256)
    if vm.wait then break end
  end
  assert(vm.wait and not vm.objects[vm.main.ref].failed)
  local ref = vm.objects[vm.env.ref].entries['s:iteration_target'].value
  local target = vm.objects[ref.ref]
  check('table key membership retains stable iteration positions', #target.order == 513
    and target.known[target.order[1]] == 1 and target.known['n:10'] == 11 and target.known['n:512'] == 513)
  -- Exercise a compatible saved graph whose private membership metadata predates
  -- indexed iteration; no guest execution may repair it during on_load.
  for encoded in pairs(target.known) do target.known[encoded] = true end
  target.sequence_length = nil
  storage.table_iteration_vm, storage.table_iteration_target = vm, ref
end
function M.resume(check)
  local vm, ref = storage.table_iteration_vm, storage.table_iteration_target
  local target = vm.objects[ref.ref]
  check('legacy iteration metadata survives load without mutation', vm.wait ~= nil and target.known['n:10'] == true and target.sequence_length == nil)
  assert(VM.queue(vm, table.pack('iterate')))
  local status, result
  for _ = 1, 200 do
    status, result = VM.run(vm, 256)
    if status == 'dead' then break end
  end
  check('indexed next preserves history and long-key iteration after reload', status == 'dead'
    and not vm.objects[vm.main.ref].failed and result[1] == 513 and #target.order == 513
    and target.known[target.order[1]] == 1 and target.known['n:10'] == 11 and target.known['n:512'] == 513 and target.sequence_length == 512)
end
return M
