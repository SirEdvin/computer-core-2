-- Synchronized-dispatch boundary. All durable admission precedes ephemeral
-- reconstruction, whether this peer has executable functions cached or not.
local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Codegen = require('__computer_core_2__.scripts.native.codegen')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
local cache = setmetatable({}, {__mode = 'k'})
local loads = 0
function M.clear_cache() cache = setmetatable({}, {__mode = 'k'}) end
function M.cache_stats() return {loads = loads} end
local function compatible_bundle(b)
  if type(b) ~= 'table' or b.version ~= Codegen.VERSION then return false, 'unsupported native bundle version' end
  if type(b.source_version) ~= 'table' or (b.source_version.compiler ~= 1 and b.source_version.compiler ~= Compiler.VERSION)
    or b.source_version.abi ~= b.version then return false, 'unsupported native source version' end
  if type(b.source) ~= 'string' or #b.source > Limits.source_bytes
    or type(b.generated) ~= 'string' or #b.generated > Codegen.OUTPUT_BYTES
    or type(b.name) ~= 'string' or #b.name > Limits.string_bytes
    or type(b.activation_work) ~= 'number' or b.activation_work ~= math.floor(b.activation_work)
    or b.activation_work < #b.source + #b.generated + #b.name
    or b.activation_work > Limits.compiler_work_per_computer then
    return false, 'invalid native retained bundle'
  end
  return true
end
local function compatible(machine)
  local valid, reason = Execution.compatible(machine)
  if not valid then return false, reason end
  return compatible_bundle(machine.bundle)
end
local function recovery(machine, message)
  machine.recovery = {message = message, previous_status = machine.status}
  machine.status = 'recovery'
  -- Leave frames, pending ownership, heap, files, handles and drafts intact.
  return machine.status, 0, 'recovery'
end
function M.activation_cost(bundle) return bundle.activation_work end
function M.compatible(machine) return compatible(machine) end
function M.run(machine, credits, admit, services)
  assert(type(credits) == 'number' and credits >= 0 and credits < math.huge
    and credits == math.floor(credits), 'invalid native dispatch credits')
  if credits == 0 or machine.status == 'recovery' then return machine.status, 0 end
  local ok, message = compatible(machine)
  if not ok then return recovery(machine, message) end
  if machine.collector or machine.objects >= machine.collect_at then
    -- Collection executes no generated blocks and needs no host compilation.
    return Execution.run(machine, machine.bundle, nil, credits, services)
  end
  if machine.status ~= 'running' then return machine.status, 0 end
  assert(type(admit) == 'function', 'native activation admission required')
  local activated, deferred = {}, false
  local function resolve(bundle)
    if activated[bundle] then return activated[bundle] end
    local valid, reason = compatible_bundle(bundle)
    if not valid then recovery(machine, reason); return nil end
    local cost = bundle.activation_work
    if not admit(cost) then deferred = true; return nil end
    machine.activation_work = (machine.activation_work or 0) + cost
    machine.activation_dispatches = (machine.activation_dispatches or 0) + 1
    local executable = cache[bundle]
    if not executable then
      local loaded
      loaded, executable = pcall(Execution.executable, bundle)
      if not loaded then
        recovery(machine, 'native reconstruction failed: ' .. tostring(executable):sub(1, 4096)); return nil
      end
      cache[bundle], loads = executable, loads + 1
    end
    activated[bundle] = executable
    return executable
  end
  local c = machine.heap[machine.active]
  local f = c.frames[#c.frames]
  local found, bundle = pcall(Execution.bundle_for, machine, f and f.bundle_id)
  if not found then return recovery(machine, 'native retained frame bundle missing') end
  local executable = resolve(bundle)
  if not executable then return machine.status, 0, deferred and 'activation-deferred' or 'recovery' end
  local status, spent = Execution.run(machine, bundle, executable, credits, services, resolve)
  return status, spent, deferred and 'activation-deferred' or nil
end
return M
