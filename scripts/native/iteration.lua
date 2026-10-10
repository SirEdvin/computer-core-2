-- Engine-order raw iteration over bounded plain native value maps.
-- Credit deferral retains read/output stages; never return a fake guest result.
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
-- Conservative provisional inventory/array-scan charge, independent of cache
-- and prior deletions. This is not a wall-clock or hard real-time guarantee.
local read_work = 16 + 4 * (Limits.table_keys + 1024)
function M.start(machine, args, admit)
  assert(Execution.type(machine, args[1]) == 'table', 'table expected')
  Execution.validate_value(machine, args[2])
  return M.step(machine, {kind = 'helper', service = 'native.next.step', object = args[1], index = args[2]}, admit)
end
function M.step(machine, p, admit)
  if not p.read then
    local target = machine.heap[p.object.native_ref]
    if not p.input_paid then
      local bytes = type(p.index) == 'string' and 2 * (#p.index + 1) or 0
      if bytes > 0 and admit('string', bytes) == false then return 'continue', p end
      p.control, p.input_paid = Execution.encode_key(machine, p.index), true
    end
    if not target.iteration then
      p.order = p.order or {n = 0, keys = {}, positions = {}}
      if not p.build_ready then
        if admit('table', read_work) == false then return 'continue', p end
        p.build_key = next(target.values, p.order.cursor)
        p.build_ready = true
      end
      if p.build_key == nil then
        target.iteration, p.order, p.build_ready = p.order, nil, nil
      else
        local bytes = type(p.build_key) == 'string' and 2 * #p.build_key or 0
        if bytes > 0 and admit('string', bytes) == false then return 'continue', p end
        assert(p.order.n < Limits.table_keys, 'native iteration inventory quota exceeded')
        p.order.n = p.order.n + 1
        p.order.keys[p.order.n], p.order.positions[p.build_key] = p.build_key, p.order.n
        p.order.cursor, p.build_key, p.build_ready = p.build_key, nil, nil
      end
      return 'continue', p
    end
    if not p.position then
      if p.control == nil then p.position = 1
      else p.position = assert(target.iteration.positions[p.control], "invalid key to 'next'") + 1 end
    end
    if admit('table', 8) == false then return 'continue', p end
    p.encoded = target.iteration.keys[p.position]
    if p.encoded ~= nil then
      p.value = target.values[p.encoded]
      p.position = p.position + 1
      if p.value == nil then return 'continue', p end
    end
    p.read = true
    -- Encode private pending reference-key ownership as a real heap edge before
    -- any output deferral can let collection run. Scalar strings stay uncut.
    if type(p.encoded) == 'string' and p.encoded:sub(1, 1) == 'r' then
      p.reference = Execution.decode_key(machine, p.encoded)
    end
  end
  if not p.result_paid then
    if admit('continuation', p.encoded == nil and 5 or 9) == false then return 'continue', p end
    p.result_paid = true
  end
  if p.encoded == nil then return 'return', {n = 1} end
  if type(p.encoded) == 'string' and p.encoded:sub(1, 1) == 's' then
    if admit('string', 2 * #p.encoded) == false then return 'continue', p end
  end
  local decoded = p.reference
  if decoded == nil then decoded = Execution.decode_key(machine, p.encoded) end
  return 'return', {n = 2, decoded, p.value}
end
return M
