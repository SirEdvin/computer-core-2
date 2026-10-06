-- Explicit Lua 5.2 guest frames. Only data (never host functions/coroutines) is durable.
local M = {VERSION = 1}
local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local Filesystem = require("__computer_core_2__.scripts.filesystem")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local Terminal = require("__computer_core_2__.scripts.guest.terminal")
local Events = require("__computer_core_2__.scripts.guest.events")
local Files = require("__computer_core_2__.scripts.guest.files")
local Format = require("__computer_core_2__.scripts.guest.format")
local stdlib_proto = assert(Compiler.compile(require("__computer_core_2__.scripts.guest.stdlib"), "=guest-stdlib"))
-- Ephemeral host scope only. Durable graphs contain counters, never callbacks.
local active_budget
local recovery_scope = false
local cleanup_remaining = 0
local function spend_cleanup_work(vm, amount)
  if amount > cleanup_remaining then return false end
  cleanup_remaining = cleanup_remaining - amount
  vm.cleanup_work = (vm.cleanup_work or 0) + amount
  return true
end
local function spend_continuation_work(amount)
  -- Trusted construction and mandatory recovery do not consume ordinary copy
  -- credits. Recovery stays bounded by size/depth and execution quanta.
  if not active_budget or recovery_scope then return end
  assert(type(amount) == "number" and amount >= 0 and amount < math.huge and amount == math.floor(amount), "invalid continuation work charge")
  local computer, aggregate = active_budget.continuation_computer, active_budget.continuation_aggregate
  if amount > computer.limit - computer.used then error("per-computer continuation work limit exceeded", 0) end
  if aggregate and amount > aggregate.limit - aggregate.used then error("aggregate continuation work limit exceeded", 0) end
  computer.used = computer.used + amount
  if aggregate then aggregate.used = aggregate.used + amount end
end

local function spend_compile_work(amount)
  local context = assert(active_budget, "missing compiler budget scope")
  local computer, aggregate = context.computer, context.aggregate
  if amount > computer.limit - computer.used then error("per-computer compiler work limit exceeded", 0) end
  if aggregate and amount > aggregate.limit - aggregate.used then error("aggregate compiler work limit exceeded", 0) end
  computer.used = computer.used + amount
  if aggregate then aggregate.used = aggregate.used + amount end
end

local function spend_string_work(amount)
  assert(type(amount) == "number" and amount >= 0 and amount < math.huge and amount == math.floor(amount), "invalid string work charge")
  local context = assert(active_budget, "missing string budget scope")
  local computer, aggregate = context.string_computer, context.string_aggregate
  if amount > computer.limit - computer.used then error("per-computer string work limit exceeded", 0) end
  if aggregate and amount > aggregate.limit - aggregate.used then error("aggregate string work limit exceeded", 0) end
  computer.used = computer.used + amount
  if aggregate then aggregate.used = aggregate.used + amount end
end

local function numeric_string_work(value)
  return type(value) == "string" and 1 + #value or 0
end
local function number_(value, base)
  local work = numeric_string_work(value) + numeric_string_work(base)
  if work > 0 then spend_string_work(work) end
  return tonumber(value, base)
end
local function tuple_size(count, message)
  if type(count) ~= "number" or count < 0 or count > Limits.tuple_values or count ~= math.floor(count) then
    error(message or "guest tuple limit exceeded", 0)
  end
end
local function tuple(...) return table.pack(...) end
local function spend_terminal_work(amount)
  local context = assert(active_budget, "missing terminal budget scope")
  local computer, aggregate = context.terminal_computer, context.terminal_aggregate
  if amount > computer.limit - computer.used then error("per-computer terminal work limit exceeded", 0) end
  if aggregate and amount > aggregate.limit - aggregate.used then error("aggregate terminal work limit exceeded", 0) end
  computer.used = computer.used + amount
  if aggregate then aggregate.used = aggregate.used + amount end
end
local function truth(value) return value ~= nil and value ~= false end
local function spend_filesystem_work(amount)
  assert(type(amount) == "number" and amount >= 0 and amount < math.huge and amount == math.floor(amount), "invalid filesystem work charge")
  local context = assert(active_budget, "missing filesystem budget scope")
  local computer, aggregate = context.filesystem_computer, context.filesystem_aggregate
  if amount > computer.limit - computer.used then error("per-computer filesystem work limit exceeded", 0) end
  if aggregate and amount > aggregate.limit - aggregate.used then error("aggregate filesystem work limit exceeded", 0) end
  computer.used = computer.used + amount
  if aggregate then aggregate.used = aggregate.used + amount end
end
local function spend_event_work(amount)
  assert(type(amount) == "number" and amount >= 0 and amount < math.huge and amount == math.floor(amount), "invalid event work charge")
  local context = assert(active_budget, "missing event budget scope")
  local computer, aggregate = context.event_computer, context.event_aggregate
  if amount > computer.limit - computer.used then error("per-computer event work limit exceeded", 0) end
  if aggregate and amount > aggregate.limit - aggregate.used then error("aggregate event work limit exceeded", 0) end
  computer.used = computer.used + amount
  if aggregate then aggregate.used = aggregate.used + amount end
end
local function object(vm, value, kind)
  local result = type(value) == "table" and vm.objects[value.ref]
  if not result or (kind and result.kind ~= kind) then error("expected guest " .. (kind or "object"), 0) end
  return result
end
local function allocate(vm, data)
  if vm.object_count >= Limits.heap_objects then error("guest allocation limit exceeded", 0) end
  local id = vm.next_id
  vm.next_id = id + 1
  vm.objects[id] = data
  vm.object_count = vm.object_count + 1
  vm.allocations_since_collection = vm.allocations_since_collection + 1
  return {ref = id}
end
local function equal(a, b)
  if type(a) == "table" and type(b) == "table" then return a.ref == b.ref end
  if type(a) == "string" and type(b) == "string" and #a == #b then spend_string_work(1 + 2 * #a) end
  return a == b
end
local function spend_table_work(amount)
  -- Trusted VM construction initializes tables outside execution. Guest access
  -- always enters through VM.run and therefore has an ephemeral budget scope.
  if not active_budget then return end
  assert(type(amount) == "number" and amount >= 0 and amount < math.huge and amount == math.floor(amount), "invalid table work charge")
  local computer, aggregate = active_budget.table_computer, active_budget.table_aggregate
  if amount > computer.limit - computer.used then error("per-computer table work limit exceeded", 0) end
  if aggregate and amount > aggregate.limit - aggregate.used then error("aggregate table work limit exceeded", 0) end
  computer.used = computer.used + amount
  if aggregate then aggregate.used = aggregate.used + amount end
