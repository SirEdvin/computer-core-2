-- Initial native block dispatcher. Kept isolated from playable computers until
-- full coroutine/protected-service/collection acceptance passes.
local Limits = require('__computer_core_2__.scripts.guest.limits')
local Codegen = require('__computer_core_2__.scripts.native.codegen')
local Collector = require('__computer_core_2__.scripts.native.collector')
local M = {VERSION = 5}
function M.compatible(machine)
  if machine.version ~= M.VERSION and not (machine.version == 4 and machine.cell_pool == nil) then
    return false, 'unsupported native execution version'
  end
  local pool = machine.cell_pool
  if pool ~= nil and (type(pool) ~= 'table' or pool.version ~= 1 or type(pool.ids) ~= 'table'
    or #pool.ids > Limits.register_pool) then return false, 'unsupported native cell pool' end
  return true
end
local function retained(machine, id)
  if id == nil or id == 1 then return machine.bundle end
  return assert(machine.bundles and machine.bundles[id], 'missing native retained bundle')
end
local supported_meta = {s__index = true, s__newindex = true, s__call = true, s__metatable = true, s__tostring = true}
local function tuple(values)
  assert(type(values) == 'table' and type(values.n) == 'number' and values.n >= 0
    and values.n <= Limits.tuple_values and values.n == math.floor(values.n), 'native tuple limit exceeded')
  return values
end
local function copy(values, first)
  tuple(values)
  first = first or 1
  local result = {n = math.max(0, values.n - first + 1)}
  for i = first, values.n do result[i - first + 1] = values[i] end
  return result
end
local function object(machine, ref, kind)
  assert(type(ref) == 'table' and ref.native_ref, 'native object expected')
  local result = assert(machine.heap[ref.native_ref], 'invalid native reference')
  assert(not kind or result.kind == kind, 'native ' .. (kind or 'object') .. ' expected')
  return result
end
local function allocate(machine, value)
  assert(not machine.collector, 'native allocation paused during collection')
  assert(machine.objects < Limits.heap_objects, 'native heap quota exceeded')
  local id = machine.next_id
  machine.next_id, machine.objects = id + 1, machine.objects + 1
  machine.heap[id] = value
  value.object_slot = #machine.object_ids + 1
  machine.object_ids[value.object_slot] = id
  machine.allocations = (machine.allocations or 0) + 1
  return {native_ref = id}
end
local function local_cell(machine, value)
  assert(not machine.collector, 'native allocation paused during collection')
  local ids = machine.cell_pool and machine.cell_pool.ids
  local id = ids and ids[#ids]
  if not id then return allocate(machine, {kind = 'cell', value = value, captured = false}).native_ref end
  local cell = assert(machine.heap[id], 'missing native pooled cell')
  assert(cell.kind == 'cell' and cell.captured == false and cell.value == nil, 'invalid native pooled cell')
  ids[#ids] = nil
  cell.value = value
  machine.cell_reuses = (machine.cell_reuses or 0) + 1
  return id
end
-- One paid control step releases at most cleanup_work_per_step/4 slots.
-- A saturated pool needs no further scan: remaining cells follow ordinary GC.
-- Only local cells explicitly known not to have escaped are ever detached.
local function release_cells(machine, f, limit, pending, cursor_field)
  local pool = machine.cell_pool
  if not pool then
    pool = {version = 1, ids = {}}
    machine.cell_pool, machine.version = pool, M.VERSION
  end
  local cursor = pending[cursor_field] or 1
  if cursor > limit or #pool.ids >= Limits.register_pool then
    machine.cleanup_work = (machine.cleanup_work or 0) + 1
    pending[cursor_field] = limit + 1
    return true
  end
  local last = math.min(limit, cursor + math.floor(Limits.cleanup_work_per_step / 4) - 1)
  for slot = cursor, last do
    local id = f.cells[slot]
    local cell = id and machine.heap[id]
    if cell and cell.captured == false then
      cell.value = nil
      f.cells[slot] = nil
      pool.ids[#pool.ids + 1] = id
    end
    machine.cleanup_work = (machine.cleanup_work or 0) + 4
    pending[cursor_field] = slot + 1
    if #pool.ids >= Limits.register_pool then pending[cursor_field] = limit + 1; return true end
  end
  return pending[cursor_field] > limit
end
local function validate(machine, value)
  local kind = type(value)
  if kind == 'nil' or kind == 'boolean' or kind == 'number' then return value end
  if kind == 'string' then assert(#value <= Limits.string_bytes, 'native string quota exceeded'); return value end
  assert(kind == 'table' and getmetatable(value) == nil, 'host value forbidden in native execution')
  assert(type(value.native_ref) == 'number' and value.native_ref >= 1
    and value.native_ref == math.floor(value.native_ref), 'invalid native reference')
  for field in pairs(value) do assert(field == 'native_ref', 'host value forbidden in native execution') end
  local target = object(machine, value)
  assert(target.kind == 'table' or target.kind == 'closure' or target.kind == 'service'
    or target.kind == 'thread' or target.kind == 'wrapped', 'private native object forbidden')
  return value
end
local function validate_tuple(machine, values)
  tuple(values)
  assert(getmetatable(values) == nil, 'host tuple metatable forbidden')
  for field in pairs(values) do
    assert(field == 'n' or (type(field) == 'number' and field >= 1 and field <= values.n
      and field == math.floor(field)), 'invalid native tuple field')
  end
  for i = 1, values.n do validate(machine, values[i]) end
  return values
end
local function key(value)
  local kind = type(value)
  if kind == 'string' then assert(#value <= Limits.string_bytes, 'native string quota exceeded'); return 's' .. value end
  if kind == 'number' then assert(value == value, 'table index is NaN'); return value end
  if kind == 'boolean' then return value and 'b1' or 'b0' end
  if kind == 'table' and value.native_ref then return 'r' .. value.native_ref end
  error('invalid native table key', 0)
end
local function get(machine, ref, index)
  validate(machine, ref); validate(machine, index)
  local target = object(machine, ref, 'table')
  if index == nil or (type(index) == 'number' and index ~= index) then return nil end
  return target.values[key(index)]
end
local function set(machine, ref, index, value)
  assert(not machine.collector, 'native table mutation paused during collection')
  validate(machine, ref); validate(machine, index); validate(machine, value)
  local target, encoded = object(machine, ref, 'table'), key(index)
  if target.used_as_metatable then
    assert(type(encoded) ~= 'string' or encoded:sub(1, 3) ~= 's__' or supported_meta[encoded], 'unsupported native metamethod')
  end
  if value == nil then
    if target.values[encoded] ~= nil then target.keys = target.keys - 1 end
  elseif target.values[encoded] == nil then
    assert(target.keys < Limits.table_keys, 'native table key quota exceeded')
    target.keys = target.keys + 1
    -- Adding keys invalidates cached order; deleting/overwriting existing keys
    -- preserves positions, including a generic-for cursor retained across save.
    target.iteration = nil
  end
  target.values[encoded] = value
  -- Persist a completed dense-prefix scan. Appending is constant work; filling
  -- a hole before an existing suffix invalidates rather than scanning in a write.
  if target.dense_length ~= nil and type(encoded) == 'number' and encoded >= 1
    and encoded == math.floor(encoded) then
    if value == nil and encoded <= target.dense_length then target.dense_length = encoded - 1
    elseif value ~= nil and encoded == target.dense_length + 1 then
      if target.values[encoded + 1] == nil then target.dense_length = encoded
      else target.dense_length = nil end
    end
  end
end
local function api(machine, bundle, admission, used)
  local a = {}
  used = used or {}
  local function spend(domain, amount)
    if amount == 0 then return end
    if admission then assert(admission(domain, amount) ~= false, 'native generated work quota exceeded')
    else
      -- Untimed low-level fixture dispatch has local ceilings. Actual scheduling
      -- supplies the durable, shared tick ledger through a host-only callback.
      local limit = assert(Limits[domain .. '_work_per_computer'], 'invalid native generated work domain')
      assert(amount <= limit - (used[domain] or 0), 'native generated work quota exceeded')
      used[domain] = (used[domain] or 0) + amount
    end
  end
  a.admit = spend -- Host-only core-service accounting; never a guest value.
  local function numbers(values)
    local bytes = 0
    for i = 1, values.n do
      local value = values[i]
      assert(type(value) == 'number' or type(value) == 'string', 'number expected')
      if type(value) == 'string' then bytes = bytes + #value end
    end
    spend('continuation', 4 * values.n)
    spend('string', bytes)
    for i = 1, values.n do values[i] = assert(tonumber(values[i]), 'number expected') end
    return values
  end
  function a.one(value) return {n = 1, value} end
  function a.empty() return {n = 0} end
  function a.constant(pid, index) return bundle.prototypes[pid].constants[index] end
  function a.copy(values, first)
    tuple(values)
    spend('continuation', 1 + 4 * math.max(0, values.n - (first or 1) + 1))
    return copy(values, first)
  end
  function a.append(result, part, expand)
    tuple(result); tuple(part)
    local size = expand and part.n or 1
    assert(size <= Limits.tuple_values - result.n, 'native tuple limit exceeded')
    spend('continuation', 1 + 4 * size)
    for i = 1, size do result[result.n + i] = part[i] end
    result.n = result.n + size
  end
  function a.declare(frame, slot, value)
    local old = frame.cells[slot] and machine.heap[frame.cells[slot]]
    if old and old.captured == false then old.value = value
    else frame.cells[slot] = local_cell(machine, value) end
  end
  function a.read(frame, slot) return assert(machine.heap[frame.cells[slot]], 'undeclared local').value end
  function a.write(frame, slot, value) assert(machine.heap[frame.cells[slot]], 'undeclared local').value = value end
  function a.upvalue(frame, slot) return assert(machine.heap[frame.upvalues[slot]], 'missing upvalue').value end
  function a.write_upvalue(frame, slot, value) assert(machine.heap[frame.upvalues[slot]], 'missing upvalue').value = value end
  function a.closure(frame, pid)
    local cells = {}
    for i, binding in ipairs(bundle.prototypes[pid].upvalues) do
      cells[i] = assert(binding.kind == 'local' and frame.cells[binding.slot] or frame.upvalues[binding.slot], 'missing captured cell')
      machine.heap[cells[i]].captured = true
    end
    return allocate(machine, {kind = 'closure', proto = pid, upvalues = cells, bundle_id = frame.bundle_id})
  end
  function a.table() return allocate(machine, {kind = 'table', values = {}, keys = 0}) end
  function a.table_key(index, operations)
    spend('table', 8 * operations)
    if type(index) == 'string' then spend('string', operations * (1 + #index)) end
  end
  function a.get(ref, index)
    a.table_key(index, 1)
    return get(machine, ref, index)
  end
  function a.set(ref, index, value)
    a.table_key(index, 1)
    return set(machine, ref, index, value)
  end
  function a.array(ref, start, values)
    tuple(values)
    local target = object(machine, ref, 'table')
    assert(type(start) == 'number' and start >= 1 and start == math.floor(start)
      and start + values.n - 1 <= Limits.table_keys, 'native array range limit exceeded')
    spend('table', 16 + 8 * values.n)
    local added, removed = 0, 0
    for i = 1, values.n do
      validate(machine, values[i])
      local prior = target.values[start + i - 1]
      if prior == nil and values[i] ~= nil then added = added + 1
      elseif prior ~= nil and values[i] == nil then removed = removed + 1 end
    end
    assert(target.keys + added - removed <= Limits.table_keys, 'native table key quota exceeded')
    -- Remove holes first so an accepted replacement cannot temporarily exceed
    -- its preflighted final key count. No guest callbacks run in this phase.
    for i = 1, values.n do
      if values[i] == nil then set(machine, ref, start + i - 1, nil) end
    end
    for i = 1, values.n do
      if values[i] ~= nil then set(machine, ref, start + i - 1, values[i]) end
    end
  end
  function a.numeric(value)
    return numbers({n = 1, value})[1]
  end
  function a.arithmetic(left, right)
    local values = numbers({n = 2, left, right})
    return values[1], values[2]
  end
  function a.numeric_for(first, last, step)
    local values = numbers({n = 3, first, last, step})
    return a.one(values[1]), a.one(values[2]), a.one(values[3])
  end
  function a.compare(left, right)
    assert(type(left) == type(right) and (type(left) == 'number' or type(left) == 'string'), 'unsupported native comparison')
    if type(left) == 'string' then spend('string', #left + #right) end
    return left, right
  end
  function a.equal(left, right)
    if type(left) == 'table' and type(right) == 'table' then return left.native_ref == right.native_ref end
    if type(left) == 'string' and type(right) == 'string' then spend('string', #left + #right) end
    return left == right
  end
  function a.length(value)
    if type(value) == 'string' then return #value end
    local t = object(machine, value, 'table')
    -- A deterministic valid Lua border; precise sparse-table borders are unspecified.
    if t.dense_length ~= nil then spend('table', 1); return t.dense_length end
    local length = 0
    while length < Limits.table_keys do
      spend('table', 1)
      if t.values[length + 1] == nil then break end
      length = length + 1
    end
    t.dense_length = length
    return length
  end
  function a.concat(values)
    tuple(values)
    local parts, bytes, estimate = {}, 0, 0
    for i = 1, values.n do
      local value = values[i]
      assert(type(value) == 'string' or type(value) == 'number', 'string expected')
      estimate = estimate + (type(value) == 'string' and #value or 32)
      assert(estimate <= Limits.string_bytes, 'native string quota exceeded')
    end
    spend('continuation', 4 * values.n)
    spend('string', 2 * estimate)
    for i = 1, values.n do
      assert(type(values[i]) == 'string' or type(values[i]) == 'number', 'string expected')
      local part = tostring(values[i])
      bytes = bytes + #part
      assert(bytes <= Limits.string_bytes, 'native string quota exceeded')
      parts[i] = part
    end
    return table.concat(parts)
  end
  -- Compact generated identifiers do not rewrite or inspect guest literals.
  a.o, a.e, a.r, a.u = a.one, a.empty, a.read, a.upvalue
  a.d, a.v, a.n, a.p = a.declare, a.write_upvalue, a.numeric, a.append
  a.b, a.q, a.j = a.arithmetic, a.compare, a.numeric_for
  return a
end
local function frame(machine, bundle, closure, args, receiver)
  bundle = retained(machine, closure.bundle_id)
  local proto = assert(bundle.prototypes[closure.proto], 'missing native prototype')
  local f = {proto = closure.proto, bundle_id = closure.bundle_id, pc = proto.entry, t = {}, cells = {}, upvalues = closure.upvalues,
    args = proto.vararg and copy(args, #proto.params + 1) or {n = 0}, receiver = receiver}
  local helpers = api(machine, bundle)
  for i, slot in ipairs(proto.params) do helpers.declare(f, slot, args[i]) end
  return f
end
function M.new(bundle, arguments)
  assert(bundle.version == Codegen.VERSION, 'unsupported native bundle version')
  local machine = {version = M.VERSION, bundle = bundle, heap = {}, object_ids = {}, objects = 0, next_id = 1, frames = {}, status = 'running', blocks = 0, collect_at = Limits.collection_interval}
  local env = allocate(machine, {kind = 'table', values = {}, keys = 0})
  machine.env = env
  local envcell = allocate(machine, {kind = 'cell', value = env})
  local upvalues = {}
  -- Phobos's main chunk captures _ENV from its synthetic outer scope.
  for i = 1, #bundle.prototypes[1].upvalues do upvalues[i] = envcell.native_ref end
  machine.frames[1] = frame(machine, bundle, {proto = 1, upvalues = upvalues}, validate_tuple(machine, arguments or {n = 0}))
  local root = allocate(machine, {kind = 'thread', status = 'running', frames = machine.frames, depth = 1})
  machine.root, machine.active = root.native_ref, root.native_ref
  return machine
end
function M.service(machine, name)
  local ref = M.service_value(machine, name)
  set(machine, machine.env, name, ref)
  return ref
end
function M.service_value(machine, name, data) return allocate(machine, {kind = 'service', name = name, data = data}) end
-- Private file records are only reachable through trusted service bindings.
function M.handle_value(machine, record) return allocate(machine, record) end
function M.table_value(machine) return allocate(machine, {kind = 'table', values = {}, keys = 0}) end
function M.validate_value(machine, value) return validate(machine, value) end
function M.set(machine, ref, index, value) return set(machine, ref, index, value) end
function M.get(machine, ref, index) return get(machine, ref, index) end
function M.bundle_for(machine, id) return retained(machine, id) end
function M.admit_helper(machine, spend)
  local thread = machine.heap[machine.active]
  local boundaries = thread.boundaries or {}
  spend('continuation', 1 + 4 * (#thread.frames + #boundaries) + 4 * Limits.continuation_depth)
  local seen, depth = {}, 0
  local function retain(receiver)
    while type(receiver) == 'table' and receiver.mode == 'helper' do
      local operation = receiver.operation
      if seen[operation] then break end
      seen[operation], depth = true, depth + 1
      assert(depth < Limits.continuation_depth, 'native helper nesting quota exceeded')
      receiver = operation.receiver
    end
  end
  retain(thread.pending and thread.pending.receiver)
  for _, f in ipairs(thread.frames) do retain(f.receiver) end
  for _, boundary in ipairs(boundaries) do retain(boundary.receiver) end
end
-- Trusted compiled bundles only; callers own compiler admission and snapshots.
function M.register_bundle(machine, bundle, spend, environment)
  assert(bundle.version == Codegen.VERSION and bundle.source_version, 'invalid native compiled bundle')
  assert(not machine.collector, 'native allocation paused during collection')
  environment = environment == nil and machine.env or environment
  object(machine, environment, 'table')
  assert(machine.objects <= Limits.heap_objects - 2, 'native heap quota exceeded')
  local proto = assert(bundle.prototypes[1], 'missing native main prototype')
  spend('continuation', 1 + 4 * #proto.upvalues + 4 * Limits.call_frames)
  local id
  for candidate = 2, Limits.call_frames do
    if not machine.bundles or not machine.bundles[candidate] then id = candidate; break end
  end
  if not id then
    machine.collect_at = math.min(machine.collect_at, machine.objects)
    error('native retained bundle quota exceeded', 0)
  end
  local env = allocate(machine, {kind = 'cell', value = environment})
  local cells = {}
  for i = 1, #proto.upvalues do cells[i] = env.native_ref end
  local ref = allocate(machine, {kind = 'closure', proto = 1, bundle_id = id, upvalues = cells})
  machine.bundles = machine.bundles or {machine.bundle}
  machine.bundles[id] = bundle
  return ref
end
-- Host-only key boundaries; admission belongs to the resumable helper.
function M.encode_key(machine, index)
  validate(machine, index)
  if index ~= nil then return key(index) end
end
function M.decode_key(machine, encoded)
  if type(encoded) == 'number' then return encoded end
  assert(type(encoded) == 'string', 'invalid native encoded key')
  local prefix = encoded:sub(1, 1)
  if prefix == 's' then return encoded:sub(2) end
  if encoded == 'b0' then return false end
  if encoded == 'b1' then return true end
  assert(prefix == 'r', 'invalid native encoded key')
  return validate(machine, {native_ref = assert(tonumber(encoded:sub(2)), 'invalid native reference key')})
end
function M.type(machine, value)
  if type(value) ~= 'table' then return type(value) end
  local kind = object(machine, value).kind
  return (kind == 'closure' or kind == 'service' or kind == 'wrapped') and 'function' or kind
end
function M.executable(bundle)
  assert(bundle.version == Codegen.VERSION and type(bundle.generated) == 'string'
    and #bundle.generated <= Codegen.OUTPUT_BYTES, 'invalid native generated bundle')
  return assert(load(bundle.generated, '=native-generated:' .. bundle.name, 't', {}))()
end

local function activate(machine, id)
  machine.active = id
  machine.frames = machine.heap[id].frames
end
local function prefixed(values, flag)
  tuple(values)
  assert(values.n < Limits.tuple_values, 'native tuple prefix limit exceeded')
  local result = {n = values.n + 1, flag}
  for i = 1, values.n do result[i + 1] = values[i] end
  return result
end
local function publish(c, receiver, values, tail)
  if type(receiver) == 'table' then
    if receiver.mode == 'protected' then
      c.pending = {kind = 'protected_result', boundary = receiver.index, values = values}
      return
    elseif receiver.mode == 'scalar' then values = {n = 1, values[1]}; receiver = receiver.slot
    elseif receiver.mode == 'discard' then c.pending = nil; return
    elseif receiver.mode == 'helper' then
      receiver.operation.values = values
      c.pending = receiver.operation
      return
    else error('invalid native result receiver', 0) end
  end
  if tail then c.pending = {kind = 'return', values = values}
  else c.frames[#c.frames].t[receiver] = values; c.pending = nil end
end
local function helper_transfer(machine, c, p, status, result)
  if status == 'continue' then
    assert(type(result) == 'table' and result.kind == 'helper' and type(result.service) == 'string', 'invalid native helper control')
    result.receiver, result.tail = p.receiver, p.tail
    c.pending = result
  elseif status == 'call' then
    validate(machine, result.callee); validate_tuple(machine, result.args)
    c.pending = {kind = 'call', callee = result.callee, args = result.args,
      receiver = {mode = 'helper', operation = p}}
  else
    assert(status == 'return', 'invalid native helper transfer')
    validate_tuple(machine, result)
    publish(c, p.receiver, result, p.tail)
  end
end
function M.resume(machine, values)
  assert(not machine.collector, 'native resumption paused during collection')
  assert(machine.status == 'yield' and machine.waiting, 'native machine not suspended')
  local c = machine.heap[machine.active]
  local result = copy(validate_tuple(machine, values))
  publish(c, machine.waiting, result, machine.wait_tail)
  machine.wait_tail = nil
  machine.waiting, machine.yielded, machine.status = nil, nil, 'running'
end
local function to_parent(machine, c, values, finished)
  local r = assert(c.resumer, 'missing native resumer')
  local result = r.wrap and copy(values) or prefixed(values, true)
  local parent = machine.heap[r.owner]
  publish(parent, r.receiver, result, r.tail)
  c.status, c.resumer, c.pending = finished and 'dead' or 'suspended', nil, nil
  if finished then c.frames = {} end
  parent.status = 'running'
  activate(machine, r.owner)
end
local function start_coroutine(machine, bundle, parent, p, ref, args, wrap)
  local c = object(machine, ref, 'thread')
  if c.status ~= 'suspended' then
    if wrap then error('cannot resume ' .. c.status .. ' coroutine', 0) end
    publish(parent, p.receiver, {n = 2, false, 'cannot resume ' .. c.status .. ' coroutine'}, p.tail)
    return
  end
  assert(parent.depth < Limits.coroutine_depth, 'native coroutine depth limit exceeded')
  if not c.started then
    local target = object(machine, c.target)
    if target.kind == 'closure' then c.frames[1] = frame(machine, bundle, target, args)
    else
      c.frames[1] = {proto = 1, pc = 1, t = {}, cells = {}, upvalues = {}, args = {n = 0}}
      c.pending = {kind = 'call', callee = c.target, args = args, receiver = 0, tail = true}
    end
    c.started, c.target = true, nil
  else
    assert(c.waiting, 'native suspended coroutine missing receiver')
    publish(c, c.waiting, copy(args), c.wait_tail)
    c.waiting, c.wait_tail = nil, nil
  end
  c.resumer = {owner = machine.active, receiver = p.receiver, tail = p.tail, wrap = wrap}
  c.status, c.depth = 'running', parent.depth + 1
  parent.pending, parent.status = nil, 'normal'
  activate(machine, ref.native_ref)
end
local function raise_guest(machine, bundle, c, message, level)
  level = level == nil and 1 or tonumber(level)
  assert(level and level > -math.huge and level < math.huge, 'invalid guest error level')
  level = math.floor(level)
  if type(message) == 'string' or type(message) == 'number' then
    local f = level > 0 and c.frames[#c.frames - level + 1]
    if f then
      bundle = retained(machine, f.bundle_id)
      local pos = bundle.prototypes[f.proto].maps[f.last_pc or f.pc] or {line = 1}
      local name = bundle.name
      if name:sub(1, 1) == '=' or name:sub(1, 1) == '@' then name = name:sub(2) end
      message = name .. ':' .. pos.line .. ': ' .. tostring(message)
    end
  end
  error(message, 0)
end
local function builtin(machine, bundle, c, p, target, helpers)
  local name, args = target.name, p.args
  local result
  if target.kind == 'wrapped' then
    start_coroutine(machine, bundle, c, p, {native_ref = target.thread}, args, true)
    return true
  elseif name == 'core.type' then result = {n = 1, M.type(machine, args[1])}
  elseif name == 'core.error' then raise_guest(machine, bundle, c, args[1], args[2])
  elseif name == 'core.assert' then
    if not args[1] then raise_guest(machine, bundle, c, args[2] or 'assertion failed!', 1) end
    result = copy(args)
  elseif name == 'core.pcall' or name == 'core.xpcall' then
    c.boundaries = c.boundaries or {}
    assert(#c.boundaries < Limits.call_frames, 'native protected boundary limit exceeded')
    local handler = name == 'core.xpcall' and args[2] or nil
    if name == 'core.xpcall' then assert(M.type(machine, handler) == 'function', 'error handler function expected') end
    local index = #c.boundaries + 1
    c.boundaries[index] = {depth = #c.frames, receiver = p.receiver, tail = p.tail, handler = handler, phase = 'body'}
    c.pending = {kind = 'call', callee = args[1], args = copy(args, name == 'core.xpcall' and 3 or 2), receiver = {mode = 'protected', index = index}}
    return true
  elseif name == 'core.setmetatable' then
    local t = object(machine, args[1], 'table')
    local meta = args[2] ~= nil and object(machine, args[2], 'table') or nil
    helpers.admit('table', 16 + 4 * (meta and meta.keys or 0))
    if t.metatable then assert(get(machine, t.metatable, '__metatable') == nil, 'protected metatable') end
    if meta then
      for field in pairs(meta.values) do
        if type(field) == 'string' and field:sub(1, 3) == 's__' then
          helpers.admit('string', #field)
          assert(supported_meta[field], 'unsupported native metamethod')
        end
      end
      meta.used_as_metatable = true
    end
    t.metatable = args[2]
    result = {n = 1, args[1]}
  elseif name == 'core.getmetatable' then
    helpers.admit('table', 8)
    local t = type(args[1]) == 'table' and object(machine, args[1])
    local meta = t and t.metatable
    local hidden = meta and get(machine, meta, '__metatable')
    if hidden == nil then hidden = meta end
    result = {n = 1, hidden}
  elseif name == 'core.rawget' or name == 'core.rawset' then
    helpers.admit('table', 8)
    if type(args[2]) == 'string' then helpers.admit('string', 1 + #args[2]) end
    if name == 'core.rawget' then result = {n = 1, get(machine, args[1], args[2])}
    else set(machine, args[1], args[2], args[3]); result = {n = 1, args[1]} end
  elseif name == 'core.coroutine.create' or name == 'core.coroutine.wrap' then
    assert(M.type(machine, args[1]) == 'function', 'function expected')
    local ref = allocate(machine, {kind = 'thread', status = 'suspended', frames = {}, target = args[1]})
    if name == 'core.coroutine.wrap' then ref = allocate(machine, {kind = 'wrapped', thread = ref.native_ref}) end
    result = {n = 1, ref}
  elseif name == 'core.coroutine.running' then result = {n = 2, {native_ref = machine.active}, machine.active == machine.root}
  elseif name == 'core.coroutine.status' then result = {n = 1, object(machine, args[1], 'thread').status}
  elseif name == 'core.coroutine.resume' then
    start_coroutine(machine, bundle, c, p, args[1], copy(args, 2), false)
    return true
  elseif name == 'core.coroutine.yield' then
    if c.resumer then
      -- Admit the parent's result prefix before publishing suspension.
      if not c.resumer.wrap then assert(args.n < Limits.tuple_values, 'native tuple prefix limit exceeded') end
      c.waiting, c.wait_tail = p.receiver, p.tail
      to_parent(machine, c, args, false)
    else
      machine.status, machine.yielded, machine.waiting, machine.wait_tail = 'yield', copy(args), p.receiver, p.tail
      c.pending = nil
    end
    return true
  else return false end
  publish(c, p.receiver, result, p.tail)
  return true
end
function M.install_core(machine)
  if machine.core_installed then return end
  local library = allocate(machine, {kind = 'table', values = {}, keys = 0})
  for _, name in ipairs({'create', 'resume', 'yield', 'status', 'running', 'wrap'}) do
    set(machine, library, name, allocate(machine, {kind = 'service', name = 'core.coroutine.' .. name}))
  end
  set(machine, machine.env, 'coroutine', library)
  set(machine, machine.env, 'type', allocate(machine, {kind = 'service', name = 'core.type'}))
  for _, name in ipairs({'error', 'assert', 'pcall', 'xpcall', 'setmetatable', 'getmetatable', 'rawget', 'rawset'}) do
    set(machine, machine.env, name, allocate(machine, {kind = 'service', name = 'core.' .. name}))
  end
  machine.core_installed = true
end
local function failure(machine, c, err, bundle, f)
  local valid = pcall(validate, machine, err)
  if not valid then err = 'invalid host error value' end
  if type(err) == 'string' then err = err:sub(1, 4096) end
  local location = f and bundle.prototypes[f.proto].maps[f.last_pc or f.pc] or {line = 1}
  c.pending = {kind = 'unwind', value = err, source = bundle.name, line = location and location.line or 1, phase = 'temps', cursor = 1}
end
local function unwind(machine, bundle, c, p)
  local boundary = c.boundaries and c.boundaries[#c.boundaries]
  local depth = boundary and boundary.depth or 0
  if #c.frames > depth then
    local f = c.frames[#c.frames]
    bundle = retained(machine, f.bundle_id)
    local proto = bundle.prototypes[f.proto]
    if p.phase == 'cells' then
      if release_cells(machine, f, proto.locals, p, 'cursor') then
        c.frames[#c.frames] = nil; p.phase, p.cursor = 'temps', 1
      end
      return
    end
    local limit = p.phase == 'temps' and proto.temps or proto.locals
    local values = p.phase == 'temps' and f.t or f.cells
    local last = math.min(limit, p.cursor + Limits.cleanup_work_per_step - 1)
    machine.cleanup_work = (machine.cleanup_work or 0) + math.max(0, last - p.cursor + 1)
    for i = p.cursor, last do values[i] = nil end
    p.cursor = last + 1
    if p.cursor > limit then
      if p.phase == 'temps' then p.phase, p.cursor = 'cells', 1
      else c.frames[#c.frames] = nil; p.phase, p.cursor = 'temps', 1 end
    end
    return
  end
  if boundary then
    if boundary.handler and boundary.phase == 'body' then
      boundary.phase = 'handler'
      c.pending = {kind = 'call', callee = boundary.handler, args = {n = 1, p.value}, receiver = {mode = 'protected', index = #c.boundaries}}
    else
      c.boundaries[#c.boundaries] = nil
      publish(c, boundary.receiver, {n = 2, false, boundary.phase == 'handler' and 'error in error handling' or p.value}, boundary.tail)
    end
  elseif c.resumer then
    local r, parent = c.resumer, machine.heap[c.resumer.owner]
    if r.wrap then parent.pending = {kind = 'failure', value = p.value}
    else publish(parent, r.receiver, {n = 2, false, p.value}, r.tail) end
    c.status, c.resumer, c.pending = 'dead', nil, nil
    parent.status = 'running'
    activate(machine, r.owner)
  else
    local message = type(p.value) == 'table' and 'guest reference error' or tostring(p.value)
    machine.status, machine.error = 'error', {message = message, value = p.value, source = p.source, line = p.line}
    c.status, c.pending = 'dead', nil
  end
end
local function metamethod(machine, ref, name)
  local target = object(machine, ref)
  return target.metatable and get(machine, target.metatable, name)
end
local function index_transfer(machine, c, p, write, helpers)
  local ref = p.object
  if type(ref) == 'string' and not write then
    ref = assert(machine.string_library, 'native string library not installed')
  end
  local target = object(machine, ref, 'table')
  -- Reserve both encoded operations before a write; a refused second lookup
  -- must not publish content or alter the delegation cursor.
  helpers.table_key(p.index, write and 2 or 1)
  if target.metatable then helpers.table_key(write and '__newindex' or '__index', 1) end
  local value = get(machine, ref, p.index)
  local meta
  if value == nil then meta = metamethod(machine, ref, write and '__newindex' or '__index') end
  if meta == nil then
    if write then set(machine, ref, p.index, p.value); c.pending = nil
    else publish(c, p.receiver, {n = 1, value}) end
  elseif M.type(machine, meta) == 'table' then
    assert((p.depth or 0) < Limits.call_frames, 'native metamethod chain limit exceeded')
    p.object, p.depth = meta, (p.depth or 0) + 1
  else
    helpers.admit('continuation', 1 + 4 * (write and 3 or 2))
    c.pending = {kind = 'call', callee = meta, args = write and {n = 3, ref, p.index, p.value} or {n = 2, ref, p.index},
      receiver = write and {mode = 'discard'} or {mode = 'scalar', slot = p.receiver}}
  end
end
-- Each native block and control transfer is a separately admitted step. Switching
-- coroutine ownership never recurses on the host stack and never fabricates a
-- result on internal quantum exhaustion.
function M.run(machine, bundle, executable, credits, services, resolve)
  local compatible, reason = M.compatible(machine)
  assert(compatible, reason)
  assert(type(credits) == 'number' and credits >= 0 and credits < math.huge and credits == math.floor(credits), 'invalid native credits')
  if credits > 0 and machine.objects >= machine.collect_at and not machine.collector then Collector.start(machine) end
  if machine.collector then return machine.status, Collector.step(machine, credits) end
  local untimed = {}
  local helpers, spent, prepaid, checkpoint_frame = api(machine, bundle, services and services['native.work'], untimed), 0, false, nil
  local helper_cache = {[bundle] = helpers}
  local function checkpoint(label)
    local f = checkpoint_frame
    if f.pc ~= label then return false end
    if prepaid then prepaid = false
    elseif spent >= credits then return false
    else spent, machine.blocks = spent + 1, machine.blocks + 1 end
    f.last_pc = label
    return true
  end
  while spent < credits and machine.status == 'running' and not machine.host_request do
    spent, machine.blocks = spent + 1, machine.blocks + 1
    local c = machine.heap[machine.active]
    local f = c.frames[#c.frames]
    local selected
    if f and f.bundle_id and f.bundle_id ~= 1 then selected = machine.bundles and machine.bundles[f.bundle_id]
    else selected = machine.bundle end
    if not selected then
      machine.recovery = {message = 'native retained frame bundle missing', previous_status = machine.status}
      machine.status = 'recovery'
      break
    end
    bundle = selected
    local ok, err = pcall(function()
      if c.pending then
        local p = c.pending
        if p.kind == 'call' then
          local target = object(machine, p.callee)
          if target.kind == 'closure' then
            assert(p.tail or #c.frames < Limits.call_frames, 'native call frame quota exceeded')
            local receiver = p.receiver
            if p.tail then receiver = f.receiver end
            if p.tail then
              -- Construct before detaching the caller: allocation refusal keeps
              -- its original recovery graph. Retain the child during slicing.
              p.child = p.child or frame(machine, bundle, target, p.args, receiver)
              if release_cells(machine, f, bundle.prototypes[f.proto].locals, p, 'release_cursor') then
                c.frames[#c.frames], c.pending = p.child, nil
              end
            else
              c.frames[#c.frames + 1] = frame(machine, bundle, target, p.args, receiver)
              c.pending = nil
            end
          elseif target.kind == 'service' or target.kind == 'wrapped' then
            if not builtin(machine, bundle, c, p, target, helpers) then
              local service = assert(services and services[target.name], 'unsupported native service ' .. target.name)
              local status, result = service(machine, p.args, target.data)
              if status == 'continue' then helper_transfer(machine, c, p, status, result)
              else
                validate_tuple(machine, result)
                if status == 'yield' then
                  machine.status, machine.yielded, machine.waiting, machine.wait_tail = 'yield', result, p.receiver, p.tail
                  c.pending = nil
                else
                  assert(status == 'return', 'invalid native service transfer')
                  publish(c, p.receiver, result, p.tail)
                end
              end
            end
          elseif target.kind == 'table' then
            helpers.table_key('__call', 1)
            local method = metamethod(machine, p.callee, '__call')
            assert(method ~= nil, 'attempt to call a non-function')
            assert((p.depth or 0) < Limits.call_frames, 'native callable metamethod chain limit exceeded')
            helpers.admit('continuation', 1 + 4 * (p.args.n + 1))
            local args = prefixed(p.args, p.callee)
            p.callee, p.args, p.depth = method, args, (p.depth or 0) + 1
          else error('attempt to call a non-function', 0) end
        elseif p.kind == 'helper' then
          local service = assert(services and services[p.service], 'unsupported native helper continuation')
          local status, result = service(machine, p)
          helper_transfer(machine, c, p, status, result)
        elseif p.kind == 'return' then
          if not release_cells(machine, f, bundle.prototypes[f.proto].locals, p, 'release_cursor') then
            -- Values/receiver remain rooted in the pending operation and frame.
          elseif #c.frames == 1 then
            if c.resumer then to_parent(machine, c, p.values, true)
            else
              machine.status, machine.result, c.status, c.pending = 'return', p.values, 'dead', nil
              c.frames = {}; machine.frames = c.frames
            end
          else
            c.frames[#c.frames] = nil
            publish(c, f.receiver, p.values)
          end
        elseif p.kind == 'protected_result' then
          local boundary = assert(c.boundaries[p.boundary], 'missing protected boundary')
          assert(p.boundary == #c.boundaries, 'native protected ownership mismatch')
          local result = boundary.phase == 'handler' and {n = 2, false, p.values[1]} or prefixed(p.values, true)
          c.boundaries[p.boundary] = nil
          publish(c, boundary.receiver, result, boundary.tail)
        elseif p.kind == 'index' then index_transfer(machine, c, p, false, helpers)
        elseif p.kind == 'set' then index_transfer(machine, c, p, true, helpers)
        elseif p.kind == 'unwind' then unwind(machine, bundle, c, p)
        elseif p.kind == 'failure' then error(p.value, 0)
        else error('invalid native transfer', 0) end
      else
        if resolve then
          executable = resolve(bundle)
          if not executable then return end
        else assert(bundle == machine.bundle, 'native additional bundle resolver required') end
        helpers = helper_cache[bundle]
        if not helpers then
          helpers = api(machine, bundle, services and services['native.work'], untimed)
          helper_cache[bundle] = helpers
        end
        local block = assert(executable[f.proto][f.pc], 'missing native block')
        f.last_pc = f.pc
        prepaid, checkpoint_frame = true, f
        local kind, first, second, receiver = block(f, helpers, f.t, checkpoint)
        if kind == 'call' or kind == 'tailcall' then
          c.pending = {kind = 'call', callee = first, args = tuple(second), receiver = receiver, tail = kind == 'tailcall'}
        elseif kind == 'return' then c.pending = {kind = kind, values = tuple(first)}
        elseif kind == 'index' then c.pending = {kind = kind, object = first, index = second, receiver = receiver}
        elseif kind == 'set' then c.pending = {kind = kind, object = first[1], index = first[2], value = first[3]}
        else assert(kind == nil, 'invalid generated transfer') end
      end
    end)
    if not ok then
      failure(machine, machine.heap[machine.active], err, bundle, f)
    end
    if resolve and not executable then break end
  end
  return machine.status, spent
end
return M
