-- Source compilation only. Raw Phobos metadata never crosses into storage.
local parser = require("__computer_core_2__.vendor.phobos.parser")
local linker = require("__computer_core_2__.vendor.phobos.jump_linker")
local compiler = require("__computer_core_2__.vendor.phobos.compiler")
local util = require("__computer_core_2__.vendor.phobos.util")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {VERSION = 1}

local function normalize(proto, spend)
  spend()
  local result = {
    version = M.VERSION, source = proto.source, num_params = proto.num_params,
    is_vararg = proto.is_vararg, max_stack_size = proto.max_stack_size,
    instructions = {}, constants = {}, upvals = {}, inner_functions = {}
  }
  for i, instruction in ipairs(proto.instructions) do
    spend()
    result.instructions[i] = {
      op = instruction.op.name, a = instruction.a, b = instruction.b,
      c = instruction.c, bx = instruction.bx, sbx = instruction.sbx,
      ax = instruction.ax, line = instruction.line
    }
  end
  for i, constant in ipairs(proto.constants) do
    spend()
    local kind = type(constant.value)
    assert(kind == "nil" or kind == "number" or kind == "boolean" or kind == "string", "prototype constants must be scalar")
    result.constants[i] = {kind = constant.node_type, value = constant.value}
  end
  for i, upvalue in ipairs(proto.upvals) do
    spend()
    result.upvals[i] = {
      name = upvalue.name, in_stack = upvalue.in_stack,
      local_idx = upvalue.local_idx, upval_idx = upvalue.upval_idx
    }
  end
  for i, inner in ipairs(proto.inner_functions) do
    result.inner_functions[i] = normalize(inner, spend)
  end
  return result
end

-- Optional host-only metrics sink; keep success/failure return arity unchanged.
-- Optional shared work callback is scoped to this invocation, never stored.
function M.compile(source, name, metrics, spend)
  if type(source) ~= "string" then return nil, "source must be a string" end
  if #source > Limits.source_bytes then return nil, "source exceeds compile byte limit" end
  if source:byte(1) == 27 then return nil, "binary chunks are not supported" end
  if name ~= nil and type(name) ~= "string" then return nil, "chunk name must be a string" end
  if name and #name > Limits.string_bytes then return nil, "chunk name exceeds byte limit" end
  if metrics ~= nil and type(metrics) ~= "table" then return nil, "compile metrics must be a table" end
  if spend ~= nil and type(spend) ~= "function" then return nil, "compile work callback must be a function" end
  metrics = metrics or {}
  metrics.source_bytes, metrics.parse_work, metrics.link_work, metrics.generate_work, metrics.normalize_work, metrics.phase = #source, 0, 0, 0, 0, "parse"
  local function charge(field, limit, message)
    return function(amount)
      amount = amount or 1
      if amount > limit - metrics[field] then error(message, 0) end
      if spend then spend(amount) end
      metrics[field] = metrics[field] + amount
    end
  end
  local parse_work = charge("parse_work", Limits.compiler_parse_work, "source parse work limit exceeded")
  local link_work = charge("link_work", Limits.compiler_link_work, "jump linking work limit exceeded")
  local normalize_work = charge("normalize_work", Limits.compiler_normalize_work, "bytecode normalization work limit exceeded")
  local generate_work = charge("generate_work", Limits.compiler_generate_work, "bytecode generation work limit exceeded")
  local ok, result = pcall(function()
    parse_work(#source)
    local ast, errors = util.with_work(parse_work, parser, source, name or "=guest", {max_parse_depth = Limits.compiler_parse_depth})
    if #errors ~= 0 then error("source parse failed: " .. #errors .. " error(s)", 0) end
    metrics.phase = "link"
    errors = linker(ast, link_work)
    if #errors ~= 0 then error("source jump linking failed: " .. #errors .. " error(s)", 0) end
    metrics.phase = "compile"
    local context = {depth = 0, limit = Limits.compiler_generate_depth, message = "bytecode generation nesting limit exceeded"}
    local proto = util.with_work(generate_work, compiler, ast, {optimizations = {tail_calls = true}, codegen_context = context})
    metrics.phase = "normalize"
    return normalize(proto, normalize_work)
  end)
  if not ok then return nil, tostring(result) end
  metrics.phase = "complete"
  return result
end

return M