end
local function key(value)
  local kind = type(value)
  if kind == "nil" then error("table index is nil", 0) end
  if kind == "number" then
    if value ~= value then error("table index is NaN", 0) end
    spend_table_work(65)
    if value == 0 then value = 0 end
    return "n:" .. string.format("%.17g", value)
  elseif kind == "table" then spend_table_work(65); return "r:" .. value.ref
  elseif kind == "string" then spend_table_work(1 + 2 * (#value + 2)); return "s:" .. value
  elseif kind == "boolean" then spend_table_work(1); return value and "b:1" or "b:0" end
  error("invalid guest key", 0)
end
local function rawget_(vm, tab, k)
  local data = object(vm, tab, "table")
  -- Nil/NaN reads miss; only writes reject these keys (Lua 5.2).
  if k == nil or type(k) == "number" and k ~= k then return nil end
  local record = data.entries[key(k)]
  return record and record.value
end
local function rawset_(vm, tab, k, value)
  local data = object(vm, tab, "table")
  local encoded = key(k)
  local new_key = value ~= nil and not data.known[encoded]
  if new_key and #data.order >= Limits.table_keys then error("guest table key limit exceeded", 0) end
  local sequence = data.sequence_length
  if sequence ~= nil and type(k) == "number" and k > 0 and k == math.floor(k) then
    if value == nil and k <= sequence then sequence = k - 1
    elseif value ~= nil and k == sequence + 1 then
      sequence = k
      -- Reserve extension probes before publishing the new entry or metadata.
      while rawget_(vm, tab, sequence + 1) ~= nil do sequence = sequence + 1 end
    end
  end
  if value == nil then data.entries[encoded] = nil
  else
    if new_key then
      data.order[#data.order + 1] = encoded; data.known[encoded] = #data.order
    end
    data.entries[encoded] = {key = k, value = value}
  end
  data.sequence_length = sequence
end
local function table_(vm) return allocate(vm, {kind = "table", entries = {}, order = {}, known = {}, sequence_length = 0}) end
local function meta(vm, value, name)
  local data = type(value) == "table" and object(vm, value)
  local mt = data and data.meta or (type(value) == "string" and vm.string_meta)
  if not mt then return nil end
  return rawget_(vm, mt, name)
end
local function cell(vm, frame, index)
  local id = frame.registers[index]
  if not id then
    vm.free_cells = vm.free_cells or {}
    id = table.remove(vm.free_cells)
    if not id then id = allocate(vm, {kind = "cell", captured = false}).ref end
    frame.registers[index] = id
    frame.register_limit = math.max(frame.register_limit or frame.proto.max_stack_size, index + 1)
  end
  return vm.objects[id]
end
local function release_frame(vm, frame)
  if not frame or not frame.registers then return end
  vm.free_cells = vm.free_cells or {}
  for i = 0, (frame.register_limit or frame.proto.max_stack_size) - 1 do
    -- Bounded, deterministic pool of already quota-counted internal objects.
    if #vm.free_cells >= Limits.register_pool then return end
    local id = frame.registers[i]
    local data = id and vm.objects[id]
    -- Missing metadata in older execution graphs is deliberately ineligible.
    if data and data.captured == false then
      data.value = nil
      vm.free_cells[#vm.free_cells + 1] = id
      frame.registers[i] = nil
    end
  end
end
local function get(vm, frame, index)
  local id = frame.registers[index]
  return id and vm.objects[id].value
end
local function put(vm, frame, index, value)
  if type(value) == "string" and #value > Limits.string_bytes then error("guest string limit exceeded", 0) end
  cell(vm, frame, index).value = value
end
local function rk(vm, frame, index)
  if index >= 256 then return frame.proto.constants[index - 256 + 1].value end
  return get(vm, frame, index)
end
local function values(vm, frame, start, count)
  tuple_size(count)
  spend_continuation_work(1 + count)
  local result = {n = count}
  for i = 1, count do result[i] = get(vm, frame, start + i - 1) end
  return result
end
local deliver, call, finish, concatenate
local function frame_(vm, closure, args, continuation)
  tuple_size(args.n, "guest argument tuple limit exceeded")
  local function_ = object(vm, closure, "closure")
  local proto = function_.proto
  spend_continuation_work(1 + 3 * proto.num_params + math.max(0, args.n - proto.num_params))
  local frame = {kind = "frame", proto = proto, closure = closure, pc = 1, top = proto.num_params,
    registers = {}, varargs = {n = math.max(0, args.n - proto.num_params)}, continuation = continuation}
  for i = 1, proto.num_params do put(vm, frame, i - 1, args[i]) end
  for i = 1, frame.varargs.n do frame.varargs[i] = args[proto.num_params + i] end
  return frame
end
local function destination(co, index, count, a)
  return {kind = "register", frame = #co.frames, a = index, count = count, top = a}
end
local function prefixed(prefix, result, admitted)
  tuple_size(result.n + 1)
  if not admitted then spend_continuation_work(2 + result.n) end
  local out = {n = result.n + 1, [1] = prefix}
  for i = 1, result.n do out[i + 1] = result[i] end
  return out
end
finish = function(vm, co, result, err, failed)
  tuple_size(result.n)
  -- Validate status-prefix growth while failure still belongs to the child.
  local returned = co.resumer and (failed and tuple(false, err) or prefixed(true, result))
  co.status = "dead"
  co.resume_depth = nil
  co.result, co.error, co.failed = result, err, failed
  for i = #co.frames, 1, -1 do release_frame(vm, co.frames[i]) end
  co.frames = {}
  if co.resumer then
    local resumer = co.resumer
    co.resumer = nil
    local parent = vm.objects[resumer.id]
    parent.status = "running"
    vm.current = resumer.id
    deliver(vm, parent, resumer.continuation, returned)
  else vm.current = nil end
end
deliver = function(vm, co, continuation, result)
  tuple_size(result.n)
  if not continuation then return finish(vm, co, result) end
  local kind = continuation.kind
  if kind == "register" then
    local frame = assert(co.frames[continuation.frame])
    local count = continuation.count < 0 and result.n or continuation.count
    spend_continuation_work(1 + 3 * count)
    for i = 1, count do put(vm, frame, continuation.a + i - 1, result[i]) end
    if continuation.count < 0 then frame.top = continuation.a + count end
  elseif kind == "return" then
    local boundary = co.frames[#co.frames]
    -- Refuse before removing the protected boundary that must catch this error.
    local next_continuation = boundary.continuation
    if next_continuation and next_continuation.kind == "protected" then
      tuple_size(result.n + 1)
      spend_continuation_work(2 + result.n)
      next_continuation = {kind = "protected", parent = next_continuation.parent, prefix_admitted = true}
    end
    local frame = table.remove(co.frames)
    release_frame(vm, frame)
    deliver(vm, co, next_continuation, result)
  elseif kind == "protected" then
    deliver(vm, co, continuation.parent, prefixed(true, result, continuation.prefix_admitted))
  elseif kind == "error_handler" then
    deliver(vm, co, continuation.parent, tuple(false, result[1]))
  elseif kind == "string_result" then
    if type(result[1]) ~= "string" then error("__tostring must return a string", 0) end
    deliver(vm, co, continuation.parent, tuple(result[1]))
  elseif kind == "compare" then
    local value = truth(result[1])
    if continuation.negate then value = not value end
    local frame = assert(co.frames[continuation.frame])
    if value ~= continuation.accept then frame.pc = frame.pc + 1 end
  elseif kind == "concat" then
    concatenate(vm, co, continuation.frame, continuation.a, continuation.index, continuation.first, result[1])
  elseif kind ~= "ignore" then error("unknown guest continuation " .. tostring(kind), 0) end
end
local function index_(vm, co, value, k, continuation, write, assigned)
  for _ = 1, 100 do
    local data = type(value) == "table" and object(vm, value)
    local found = data and data.kind == "table" and rawget_(vm, value, k)
    if data and data.kind == "table" and (found ~= nil or not meta(vm, value, write and "__newindex" or "__index")) then
      if write then rawset_(vm, value, k, assigned); return deliver(vm, co, continuation, tuple()) end
      return deliver(vm, co, continuation, tuple(found))
    end
    local method = meta(vm, value, write and "__newindex" or "__index")
    if not method then error("attempt to index a " .. type(value) .. " value", 0) end
    local method_data = type(method) == "table" and object(vm, method)
    if method_data and method_data.kind == "table" then value = method
    else return call(vm, co, method, write and tuple(value, k, assigned) or tuple(value, k), continuation) end
  end
  error("metatable index chain too long", 0)
end
local function next_(vm, tab, previous)
  local data = object(vm, tab, "table")
  spend_table_work(1)
  local start = 0
  if previous ~= nil then
    local encoded = key(previous)
    start = data.known[encoded]
    if not start then error("invalid key to next", 0) end
    if start == true then
      -- Older graphs store membership booleans. Upgrade private metadata only
      -- at synchronized execution, never on_load; deleted keys retain positions.
      spend_table_work(2 * #data.order)
      for i, candidate in ipairs(data.order) do data.known[candidate] = i end
      start = data.known[encoded]
    end
  end
  for i = start + 1, #data.order do
    spend_table_work(1)
    local record = data.entries[data.order[i]]
    if record then return tuple(record.key, record.value) end
  end
  return tuple(nil)
end
local function length(vm, value)
  if type(value) == "string" then return #value end
  local data = object(vm, value, "table")
  spend_table_work(1)
  if data.sequence_length ~= nil then return data.sequence_length end
  local n = 0
  while rawget_(vm, value, n + 1) ~= nil do n = n + 1 end
  data.sequence_length = n
  return n
end
local native = {}
for name, handler in pairs(Terminal.methods) do
  native["term." .. name] = function(vm, _, args)
    spend_terminal_work(Terminal.work(vm.display, name, args))
    return tuple(handler(vm.display, table.unpack(args, 1, args.n)))
  end
end
local function native_(vm, name) return allocate(vm, {kind = "native", name = name}) end
local function file_args(vm, args, service)
  local handle = object(vm, service.handle, "handle")
  if args.n > 0 and equal(args[1], service.receiver) then
    spend_continuation_work(args.n)
    local shifted = {n = args.n - 1}
    for i = 1, shifted.n do shifted[i] = args[i + 1] end
    args = shifted
  end
  return handle, args
end
local file_methods = {"read", "readAll", "readLine", "write", "writeLine", "seek", "flush", "close", "lines"}
local function file_handle(vm, record, io_mode)
  local handle, tab = allocate(vm, record), table_(vm)
  object(vm, tab).file_handle = handle
  for _, method in ipairs(file_methods) do
    rawset_(vm, tab, method, allocate(vm, {kind = "native", name = "@file." .. method, handle = handle, receiver = tab, io_mode = io_mode}))
  end
  return tab
end
local function open_file(vm, args, io_mode)
  local ok, record = pcall(Files.open, vm, args[1], args[2], spend_filesystem_work)
  if not ok then return tuple(nil, tostring(record)) end
  local admitted, handle = pcall(file_handle, vm, record, io_mode)
  if not admitted then
    vm.open_handles = vm.open_handles - 1
    vm.handle_bytes = vm.handle_bytes - #record.text
    record.closed, record.text = true, ""
    return tuple(nil, tostring(handle))
  end
  return tuple(handle)
end
native["fs.open"] = function(vm, _, args) return open_file(vm, args, false) end
native["io.open"] = function(vm, _, args) return open_file(vm, args, true) end
for name, method in pairs({exists = Files.exists, isDir = Files.is_dir, isReadOnly = Files.is_readonly, getSize = Files.size, makeDir = Files.mkdir, delete = Files.delete}) do
  native["fs." .. name] = function(vm, _, args) return tuple(method(vm, args[1], spend_filesystem_work)) end
end
native["fs.list"] = function(vm, _, args)
  local names = Files.list(vm, args[1], spend_filesystem_work)
  spend_filesystem_work(#names)
  local tab = table_(vm)
  for i, name in ipairs(names) do rawset_(vm, tab, i, name) end
  return tuple(tab)
end
native["fs.copy"] = function(vm, _, args) Files.transfer(vm, args[1], args[2], false, spend_filesystem_work); return tuple() end
native["fs.move"] = function(vm, _, args) Files.transfer(vm, args[1], args[2], true, spend_filesystem_work); return tuple() end
native["fs.combine"] = function(vm, _, args)
  local segments = {}
  spend_filesystem_work(1)
  for i = 1, args.n do
    assert(type(args[i]) == "string", "path segments must be strings")
    spend_filesystem_work(1 + 16 * (#args[i] + 1))
    segments[i] = args[i]
  end
  return tuple(Filesystem.path({cwd = "/"}, "/" .. table.concat(segments, "/")):sub(2))
end
local function metadata_path(vm, name)
  assert(type(name) == "string" and #name <= 1024, "invalid path")
  spend_filesystem_work(1 + 16 * (#name + #vm.disk.cwd + 1))
  return Filesystem.path(vm.disk, name)
end
native["fs.getName"] = function(vm, _, args) return tuple(metadata_path(vm, args[1]):match("[^/]+$") or "") end
native["fs.getDir"] = function(vm, _, args)
  local directory = (metadata_path(vm, args[1]):match("^(.*)/[^/]+$") or ""):gsub("^/", "")
  return tuple(directory)
end
native["fs.getFreeSpace"] = function(vm)
  spend_filesystem_work(1)
  local bytes = 0
  for _, node in pairs(vm.disk.fs) do spend_filesystem_work(1); if node.type == "file" then bytes = bytes + #node.text end end
  return tuple(Filesystem.max_bytes - bytes)
end
native["@file.read"] = function(vm, _, args, _, service)
  local handle; handle, args = file_args(vm, args, service)
  if not service.io_mode then
    local result = Files.read(handle, args[1] == nil and 1 or args[1], spend_filesystem_work)
    if handle.binary and args[1] == nil and result then result = string.byte(result) end
    return tuple(result)
  end
  local result = {n = math.max(1, args.n)}
  for i = 1, result.n do result[i] = Files.read(handle, args[i], spend_filesystem_work) end
  return result
end
native["@file.readAll"] = function(vm, _, args, _, service)
  local handle = file_args(vm, args, service)
  return tuple(Files.read(handle, "a", spend_filesystem_work))
end
native["@file.readLine"] = function(vm, _, args, _, service)
  local handle; handle, args = file_args(vm, args, service)
  return tuple(Files.read(handle, args[1] and "L" or "l", spend_filesystem_work))
end
native["@file.write"] = function(vm, _, args, _, service)
  local handle; handle, args = file_args(vm, args, service)
  spend_filesystem_work(1)
  for i = 1, args.n do
    local text = args[i]
    spend_filesystem_work(1)
    if type(text) == "number" then
      if handle.binary and not service.io_mode then
        assert(text == math.floor(text) and text >= 0 and text <= 255, "invalid byte")
        text = string.char(text)
      else text = tostring(text) end
    end
    Files.write(vm, handle, text, spend_filesystem_work)
  end
  return service.io_mode and tuple(service.receiver) or tuple()
end
native["@file.writeLine"] = function(vm, _, args, _, service)
  local handle; handle, args = file_args(vm, args, service)
  spend_filesystem_work(1)
  local text = args[1] or ""
  if type(text) == "number" then text = tostring(text) end
  assert(type(text) == "string", "expected line string")
  spend_filesystem_work(1 + #text)
  Files.write(vm, handle, text .. "\n", spend_filesystem_work)
  return tuple()
end
native["@file.seek"] = function(vm, _, args, _, service)
  local handle; handle, args = file_args(vm, args, service)
  return tuple(Files.seek(handle, args[1], args[2], spend_filesystem_work))
end
native["@file.flush"] = function(vm, _, args, _, service)
  local handle = file_args(vm, args, service)
  Files.flush(vm, handle, spend_filesystem_work)
  return tuple(service.receiver)
end
native["@file.close"] = function(vm, _, args, _, service)
  local handle = file_args(vm, args, service)
  Files.close(vm, handle, spend_filesystem_work)
  return tuple(true)
end
native["@file.lines"] = function(vm, _, args, _, service)
  local _, formats = file_args(vm, args, service)
  spend_filesystem_work(1 + formats.n)
  return tuple(allocate(vm, {kind = "native", name = "@file.iterator", handle = service.handle, receiver = service.receiver, formats = formats}))
end
native["@file.iterator"] = function(vm, _, _, _, service)
  local handle = object(vm, service.handle, "handle")
  local formats = service.formats
  local result = {n = math.max(1, formats.n)}
  for i = 1, result.n do result[i] = Files.read(handle, formats[i], spend_filesystem_work) end
  if result[1] == nil and service.auto_close then Files.close(vm, handle, spend_filesystem_work) end
  return result
end
native["io.lines"] = function(vm, _, args)
  spend_filesystem_work(1 + args.n)
  local opened = open_file(vm, tuple(args[1], "r"), true)
  if not opened[1] then error(opened[2], 0) end
  local formats = {n = args.n - 1}
  for i = 1, formats.n do formats[i] = args[i + 1] end
  return tuple(allocate(vm, {kind = "native", name = "@file.iterator", handle = object(vm, opened[1]).file_handle, formats = formats, auto_close = true}))
end
native["io.type"] = function(vm, _, args)
  spend_filesystem_work(1)
  local data = type(args[1]) == "table" and object(vm, args[1])
  if not data or not data.file_handle then return tuple(nil) end
  return tuple(object(vm, data.file_handle, "handle").closed and "closed file" or "file")
end
local function loaded_closure(vm, source, name, mode, env)
  if mode ~= nil and (type(mode) ~= "string" or not mode:find("t", 1, true)) then return tuple(nil, "only source text loading is supported") end
  if type(source) ~= "string" then return tuple(nil, "source must be a string (reader functions are not supported)") end
  if #source > Limits.source_bytes then return tuple(nil, "source exceeds compile byte limit") end
  if env == nil then env = vm.env end
  object(vm, env, "table")
  local proto, err = Compiler.compile(source, name, nil, spend_compile_work)
  if not proto then return tuple(nil, err) end
  local environment = allocate(vm, {kind = "cell", value = env})
  return tuple(allocate(vm, {kind = "closure", proto = proto, upvals = {environment.ref}}))
end
local function guest_type(vm, value)
  if type(value) ~= "table" then return type(value) end
  local kind = object(vm, value).kind
  return (kind == "native" or kind == "closure") and "function" or (kind == "coroutine" and "thread" or kind)
end
native.type = function(vm, _, args) return tuple(guest_type(vm, args[1])) end
native.assert = function(_, _, args)
  if not truth(args[1]) then error({guest_error = true, value = args[2] or "assertion failed!"}, 0) end
  return args
end
native.error = function(_, _, args) error({guest_error = true, value = args[1]}, 0) end
native.rawequal = function(_, _, args) return tuple(equal(args[1], args[2])) end
native.rawget = function(vm, _, args) return tuple(rawget_(vm, args[1], args[2])) end
native.rawset = function(vm, _, args) rawset_(vm, args[1], args[2], args[3]); return tuple(args[1]) end
native.rawlen = function(vm, _, args) return tuple(length(vm, args[1])) end
native.next = function(vm, _, args) return next_(vm, args[1], args[2]) end
native.pairs = function(vm, co, args, cont)
  local method = meta(vm, args[1], "__pairs")
  if method then call(vm, co, method, tuple(args[1]), cont); return nil end
  object(vm, args[1], "table")
  return tuple(rawget_(vm, vm.env, "next"), args[1], nil)
end
native.ipairs_next = function(vm, _, args)
  local i = args[2] + 1
  local value = rawget_(vm, args[1], i)
  if value == nil then return tuple(nil) end
  return tuple(i, value)
end
native.ipairs = function(vm, co, args, cont)
  local method = meta(vm, args[1], "__ipairs")
  if method then call(vm, co, method, tuple(args[1]), cont); return nil end
  object(vm, args[1], "table")
  return tuple(vm.ipairs_next, args[1], 0)
end
native.setmetatable = function(vm, _, args)
  local data = object(vm, args[1], "table")
  if meta(vm, args[1], "__metatable") ~= nil then error("cannot change a protected metatable", 0) end
  if args[2] ~= nil then object(vm, args[2], "table") end
  data.meta = args[2]
  return tuple(args[1])
end
native.getmetatable = function(vm, _, args)
  local data = type(args[1]) == "table" and object(vm, args[1])
  local mt = data and data.meta or (type(args[1]) == "string" and vm.string_meta)
  if not mt then return tuple(nil) end
  local protected = rawget_(vm, mt, "__metatable")
  if protected ~= nil then return tuple(protected) end
  return tuple(mt)
end
native.select = function(_, _, args)
  if args[1] == "#" then return tuple(args.n - 1) end
  local i = number_(args[1])
  if not i or i ~= math.floor(i) or i == 0 or i < -(args.n - 1) then error("index out of range", 0) end
  if i < 0 then i = args.n + i end
  local result = {n = math.max(0, args.n - i)}
  for j = 1, result.n do result[j] = args[i + j] end
  return result
end
native.tonumber = function(_, _, args)
  if type(args[1]) == "table" then return tuple(nil) end
  return tuple(number_(args[1], args[2]))
end
native.load = function(vm, _, args) return loaded_closure(vm, args[1], args[2], args[3], args[4]) end
native.loadfile = function(vm, _, args)
  local ok, source = pcall(Files.read_source, vm, args[1], spend_filesystem_work)
  if not ok then return tuple(nil, tostring(source)) end
  return loaded_closure(vm, source, "=" .. args[1], args[2], args[3])
end
native.dofile = function(vm, co, args, cont)
  local result = native.loadfile(vm, co, args)
  if not result[1] then error(result[2], 0) end
  call(vm, co, result[1], tuple(), cont)
end
local function wait_event(vm, co, cont, filter, raw, timer, prepaid)
  if filter ~= nil and type(filter) ~= "string" then error("event filter must be a string", 0) end
  local event, err = Events.poll(vm.events, filter, raw, timer, not prepaid and spend_event_work or nil)
  if err then error(err, 0) end
  if event then return timer and tuple() or event end
  vm.wait = {co = {ref = vm.current}, continuation = cont, filter = filter, raw = raw, timer = timer}
  co.status = "waiting"
  vm.current = nil
end
native["os.pullEvent"] = function(vm, co, args, cont) return wait_event(vm, co, cont, args[1], false) end
native["os.pullEventRaw"] = function(vm, co, args, cont) return wait_event(vm, co, cont, args[1], true) end
native["os.queueEvent"] = function(vm, _, args)
  local ok, err = Events.admit(vm.events, args, vm.objects, false, spend_event_work)
  if not ok then error(err, 0) end
  return tuple()
end
native["os.startTimer"] = function(vm, _, args) return tuple(Events.start_timer(vm.events, args[1], spend_event_work)) end
native["os.cancelTimer"] = function(vm, _, args)
  if type(args[1]) ~= "number" then error("timer id must be a number", 0) end
  Events.cancel_timer(vm.events, args[1], spend_event_work)
  return tuple()
end
native["os.clock"] = function(vm) spend_event_work(1); return tuple(vm.events.tick / 60) end
native["os.sleep"] = function(vm, co, args, cont)
  -- Reserve timer creation and the initial poll together, before retaining a timer.
  spend_event_work(1 + Events.poll_work(vm.events, "timer"))
  local id = Events.start_timer(vm.events, args[1] == nil and 0 or args[1])
  return wait_event(vm, co, cont, "timer", false, id, true)
end
native.sleep = native["os.sleep"]
native.tostring = function(vm, co, args, cont)
  local method = meta(vm, args[1], "__tostring")
  if method then call(vm, co, method, tuple(args[1]), {kind = "string_result", parent = cont}); return nil end
  if type(args[1]) == "table" then return tuple(guest_type(vm, args[1]) .. ":" .. args[1].ref) end
  return tuple(tostring(args[1]))
end
native.pcall = function(vm, co, args, cont)
  if #co.frames >= Limits.call_frames then error("guest call stack limit exceeded", 0) end
  local params = {n = math.max(0, args.n - 1)}
  spend_continuation_work(1 + params.n)
  for i = 1, params.n do params[i] = args[i + 1] end
  -- A boundary frame also protects errors raised before a callee frame exists.
  co.frames[#co.frames + 1] = {kind = "boundary", continuation = {kind = "protected", parent = cont}}
  call(vm, co, args[1], params, {kind = "return"})
end
native.xpcall = function(vm, co, args, cont)
  if #co.frames >= Limits.call_frames then error("guest call stack limit exceeded", 0) end
  local params = {n = math.max(0, args.n - 2)}
  spend_continuation_work(1 + params.n)
  for i = 1, params.n do params[i] = args[i + 2] end
  co.frames[#co.frames + 1] = {kind = "boundary", continuation = {kind = "protected", parent = cont, handler = args[2]}}
  call(vm, co, args[1], params, {kind = "return"})
end
native["table.pack"] = function(vm, _, args)
  local tab = table_(vm)
  for i = 1, args.n do rawset_(vm, tab, i, args[i]) end
  rawset_(vm, tab, "n", args.n)
  return tuple(tab)
end
native["table.unpack"] = function(vm, _, args)
  local first, last = args[2] or 1, args[3] or length(vm, args[1])
  if type(first) ~= "number" or type(last) ~= "number" or first ~= math.floor(first) or last ~= math.floor(last) or math.abs(first) == math.huge or math.abs(last) == math.huge or last - first >= Limits.tuple_values then error("unpack range out of bounds", 0) end
  local out = {n = math.max(0, last - first + 1)}
  for i = 1, out.n do out[i] = rawget_(vm, args[1], first + i - 1) end
  return out
end
native["coroutine.create"] = function(vm, _, args)
  if guest_type(vm, args[1]) ~= "function" then error("coroutine entry must be a function", 0) end
  return tuple(allocate(vm, {kind = "coroutine", entry = args[1], frames = {}, status = "suspended"}))
end
native["coroutine.status"] = function(vm, _, args)
  local status = object(vm, args[1], "coroutine").status
  return tuple(status == "waiting" and "suspended" or status)
end
native["coroutine.running"] = function(vm) return tuple({ref = vm.current}, vm.current == vm.main.ref) end
native["coroutine.yield"] = function(vm, co, args, cont)
  if not co.resumer and vm.event_loop then return wait_event(vm, co, cont, nil, true) end
  if not co.resumer then error("attempt to yield from outside a coroutine", 0) end
  local returned = prefixed(true, args)
  co.yield_continuation = cont
  co.awaiting_resume = true
  co.status = "suspended"
  local resumer = co.resumer
  co.resumer = nil
  co.resume_depth = nil
  local parent = vm.objects[resumer.id]
  parent.status = "running"
  vm.current = resumer.id
  deliver(vm, parent, resumer.continuation, returned)
end
native["coroutine.resume"] = function(vm, co, args, cont)
  local child = object(vm, args[1], "coroutine")
  if child.status ~= "suspended" then return tuple(false, "cannot resume " .. child.status .. " coroutine") end
  local depth = 1
  if co.resumer then
    if co.resume_depth then depth = co.resume_depth + 1
    else
      -- Reconstruct compatible older active chains only at synchronized resume.
      local ancestor = co
      while ancestor.resumer do
        depth = depth + 1
        if depth > Limits.coroutine_depth then break end
        ancestor = vm.objects[ancestor.resumer.id]
      end
    end
  end
  if depth > Limits.coroutine_depth then return tuple(false, "guest coroutine nesting limit exceeded") end
  local params = {n = args.n - 1}
  spend_continuation_work(1 + params.n)
  for i = 1, params.n do params[i] = args[i + 1] end
  local parent_id = vm.current
  child.resumer = {id = parent_id, continuation = cont}
  child.resume_depth = depth
  co.status = "normal"
  child.status = "running"
  vm.current = args[1].ref
  if child.awaiting_resume then
    local waiting = child.yield_continuation
    child.yield_continuation = nil
    child.awaiting_resume = nil
    deliver(vm, child, waiting, params)
  else call(vm, child, child.entry, params) end
end
-- These closures remain outside storage. Natives store only symbolic names.
for _, name in ipairs({"abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg", "exp", "floor", "fmod", "frexp", "ldexp", "log", "max", "min", "modf", "rad", "sin", "sinh", "sqrt", "tan", "tanh"}) do
  local fn = assert(math[name])
  native["math." .. name] = function(_, _, args)
    local work = 0
    for i = 1, args.n do
      if type(args[i]) == "table" then error("math operands must be scalar", 0) end
      work = work + numeric_string_work(args[i])
    end
    if work > 0 then spend_string_work(work) end
    return tuple(fn(table.unpack(args, 1, args.n)))
  end
end
for _, name in ipairs({"arshift", "band", "bnot", "bor", "btest", "bxor", "extract", "lrotate", "lshift", "replace", "rrotate", "rshift"}) do
  local fn = assert(bit32[name])
  native["bit32." .. name] = function(_, _, args)
    for i = 1, args.n do if type(args[i]) ~= "number" then error("bit32 operands must be numbers", 0) end end
    return tuple(fn(table.unpack(args, 1, args.n)))
  end
end
for _, name in ipairs({"len", "sub", "byte", "char", "lower", "upper", "reverse"}) do
  local fn = assert(string[name])
  native["string." .. name] = function(_, _, args)
    for i = 1, args.n do
      if type(args[i]) ~= "number" and type(args[i]) ~= "string" then error("string operands must be scalar", 0) end
      if type(args[i]) == "string" and #args[i] > 65536 then error("string operand exceeds byte limit", 0) end
    end
    local work = 1 + args.n
    local conversion_work = 0
    local first, last = args.n + 1, args.n
    if name == "char" then first = 1
    elseif name == "sub" or name == "byte" then first, last = 2, math.min(3, args.n) end
    for i = first, last do conversion_work = conversion_work + numeric_string_work(args[i]) end
    if conversion_work > 0 then spend_string_work(conversion_work) end
    if name == "lower" or name == "upper" or name == "reverse" then
      work = work + 2 * #tostring(args[1])
    elseif name == "char" then work = work + args.n
    elseif name == "sub" then
      local size = #tostring(args[1])
      local first, last = tonumber(args[2]), args[3] == nil and -1 or tonumber(args[3])
      -- Conservative slice size; let the host retain its own argument errors.
      if not first or not last or first ~= first or last ~= last or math.abs(first) == math.huge or math.abs(last) == math.huge then
        work = work + size
      else
        if first < 0 then first = size + first + 1 end
        if last < 0 then last = size + last + 1 end
        work = work + math.max(0, math.min(size, math.ceil(last)) - math.max(1, math.floor(first)) + 1)
      end
    end
    if name == "byte" then
      local size = type(args[1]) == "string" and #args[1] or #tostring(args[1])
      local first = args[2] == nil and 1 or tonumber(args[2])
      local last = args[3] == nil and first or tonumber(args[3])
      if not first or not last or first ~= first or last ~= last or math.abs(first) == math.huge or math.abs(last) == math.huge then
        work = work + size
      else
        first = first < 0 and size + first + 1 or first
        last = last < 0 and size + last + 1 or last
        if last - first > 1023 then error("string.byte result exceeds tuple limit", 0) end
        work = work + math.max(0, math.min(size, math.ceil(last)) - math.max(1, math.floor(first)) + 1)
      end
    end
    spend_string_work(work)
    return tuple(fn(table.unpack(args, 1, args.n)))
  end
end
native["string.format"] = function(_, _, args) return tuple(Format.format(args, spend_string_work)) end
native["string.rep"] = function(_, _, args)
  local count = args[2]
  if type(args[1]) ~= "string" or type(count) ~= "number" or count ~= count or math.abs(count) == math.huge or count ~= math.floor(count) or count > 65536 then error("invalid repetition", 0) end
  local separator = args[3] or ""
  if type(separator) ~= "string" then error("separator must be a string", 0) end
  local bytes = #args[1] * math.max(0, count) + #separator * math.max(0, count - 1)
  if bytes > 65536 then error("string result exceeds byte limit", 0) end
  spend_string_work(1 + bytes)
  return tuple(string.rep(args[1], count, separator))
end
native["table.concat"] = function(vm, _, args)
  local tab, separator = args[1], args[2] or ""
  local first, last = args[3] or 1, args[4] or length(vm, tab)
  if type(separator) ~= "string" or type(first) ~= "number" or type(last) ~= "number" or first ~= math.floor(first) or last ~= math.floor(last) or math.abs(first) == math.huge or math.abs(last) == math.huge or last - first >= Limits.table_keys then error("invalid concat range", 0) end
  local pieces, bytes = {}, 0
  for i = first, last do
    spend_string_work(1)
    local value = rawget_(vm, tab, i)
    if type(value) ~= "string" and type(value) ~= "number" then error("concat values must be strings or numbers", 0) end
    value = tostring(value)
    bytes = bytes + #value + (i == first and 0 or #separator)
    if bytes > 65536 then error("string result exceeds byte limit", 0) end
    spend_string_work(#value + (i == first and 0 or #separator))
    pieces[#pieces + 1] = value
  end
  spend_string_work(1 + bytes)
  return tuple(table.concat(pieces, separator))
end
native["debug.traceback"] = function(_, _, args)
  -- Never call the host debug library or expose its frames.
  if args[1] == nil then return tuple("guest traceback") end
  return tuple(args[1])
end
call = function(vm, co, fn, args, continuation)
  tuple_size(args.n, "guest argument tuple limit exceeded")
  if recovery_scope then
    -- A recovered result may resume a metamethod continuation as well as an
    -- explicit error handler. No guest-selected call inherits recovery credit.
    assert(not vm.pending_operation, "pending guest call operation already exists")
    vm.pending_operation = {kind = "call", co = {ref = vm.current}, a = fn,
      b = args, c = continuation, recovery = false}
    return
  end
  for _ = 1, 100 do
    local data = type(fn) == "table" and object(vm, fn)
    if data and data.kind == "closure" then
      if #co.frames >= Limits.call_frames then error("guest call stack limit exceeded", 0) end
      co.frames[#co.frames + 1] = frame_(vm, fn, args, continuation)
      return
    elseif data and data.kind == "native" then
      local handler = native[data.name]
      if not handler then error("unsupported guest service " .. data.name, 0) end
      local result = handler(vm, co, args, continuation, data)
      if result then deliver(vm, co, continuation, result) end
      return
    end
    local method = meta(vm, fn, "__call")
    if not method then error("attempt to call a " .. guest_type(vm, fn) .. " value", 0) end
    args = prefixed(fn, args)
    fn = method
  end
  error("metatable call chain too long", 0)
end
concatenate = function(vm, co, frame_index, a, index, first, accumulator)
  local frame = co.frames[frame_index]
  if index < first then put(vm, frame, a, accumulator); return end
  local value = get(vm, frame, index)
  if (type(accumulator) == "number" or type(accumulator) == "string") and (type(value) == "number" or type(value) == "string") then
    local left, right = tostring(value), tostring(accumulator)
    if #left + #right > Limits.string_bytes then error("guest string limit exceeded", 0) end
    spend_string_work(1 + #left + #right)
    return concatenate(vm, co, frame_index, a, index - 1, first, left .. right)
  end
  local method = meta(vm, value, "__concat") or meta(vm, accumulator, "__concat")
  if not method then error("attempt to concatenate unsupported values", 0) end
  call(vm, co, method, tuple(value, accumulator), {kind = "concat", frame = frame_index, a = a, index = index - 1, first = first})
end
local arithmetic = {
  add = function(a,b) return a+b end, sub = function(a,b) return a-b end,
  mul = function(a,b) return a*b end, div = function(a,b) return a/b end,
  mod = function(a,b) return a%b end, pow = function(a,b) return a^b end
}
local function step(vm, co)
  local frame = assert(co.frames[#co.frames], "missing guest frame")
  assert(frame.kind == "frame", "unresolved guest boundary")
  local proto = frame.proto
  local inst = assert(proto.instructions[frame.pc], "guest PC out of range")
  frame.pc = frame.pc + 1
  local op, a, b, c = inst.op, inst.a, inst.b, inst.c
  local closure = object(vm, frame.closure, "closure")
  if op == "move" then put(vm, frame, a, get(vm, frame, b))
  elseif op == "loadk" then put(vm, frame, a, proto.constants[inst.bx + 1].value)
  elseif op == "loadkx" then
    local extra = proto.instructions[frame.pc]; frame.pc = frame.pc + 1
    put(vm, frame, a, proto.constants[extra.ax + 1].value)
  elseif op == "loadbool" then put(vm, frame, a, b == true or b == 1); if c == true or c == 1 then frame.pc = frame.pc + 1 end
  elseif op == "loadnil" then for i = a, a + b do put(vm, frame, i, nil) end
  elseif op == "getupval" then put(vm, frame, a, vm.objects[closure.upvals[b + 1]].value)
  elseif op == "setupval" then vm.objects[closure.upvals[b + 1]].value = get(vm, frame, a)
  elseif op == "gettable" or op == "gettabup" or op == "self" then
    local tab = op == "gettabup" and vm.objects[closure.upvals[b + 1]].value or get(vm, frame, b)
    if op == "self" then put(vm, frame, a + 1, tab) end
    index_(vm, co, tab, rk(vm, frame, c), destination(co, a, 1))
  elseif op == "settable" or op == "settabup" then
    local tab = op == "settabup" and vm.objects[closure.upvals[a + 1]].value or get(vm, frame, a)
    index_(vm, co, tab, rk(vm, frame, b), {kind = "ignore"}, true, rk(vm, frame, c))
  elseif op == "newtable" then put(vm, frame, a, table_(vm))
  elseif arithmetic[op] then
    local left, right = rk(vm, frame, b), rk(vm, frame, c)
    local work = numeric_string_work(left) + numeric_string_work(right)
    if work > 0 then spend_string_work(work) end
    local ln, rn = tonumber(type(left) ~= "table" and left or nil), tonumber(type(right) ~= "table" and right or nil)
    if ln and rn then put(vm, frame, a, arithmetic[op](ln, rn))
    else
      local method = meta(vm, left, "__" .. op) or meta(vm, right, "__" .. op)
      if not method then error("invalid guest arithmetic operands", 0) end
      call(vm, co, method, tuple(left, right), destination(co, a, 1))
    end
  elseif op == "not" then put(vm, frame, a, not truth(rk(vm, frame, b)))
  elseif op == "unm" or op == "len" then
    local value = rk(vm, frame, b)
    local method = meta(vm, value, "__" .. op)
    local number = op == "unm" and (type(value) == "number" or type(value) == "string") and number_(value)
    if number then put(vm, frame, a, -number)
    elseif op == "len" and type(value) == "string" then put(vm, frame, a, #value)
    elseif method then call(vm, co, method, tuple(value, value), destination(co, a, 1))
    elseif op == "len" then put(vm, frame, a, length(vm, value))
    else error("invalid guest unary operand", 0) end
  elseif op == "concat" then concatenate(vm, co, #co.frames, a, c - 1, b, get(vm, frame, c))
  elseif op == "jmp" then
    if a > 0 then
      for i = a - 1, proto.max_stack_size - 1 do
        if frame.registers[i] and vm.objects[frame.registers[i]].captured ~= false then
          local value = get(vm, frame, i)
          frame.registers[i] = nil
          cell(vm, frame, i).value = value
        end
      end
    end
    frame.pc = frame.pc + inst.sbx
  elseif op == "eq" or op == "lt" or op == "le" then
    local left, right = rk(vm, frame, b), rk(vm, frame, c)
    local accept = a == true or a == 1
    local result, method, negate
    if op == "eq" then
      result = equal(left, right)
      if not result and type(left) == "table" and type(right) == "table" then
        local lm, rm = meta(vm, left, "__eq"), meta(vm, right, "__eq")
        if lm and rm and equal(lm, rm) then method = lm end
      end
    elseif type(left) == type(right) and (type(left) == "number" or type(left) == "string") then
      if type(left) == "string" then spend_string_work(1 + 2 * math.min(#left, #right)) end
      if op == "lt" then result = left < right else result = left <= right end
    else
      method = meta(vm, left, "__" .. op) or meta(vm, right, "__" .. op)
      if op == "le" and not method then
        method = meta(vm, right, "__lt") or meta(vm, left, "__lt")
        left, right, negate = right, left, true
      end
      if not method then error("invalid guest comparison", 0) end
    end
    if method then call(vm, co, method, tuple(left, right), {kind = "compare", frame = #co.frames, accept = accept, negate = negate})
    elseif result ~= accept then frame.pc = frame.pc + 1 end
  elseif op == "test" or op == "testset" then
    local result = truth(get(vm, frame, op == "test" and a or b))
    if result == (c == true or c == 1) then
      if op == "testset" then put(vm, frame, a, get(vm, frame, b)) end
    else frame.pc = frame.pc + 1 end
  elseif op == "call" or op == "tailcall" then
    local count = b == 0 and frame.top - a - 1 or b - 1
    local args = values(vm, frame, a + 1, count)
    local fn = get(vm, frame, a)
    if op == "tailcall" then
      table.remove(co.frames)
      release_frame(vm, frame)
      call(vm, co, fn, args, frame.continuation)
    else call(vm, co, fn, args, destination(co, a, c == 0 and -1 or c - 1)) end
  elseif op == "return" then
    local result = values(vm, frame, a, b == 0 and frame.top - a or b - 1)
    table.remove(co.frames)
    release_frame(vm, frame)
    deliver(vm, co, frame.continuation, result)
  elseif op == "forprep" then
    local work = 0
    for i = a, a + 2 do work = work + numeric_string_work(get(vm, frame, i)) end
    if work > 0 then spend_string_work(work) end
    for i = a, a + 2 do
      local value = get(vm, frame, i)
      local number = type(value) ~= "table" and tonumber(value)
      if not number then error("invalid numeric for operand", 0) end
      put(vm, frame, i, number)
    end
    put(vm, frame, a, get(vm, frame, a) - get(vm, frame, a + 2)); frame.pc = frame.pc + inst.sbx
  elseif op == "forloop" then
    local increment = get(vm, frame, a + 2)
    local value = get(vm, frame, a) + increment
    put(vm, frame, a, value)
    if (increment > 0 and value <= get(vm, frame, a + 1)) or (increment <= 0 and value >= get(vm, frame, a + 1)) then
      put(vm, frame, a + 3, value); frame.pc = frame.pc + inst.sbx
    end
  elseif op == "tforcall" then call(vm, co, get(vm, frame, a), values(vm, frame, a + 1, 2), destination(co, a + 3, c))
  elseif op == "tforloop" then
    if get(vm, frame, a + 1) ~= nil then put(vm, frame, a, get(vm, frame, a + 1)); frame.pc = frame.pc + inst.sbx end
  elseif op == "setlist" then
    if c == 0 then c = proto.instructions[frame.pc].ax; frame.pc = frame.pc + 1 end
    local count = b == 0 and frame.top - a - 1 or b
    for i = 1, count do rawset_(vm, get(vm, frame, a), (c - 1) * 50 + i, get(vm, frame, a + i)) end
  elseif op == "closure" then
    local child = proto.inner_functions[inst.bx + 1]
    local upvals = {}
    for i, upvalue in ipairs(child.upvals) do
      if upvalue.in_stack then
        cell(vm, frame, upvalue.local_idx).captured = true
        upvals[i] = frame.registers[upvalue.local_idx]
      else upvals[i] = closure.upvals[upvalue.upval_idx + 1] end
    end
    put(vm, frame, a, allocate(vm, {kind = "closure", proto = child, upvals = upvals}))
  elseif op == "vararg" then
    local count = b == 0 and frame.varargs.n or b - 1
    spend_continuation_work(1 + 3 * count)
    for i = 1, count do put(vm, frame, a + i - 1, frame.varargs[i]) end
    if b == 0 then frame.top = a + count end
  else error("unsupported guest opcode " .. tostring(op), 0) end
end
local cleanup_failure
cleanup_failure = function(vm, co, state)
  while true do
    if state.phase == "scan" then
      if state.scan == 0 then
        state.phase, state.target, state.slot = "release", 1, 0
      else
        if not spend_cleanup_work(vm, 1) then break end
        local boundary = co.frames[state.scan].continuation
        if boundary and (boundary.kind == "protected" or boundary.kind == "error_handler") then
          state.boundary, state.target, state.phase, state.slot = boundary, state.scan, "release", 0
        else state.scan = state.scan - 1 end
      end
    elseif state.phase == "release" then
      if #co.frames < state.target then state.phase = "publish"
      else
        local frame = co.frames[#co.frames]
        local limit = frame.registers and (frame.register_limit or frame.proto.max_stack_size) or 0
        vm.free_cells = vm.free_cells or {}
        if state.slot < limit and #vm.free_cells < Limits.register_pool then
          -- Reserve lookup plus possible value clearing/pool append/register
          -- removal before touching a slot, including captured/absent cells.
          if not spend_cleanup_work(vm, 4) then break end
          local id = frame.registers[state.slot]
          local data = id and vm.objects[id]
          if data and data.captured == false then
            data.value = nil
            vm.free_cells[#vm.free_cells + 1] = id
            frame.registers[state.slot] = nil
          end
          state.slot = state.slot + 1
        else
          if not spend_cleanup_work(vm, 1) then break end
          co.frames[#co.frames], state.slot = nil, 0
        end
      end
    else
      assert(state.phase == "publish", "invalid cleanup phase")
      if not spend_cleanup_work(vm, 1) then break end
      local boundary = state.boundary
      if not boundary then finish(vm, co, tuple(), state.value, true)
      elseif boundary.kind == "error_handler" then deliver(vm, co, boundary.parent, tuple(false, "error in error handling"))
      elseif boundary.handler then
        co.frames[#co.frames + 1] = {kind = "boundary", continuation = {kind = "error_handler", parent = boundary.parent}}
        call(vm, co, boundary.handler, tuple(state.value), {kind = "return"})
      else deliver(vm, co, boundary.parent, tuple(false, state.value)) end
      return
    end
  end
  assert(vm.current and vm.objects[vm.current] == co, "pending cleanup owner mismatch")
  assert(not vm.pending_operation, "pending cleanup operation already exists")
  vm.pending_operation = {kind = "failure_cleanup", co = {ref = vm.current}, a = state, recovery = true}
end
local function failure(vm, co, err)
  local value
  if type(err) == "table" and err.guest_error then value = err.value else value = tostring(err) end
  cleanup_failure(vm, co, {value = value, phase = "scan", scan = #co.frames})
end
-- Bound mutual host recursion while retaining ordinary shallow-call performance.
-- Operations deferred at the depth ceiling become plain-data roots, not closures.
local control_depth = 0
local control_operations = {}
local function controlled(kind, operation)
  local function handler(vm, co, a, b, c)
    if control_depth >= Limits.continuation_depth then
      assert(vm.current and vm.objects[vm.current] == co, "pending control owner mismatch")
      assert(not vm.pending_operation, "pending control operation already exists")
      vm.pending_operation = {kind = kind, co = {ref = vm.current}, a = a, b = b, c = c, recovery = recovery_scope}
      return
    end
    control_depth = control_depth + 1
    local ok, err = pcall(operation, vm, co, a, b, c)
    control_depth = control_depth - 1
    if not ok then error(err, 0) end
  end
  control_operations[kind] = handler
  return handler
end
call = controlled("call", call)
deliver = controlled("deliver", deliver)
finish = controlled("finish", finish)
failure = controlled("failure", failure)
cleanup_failure = controlled("failure_cleanup", cleanup_failure)
local function pending_step(vm)
  local record = vm.pending_operation
  assert(record.co.ref == vm.current, "pending control owner mismatch")
  vm.pending_operation = nil
  local co = object(vm, record.co, "coroutine")
  local previous = recovery_scope
  recovery_scope = record.recovery == true or record.kind == "failure"
  local ok, err = pcall(control_operations[record.kind], vm, co, record.a, record.b, record.c)
  recovery_scope = previous
  if not ok then error(err, 0) end
end
local function recover(vm, co, err)
  -- Recovery can itself exhaust the heap while delivering into a parent's
  -- registers. Do not make an unprotected second delivery. Retain that parent's
  -- error as data and unwind it under the next execution credit instead.
  local owner = vm.current and vm.objects[vm.current] or co
  local previous = recovery_scope
  recovery_scope = true
  local ok, secondary = pcall(failure, vm, owner, err)
  recovery_scope = previous
  if not ok then
    assert(vm.current and vm.objects[vm.current], "secondary recovery has no active owner")
    assert(not vm.pending_operation, "pending recovery operation already exists")
    vm.pending_operation = {kind = "failure", co = {ref = vm.current}, a = secondary, recovery = true}
  end
end

function M.new(proto, args, disk, dimensions, event_loop)
  assert(proto.version == M.VERSION, "incompatible guest prototype")
  if args then tuple_size(args.n, "guest argument tuple limit exceeded") end
  local vm = {version = M.VERSION, objects = {}, next_id = 1, instructions = 0,
    object_count = 0, allocations_since_collection = 0, open_handles = 0, handle_bytes = 0,
    disk = {cwd = "/", fs = {['/'] = {type = "dir"}}}}
  vm.display = dimensions and Terminal.new(dimensions.columns, dimensions.rows) or Terminal.configured()
  vm.configured_geometry = dimensions == nil
  vm.events = Events.new()
  vm.event_loop = event_loop == true
  if disk then
    local count, bytes = 0, 0
    for path, node in pairs(disk.fs) do
      assert(type(path) == "string" and type(node) == "table" and (node.type == "file" or node.type == "dir"), "invalid local disk node")
      local normalized = Filesystem.path(vm.disk, path)
      assert(normalized == path, "local disk paths must be canonical")
      if node.type == "file" then assert(type(node.text) == "string", "invalid local file content"); bytes = bytes + #node.text end
      count = count + 1
      assert(count <= Filesystem.max_nodes and bytes <= Filesystem.max_bytes, "local disk quota exceeded")
      vm.disk.fs[path] = {type = node.type, text = node.type == "file" and node.text or nil}
    end
  end
  vm.env = table_(vm)
  rawset_(vm, vm.env, "_G", vm.env)
  rawset_(vm, vm.env, "_VERSION", "Lua 5.2")
  rawset_(vm, vm.env, "_HOST", "Computer Core 2 guest")
  local names = {}
  for name in pairs(native) do names[#names + 1] = name end
  table.sort(names)
  local libraries = {}
  for _, name in ipairs(names) do
    if name == "ipairs_next" then vm.ipairs_next = native_(vm, name)
    elseif name:sub(1, 1) ~= "@" then
      local lib, member = name:match("^([^.]+)%.(.+)$")
      if lib then
        if not libraries[lib] then libraries[lib] = table_(vm); rawset_(vm, vm.env, lib, libraries[lib]) end
        rawset_(vm, libraries[lib], member, native_(vm, name))
      else rawset_(vm, vm.env, name, native_(vm, name)) end
    end
  end
  rawset_(vm, libraries.math, "pi", math.pi)
  rawset_(vm, libraries.math, "huge", math.huge)
  vm.string_meta = table_(vm)
  rawset_(vm, vm.string_meta, "__index", libraries.string)
  local env_cell = allocate(vm, {kind = "cell", value = vm.env})
  local entry = allocate(vm, {kind = "closure", proto = proto, upvals = {env_cell.ref}})
  vm.main = allocate(vm, {kind = "coroutine", entry = entry, status = "running", frames = {}})
  vm.current = vm.main.ref
  object(vm, vm.main).frames[1] = frame_(vm, entry, args or tuple())
  -- Trusted definitions still consume guest instruction quanta and persist as data.
  local initializer = allocate(vm, {kind = "closure", proto = stdlib_proto, upvals = {env_cell.ref}})
  object(vm, vm.main).frames[2] = frame_(vm, initializer, tuple(Limits.table_keys), {kind = "ignore"})
  return vm
end
function M.queue(vm, event, priority)
  -- Host ingress accepts scalars only; guest queueEvent admits its own references.
  M.reconcile_configured(vm)
  return Events.admit(vm.events, event, nil, priority)
end
function M.advance(vm, tick, spend)
  M.reconcile_configured(vm)
  Events.advance(vm.events, tick, spend)
end
function M.reconcile(vm, columns, rows)
  if not Terminal.reconcile(vm.display, columns, rows) then return false end
  assert(Events.admit(vm.events, tuple("term_resize"), nil, true))
  return true
end
function M.reconcile_configured(vm)
  -- Synchronized host boundaries only; never invoked by an on_load hook.
  -- Explicit standalone test grids remain detached from startup settings.
  -- Missing metadata in compatible older graphs defaults to startup binding.
  if vm.configured_geometry == false then return false end
  return M.reconcile(vm, Terminal.dimensions())
end
local function run(vm, budget)
  assert(vm.version == M.VERSION, "incompatible guest execution state")
  assert(not vm.collection, "guest must remain paused during collection")
  assert(type(budget) == "number" and budget >= 0 and budget <= 100000 and budget == math.floor(budget), "invalid guest instruction budget")
  M.reconcile_configured(vm)
  local used = 0
  if vm.wait and budget > 0 then
    local waiting = vm.wait
    local admitted, event, err = pcall(Events.poll, vm.events, waiting.filter, waiting.raw, waiting.timer, spend_event_work)
    if not admitted then err, event = event, nil end
    if event or err then
      -- Resuming a saved continuation is execution even when it finishes without
      -- reaching another bytecode instruction. Charge before any delivery.
      used = used + 1
      vm.instructions = vm.instructions + 1
      local co = object(vm, waiting.co, "coroutine")
      vm.wait, vm.current, co.status = nil, waiting.co.ref, "running"
      cleanup_remaining = Limits.cleanup_work_per_step
      local ok, failure_error = pcall(function()
        if err then error(err, 0) end
        deliver(vm, co, waiting.continuation, waiting.timer and tuple() or event)
      end)
      if not ok then
        recover(vm, co, failure_error)
      end
    end
  end
  while vm.current and used < budget do
    local co = vm.objects[vm.current]
    -- Deferred native propagation consumes the same durable execution credits
    -- as a bytecode step and always precedes access to a possibly empty frame.
    local ok, err
    cleanup_remaining = Limits.cleanup_work_per_step
    if vm.pending_operation then ok, err = pcall(pending_step, vm)
    else ok, err = pcall(step, vm, co) end
    used = used + 1
    vm.instructions = vm.instructions + 1
    if not ok then
      -- Native resume/yield and return delivery may switch ownership inside one
      -- instruction. Handle failure in the active coroutine, not its old caller.
      recover(vm, co, err)
    end
  end
  local main = object(vm, vm.main)
  return main.status, main.result, used, main.error
end
function M.run(vm, budget, context)
  context = context or {computer = {used = 0, limit = Limits.compiler_work_per_computer}}
  local function validate(counter, maximum)
    assert(type(counter) == "table" and type(counter.used) == "number" and type(counter.limit) == "number"
      and counter.used >= 0 and counter.used <= counter.limit and counter.used == math.floor(counter.used)
      and counter.limit >= 0 and counter.limit <= maximum and counter.limit == math.floor(counter.limit), "invalid compiler budget")
  end
  validate(context.computer, Limits.compiler_work_per_computer)
  if context.aggregate then validate(context.aggregate, Limits.compiler_work_per_tick) end
  context.string_computer = context.string_computer or {used = 0, limit = Limits.string_work_per_computer}
  validate(context.string_computer, Limits.string_work_per_computer)
  if context.string_aggregate then validate(context.string_aggregate, Limits.string_work_per_tick) end
  context.terminal_computer = context.terminal_computer or {used = 0, limit = Limits.terminal_work_per_computer}
  validate(context.terminal_computer, Limits.terminal_work_per_computer)
  if context.terminal_aggregate then validate(context.terminal_aggregate, Limits.terminal_work_per_tick) end
  context.filesystem_computer = context.filesystem_computer or {used = 0, limit = Limits.filesystem_work_per_computer}
  validate(context.filesystem_computer, Limits.filesystem_work_per_computer)
  if context.filesystem_aggregate then validate(context.filesystem_aggregate, Limits.filesystem_work_per_tick) end
  context.event_computer = context.event_computer or {used = 0, limit = Limits.event_work_per_computer}
  validate(context.event_computer, Limits.event_work_per_computer)
  if context.event_aggregate then validate(context.event_aggregate, Limits.event_work_per_tick) end
  context.table_computer = context.table_computer or {used = 0, limit = Limits.table_work_per_computer}
  validate(context.table_computer, Limits.table_work_per_computer)
  if context.table_aggregate then validate(context.table_aggregate, Limits.table_work_per_tick) end
  context.continuation_computer = context.continuation_computer or {used = 0, limit = Limits.continuation_work_per_computer}
  validate(context.continuation_computer, Limits.continuation_work_per_computer)
  if context.continuation_aggregate then validate(context.continuation_aggregate, Limits.continuation_work_per_tick) end
  local previous, previous_cleanup = active_budget, cleanup_remaining
  active_budget = context
  local result = table.pack(pcall(run, vm, budget))
  active_budget = previous
  cleanup_remaining = previous_cleanup
  if not result[1] then error(result[2], 0) end
  return table.unpack(result, 2, result.n)
end
return M
