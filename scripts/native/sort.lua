-- Persistent bottom-up merge sort. Never call host table.sort on guest data.
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
function M.start(machine, args, spend)
  assert(Execution.type(machine, args[1]) == 'table', 'table expected')
  assert(args[2] == nil or Execution.type(machine, args[2]) == 'function', 'comparison function expected')
  spend('table', 1)
  Execution.admit_helper(machine, spend)
  return 'continue', {kind = 'helper', service = 'table.sort.step', phase = 'copy', object = args[1],
    compare = args[2], source = {}, target = {}, size = 0, width = 1, first = 1}
end
local function choose(p, right)
  if right then p.target[p.output] = p.source[p.right]; p.right = p.right + 1
  else p.target[p.output] = p.source[p.left]; p.left = p.left + 1 end
  p.output = p.output + 1
end
function M.step(machine, p, spend)
  spend('table', 8)
  if p.phase == 'copy' then
    if p.size == Limits.table_keys then p.phase = 'merge'; return 'continue', p end
    local value = Execution.get(machine, p.object, p.size + 1)
    if value == nil then p.phase = 'merge'
    else p.size = p.size + 1; p.source[p.size] = value end
  elseif p.phase == 'merge' then
    if p.width >= p.size then p.phase, p.check = 'check', 2
    elseif p.first > p.size then
      p.source, p.target, p.width, p.first = p.target, {}, p.width * 2, 1
    else
      if not p.output then
        p.middle = math.min(p.first + p.width - 1, p.size)
        p.last = math.min(p.first + 2 * p.width - 1, p.size)
        p.left, p.right, p.output = p.first, p.middle + 1, p.first
      end
      if p.output > p.last then p.first, p.output = p.last + 1, nil
      elseif p.left > p.middle then choose(p, true)
      elseif p.right > p.last then choose(p, false)
      elseif p.values then choose(p, not not p.values[1]); p.values = nil
      elseif p.compare then
        return 'call', {callee = p.compare, args = {n = 2, p.source[p.right], p.source[p.left]}}
      else
        local left, right = p.source[p.left], p.source[p.right]
        assert(type(left) == type(right) and (type(left) == 'number' or type(left) == 'string'),
          'unsupported native sort comparison')
        if type(left) == 'string' then spend('string', #left + #right) end
        choose(p, right < left)
      end
    end
  elseif p.phase == 'check' then
    if p.check > p.size then p.phase = 'commit'
    elseif p.values then
      assert(not p.values[1], 'invalid order function for sorting')
      p.values, p.check = nil, p.check + 1
    elseif p.compare then
      return 'call', {callee = p.compare, args = {n = 2, p.source[p.check], p.source[p.check - 1]}}
    else p.check = p.check + 1 end
  elseif p.phase == 'commit' then
    -- Preflight and publication share one reservation. Guest comparators may
    -- have changed the input; quota refusal must not publish a partial sort.
    spend('table', 1 + 8 * p.size)
    local target = machine.heap[p.object.native_ref]
    local missing = 0
    for i = 1, p.size do
      if Execution.get(machine, p.object, i) == nil then missing = missing + 1 end
      Execution.validate_value(machine, p.source[i])
    end
    assert(target.keys + missing <= Limits.table_keys, 'native table key quota exceeded')
    for i = 1, p.size do Execution.set(machine, p.object, i, p.source[i]) end
    return 'return', {n = 0}
  else error('invalid native sort phase', 0) end
  return 'continue', p
end
return M
