local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local prototype = assert(Compiler.compile([[native_child = coroutine.create(term.clear)
  os.pullEvent('retry')
  return pcall(coroutine.resume, native_child)
]], '=native-coroutine-quota'))
local function prepare()
  local vm = VM.new(prototype, nil, nil, {columns = 51, rows = 19})
  VM.run(vm, 1000)
  assert(vm.wait)
  return vm
end
local function exercise(vm, check, phase)
  local revision, line = vm.display.revision, vm.display.lines[1]
  assert(VM.queue(vm, table.pack('retry')))
  local context = {computer = {used = 0, limit = Limits.compiler_work_per_computer}, terminal_computer = {used = 0, limit = 0}}
  local status, result
  for _ = 1, 20 do
    status, result = VM.run(vm, 256, context)
    if status == 'dead' then break end
  end
  local child = vm.objects[vm.objects[vm.env.ref].entries['s:native_child'].value.ref]
  check('native child quota error preserves protected resume semantics '..phase, status == 'dead'
    and not vm.objects[vm.main.ref].failed and result.n == 3 and result[1] == true and result[2] == false
    and result[3] == 'per-computer terminal work limit exceeded' and child.status == 'dead'
    and child.failed == true and child.error == result[3] and vm.current == nil)
  check('native child quota refusal preserves display '..phase, vm.display.revision == revision and vm.display.lines[1] == line
    and context.terminal_computer.used == 0)
end
function M.initial(check)
  exercise(prepare(), check, 'initial')
  storage.native_coroutine_error_vm = prepare()
end
function M.resume(check)
  local vm = storage.native_coroutine_error_vm
  check('native child and parent wait survive reload', vm.wait ~= nil
    and vm.objects[vm.objects[vm.env.ref].entries['s:native_child'].value.ref].status == 'suspended')
  exercise(vm, check, 'reloaded')
end
return M
