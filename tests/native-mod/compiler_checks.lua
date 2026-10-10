-- Front-end fixtures run in the exact engine. AST results never enter storage.
local Frontend = require('__computer_core_2__.scripts.native.compiler')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local util = require('__computer_core_2__.vendor.phobos.util')
return function(check)
  local metrics = {}
  local ast, err = Frontend.analyze('local x = 1; ::again:: x=x+1; if x<3 then goto again end; return x', '=native-front', metrics)
  check('native frontend parses and links supported source', ast and not err and ast.node_type == 'functiondef')
  check('native frontend exposes bounded phase metrics', metrics.parse_work > 0 and metrics.link_work > 0 and metrics.phase == 'complete')
  check('native frontend is not a bytecode generator', ast.instructions == nil)
  check('native frontend rejects malformed syntax', Frontend.analyze('local =', '=bad') == nil)
  check('native frontend rejects invalid jump scope', Frontend.analyze('goto missing', '=bad-jump') == nil)
  check('native frontend rejects binary source', Frontend.analyze('\27Lua', '=binary') == nil)
  check('native frontend rejects oversized source', Frontend.analyze(string.rep(' ', Limits.source_bytes + 1), '=large') == nil)
  check('native frontend rejects oversized names', Frontend.analyze('return 1', string.rep('x', Limits.string_bytes + 1)) == nil)
  local deep = 'return ' .. string.rep('(', Limits.compiler_parse_depth + 1) .. '1' .. string.rep(')', Limits.compiler_parse_depth + 1)
  local result, failure = Frontend.analyze(deep, '=deep')
  check('native frontend bounds recursive parsing', result == nil and failure:find('nesting limit', 1, true))
  local pieces = {}
  for i = 1, 200 do pieces[#pieces + 1] = 'local v' .. i .. '=0;' end
  pieces[#pieces + 1] = string.rep('missing=missing+1;', 1000)
  metrics = {}
  result, failure = Frontend.analyze(table.concat(pieces), '=work', metrics)
  check('native frontend stops at exact parse work cap', result == nil
    and failure == 'source parse work limit exceeded' and metrics.parse_work == Limits.compiler_parse_work)
  pieces = {}
  for i = 1, 320 do pieces[#pieces + 1] = 'goto label' .. i .. '\n' end
  for i = 1, 320 do pieces[#pieces + 1] = '::label' .. i .. '::\n' end
  metrics = {}
  result, failure = Frontend.analyze(table.concat(pieces), '=link-work', metrics)
  check('native frontend stops at exact jump linking work cap', result == nil
    and failure == 'jump linking work limit exceeded' and metrics.link_work == Limits.compiler_link_work)
  -- Admission callbacks also bound shared work; refusal is not a syntax failure.
  local spent = 0
  result, failure = Frontend.analyze('local x=1; return x', '=refused', {}, function(amount)
    if amount > 8 - spent then error('fixture shared admission refused', 0) end
    spent = spent + amount
  end)
  check('native frontend charges shared work before proceeding', result == nil and failure:find('shared admission refused', 1, true) and spent <= 8)
  local restored = 0
  util.with_work(function(amount) restored = restored + amount end, function()
    Frontend.analyze(deep, '=nested-refused')
    util.spend_work(3)
  end)
  check('native frontend restores enclosing utility work scope', restored == 3)
  result = Frontend.analyze('return 42', '=recovery')
  check('native frontend recovers after work and depth refusal', result ~= nil)
end
