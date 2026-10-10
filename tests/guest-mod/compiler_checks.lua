local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local util = require("__computer_core_2__.vendor.phobos.util")

return function(check)
  local names = {}
  for i = 1, 200 do names[#names + 1] = 'local v' .. i .. '=0;' end
  names[#names + 1] = string.rep('missing=missing+1;', 1000)
  local parsing = {}
  local parsed, parse_error = Compiler.compile(table.concat(names), '=parse-work-check', parsing)
  check('name resolution stops at its exact parser work quota', not parsed and parse_error == 'source parse work limit exceeded' and parsing.phase == 'parse' and parsing.parse_work == Limits.compiler_parse_work and parsing.link_work == 0 and parsing.normalize_work == 0)
  local padding = string.rep('=', 3000)
  local delimiter = {}
  parsed, parse_error = Compiler.compile('return [' .. padding .. '[' .. string.rep(']', 1000) .. ']' .. padding .. ']', '=delimiter-work-check', delimiter)
  check('variable-width delimiter comparisons are charged before matching', not parsed and parse_error == 'source parse work limit exceeded' and delimiter.phase == 'parse' and delimiter.parse_work <= Limits.compiler_parse_work and delimiter.parse_work > 0 and delimiter.link_work == 0 and delimiter.normalize_work == 0)
  local outer_work, inner_work = 0, 0
  local nesting = {}
  parsed, parse_error = Compiler.compile('return ' .. string.rep('(', Limits.compiler_parse_depth + 1) .. '1' .. string.rep(')', Limits.compiler_parse_depth + 1), '=nesting-work-check', nesting)
  check('recursive expressions stop at a controlled parser depth', not parsed and parse_error == 'source parse nesting limit exceeded' and nesting.phase == 'parse' and nesting.parse_work <= Limits.compiler_parse_work and nesting.link_work == 0)
  parsed, parse_error = Compiler.compile(string.rep('do ', Limits.compiler_parse_depth + 1) .. string.rep('end ', Limits.compiler_parse_depth + 1), '=block-depth-check', nesting)
  check('nested blocks share the same parser depth guard', not parsed and parse_error == 'source parse nesting limit exceeded' and nesting.phase == 'parse' and nesting.parse_work <= Limits.compiler_parse_work and nesting.link_work == 0)
  local scoped = table.pack(util.with_work(function(amount) outer_work = outer_work + amount end, function()
    util.spend_work(2)
    local ok, failure = pcall(util.with_work, function(amount) inner_work = inner_work + amount end, function()
      util.spend_work(3)
      error('inner work failure', 0)
    end)
    assert(not ok and failure == 'inner work failure')
    util.spend_work(5)
    return 'scope-pass', nil, 9
  end))
  check('nested work scopes restore callbacks and preserve nil tuples', outer_work == 2 + 5 and inner_work == 3 and scoped.n == 3 and scoped[1] == 'scope-pass' and scoped[2] == nil and scoped[3] == 9)
  util.spend_work(Limits.compiler_parse_work + 1)
  check('completed and failed parser contexts leave no active work callback', outer_work == 2 + 5 and inner_work == 3)
  local depth_context = {depth = 0, limit = 4, message = 'test generation depth exhausted'}
  local function enter_again() return util.with_depth(depth_context, enter_again) end
  local depth_ok, depth_failure = pcall(enter_again)
  local depth_tuple = table.pack(util.with_depth(depth_context, function() return 1, nil, 3 end))
  check('generation depth guards restore temporary counters and preserve nil tuples',
    not depth_ok and depth_failure == depth_context.message and depth_context.depth == 0
      and depth_tuple.n == 3 and depth_tuple[1] == 1 and depth_tuple[2] == nil and depth_tuple[3] == 3)

  local generation = {}
  local generated, generation_error = Compiler.compile(string.rep('do local x=1 end;', 1200), '=register-history-work', generation)
  check('raw compiler register-history scans stop at the exact generation quota',
    not generated and generation_error == 'bytecode generation work limit exceeded'
      and generation.generate_work == Limits.compiler_generate_work and generation.phase == 'compile' and generation.normalize_work == 0)
  util.spend_work(Limits.compiler_generate_work + 1)
  check('failed generation restores the previous work callback', outer_work == 2 + 5 and inner_work == 3)

  local nested_source = 'local function f()' .. string.rep('do local x=1 end;', 600) .. 'end;return f'
  local single_generation, nested_generation = {}, {}
  local single = Compiler.compile(nested_source, '=single-generation-work', single_generation)
  generated, generation_error = Compiler.compile(nested_source:gsub('end;return f$', 'end;') .. nested_source, '=shared-generation-work', nested_generation)
  check('nested prototypes share one generation quota instead of resetting it',
    single ~= nil and single_generation.generate_work < Limits.compiler_generate_work
      and not generated and generation_error == 'bytecode generation work limit exceeded'
      and nested_generation.generate_work == Limits.compiler_generate_work and nested_generation.phase == 'compile')

  local generation_depth = {}
  generated, generation_error = Compiler.compile('return ' .. string.rep('1+', 100) .. '1', '=left-associated-depth', generation_depth)
  local recovered_generation = Compiler.compile('return 9', '=generation-recovery')
  check('left-associated generation fails controllably and later compilation recovers',
    not generated and generation_error == 'bytecode generation nesting limit exceeded'
      and generation_depth.phase == 'compile' and recovered_generation ~= nil)
  local pieces = {}
  for i = 1, 320 do pieces[#pieces + 1] = 'goto label' .. i .. '\n' end
  for i = 1, 320 do pieces[#pieces + 1] = '::label' .. i .. '::\n' end
  local metrics = {}
  local proto, err = Compiler.compile(table.concat(pieces), '=link-work-check', metrics)
  check('quadratic jump linking stops at its exact work quota', not proto and err == 'jump linking work limit exceeded' and metrics.phase == 'link' and metrics.link_work == Limits.compiler_link_work and metrics.normalize_work == 0)
  local linking = metrics
  metrics = {}
  proto, err = Compiler.compile(string.rep('a=a+1;', 3500), '=normalize-work-check', metrics)
  check('normalization stops before allocating an excess record', not proto and err == 'bytecode normalization work limit exceeded' and metrics.phase == 'normalize' and metrics.normalize_work == Limits.compiler_normalize_work and metrics.link_work <= Limits.compiler_link_work)
  storage.compile_work = {parsing = parsing, delimiter = delimiter, linking = linking, normalization = metrics,
    generation = generation, generation_nested = nested_generation, generation_depth = generation_depth}
  metrics = {}
  local values = table.pack(Compiler.compile('local function f() return function() return 7 end end; return f()()', '=nested-work-check', metrics))
  local function records(value)
    local count = 1 + #value.instructions + #value.constants + #value.upvals
    for _, inner in ipairs(value.inner_functions) do count = count + records(inner) end
    return count
  end
  check('normalization shares one budget across nested prototypes', values[1] and metrics.phase == 'complete' and metrics.normalize_work == records(values[1]) and #values[1].inner_functions == 1)
  check('compiler recovery preserves the single success return contract', values.n == 1 and metrics.parse_work >= metrics.source_bytes and metrics.parse_work <= Limits.compiler_parse_work and metrics.link_work > 0 and metrics.link_work <= Limits.compiler_link_work and metrics.generate_work > 0 and metrics.generate_work <= Limits.compiler_generate_work)
  proto, err = Compiler.compile('do ::inside:: end; goto inside', '=invalid-jump-check')
  check('bounded linker retains ordinary jump validation', not proto and err:find('source jump linking failed:', 1, true))
  proto, err = Compiler.compile('return 1', string.rep('x', Limits.string_bytes + 1))
  check('compiler rejects oversized diagnostic names before parsing', not proto and err == 'chunk name exceeds byte limit')
  log('CC2 COMPILE WORK parse=' .. parsing.parse_work .. ' delimiter=' .. delimiter.parse_work .. ' link=' .. linking.link_work .. ' normalization=' .. storage.compile_work.normalization.normalize_work)
end
