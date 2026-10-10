-- Bounded native compiler front end. ASTs are ephemeral, never stored/executed.
local parser = require('__computer_core_2__.vendor.phobos.parser')
local linker = require('__computer_core_2__.vendor.phobos.jump_linker')
local util = require('__computer_core_2__.vendor.phobos.util')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local Codegen = require('__computer_core_2__.scripts.native.codegen')
local M = {VERSION = 2}

-- Success returns only the AST; failure returns nil and a bounded diagnostic.
-- The optional spend callback is host-only shared admission, never guest input.
function M.analyze(source, name, metrics, spend)
  if type(source) ~= 'string' then return nil, 'source must be a string' end
  if #source > Limits.source_bytes then return nil, 'source exceeds compile byte limit' end
  if source:byte(1) == 27 then return nil, 'binary chunks are not supported' end
  if name ~= nil and type(name) ~= 'string' then return nil, 'chunk name must be a string' end
  if name and #name > Limits.string_bytes then return nil, 'chunk name exceeds byte limit' end
  if metrics ~= nil and type(metrics) ~= 'table' then return nil, 'compile metrics must be a table' end
  if spend ~= nil and type(spend) ~= 'function' then return nil, 'compile work callback must be a function' end
  metrics = metrics or {}
  metrics.source_bytes, metrics.parse_work, metrics.link_work, metrics.phase = #source, 0, 0, 'parse'
  local function charge(field, limit, message)
    return function(amount)
      amount = amount or 1
      assert(type(amount) == 'number' and amount >= 0 and amount < math.huge
        and amount == math.floor(amount), 'invalid native compiler work charge')
      if amount > limit - metrics[field] then error(message, 0) end
      if spend then spend(amount) end
      metrics[field] = metrics[field] + amount
    end
  end
  local parse_work = charge('parse_work', Limits.compiler_parse_work, 'source parse work limit exceeded')
  local link_work = charge('link_work', Limits.compiler_link_work, 'jump linking work limit exceeded')
  local function diagnostic(errors, message)
    local position = errors[1].start_position or errors[1].position or {}
    return (name or '=native') .. ':' .. (position.line or 1) .. ':' .. (position.column or 1) .. ': ' .. message .. ': ' .. #errors .. ' error(s)'
  end
  local ok, result = pcall(function()
    parse_work(#source)
    local ast, errors = util.with_work(parse_work, parser, source, name or '=native',
      {max_parse_depth = Limits.compiler_parse_depth})
    if #errors > 0 then error(diagnostic(errors, 'source parse failed'), 0) end
    metrics.phase = 'link'
    errors = linker(ast, link_work)
    if #errors > 0 then error(diagnostic(errors, 'source jump linking failed'), 0) end
    return ast
  end)
  if not ok then return nil, tostring(result):sub(1, 4096) end
  metrics.phase = 'complete'
  return result
end

function M.compile(source, name, metrics, spend)
  metrics = metrics or {}
  local ast, err = M.analyze(source, name, metrics, spend)
  if not ast then return nil, err end
  local ok, bundle = pcall(Codegen.generate, ast, metrics, spend)
  if not ok then return nil, tostring(bundle):sub(1, 4096) end
  metrics.phase, metrics.snapshot_work = 'snapshot', 0
  ok, err = pcall(function()
    if spend then spend(#bundle.prototypes + 1) end
    metrics.snapshot_work = #bundle.prototypes + 1
    bundle.source = source
    -- The exact (name, source, compiler, ABI) tuple identifies an active version.
    -- Keep it with the generated text: disk edits cannot change a live snapshot.
    bundle.source_version = {compiler = M.VERSION, abi = bundle.version}
    bundle.activation_work = #source + #bundle.generated + #bundle.name + #bundle.prototypes
    for _, proto in ipairs(bundle.prototypes) do
      bundle.activation_work = bundle.activation_work + proto.blocks
    end
  end)
  if not ok then return nil, tostring(err):sub(1, 4096) end
  metrics.phase = 'complete'
  metrics.activation_work = bundle.activation_work
  return bundle
end

return M
