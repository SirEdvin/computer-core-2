local pieces = {}
for i = 1, 320 do pieces[#pieces + 1] = 'goto label' .. i .. '\n' end
for i = 1, 320 do pieces[#pieces + 1] = '::label' .. i .. '::\n' end
local source = table.concat(pieces)
local linked, link_error = load(source, '=quadratic-jumps')
assert(linked == nil and link_error:find('jump linking work limit exceeded', 1, true), tostring(link_error))
local wide = string.rep('a=a+1;', 3500)
local normalized, normalization_error = load(wide, '=wide-bytecode')
assert(normalized == nil and normalization_error:find('bytecode normalization work limit exceeded', 1, true), tostring(normalization_error))
pieces = {}
for i = 1, 200 do pieces[#pieces + 1] = 'local v' .. i .. '=0;' end
pieces[#pieces + 1] = string.rep('missing=missing+1;', 1000)
local parsed, parse_error = load(table.concat(pieces), '=quadratic-name-resolution')
assert(parsed == nil and parse_error:find('source parse work limit exceeded', 1, true), tostring(parse_error))
local padding = string.rep('=', 3000)
local blocked, block_error = load('return [' .. padding .. '[' .. string.rep(']', 1000) .. ']' .. padding .. ']', '=long-delimiter-scans')
assert(blocked == nil and block_error:find('source parse work limit exceeded', 1, true), tostring(block_error))
local nested, nesting_error = load('return ' .. string.rep('(', 100) .. '1' .. string.rep(')', 100), '=deep-expression')
assert(nested == nil and nesting_error:find('source parse nesting limit exceeded', 1, true), tostring(nesting_error))
local valid = assert(load([[local n = 0
::again::
n = n + 1
if n < 3 then goto again end
return n]], '=compiler-recovery'))
assert(valid() == 3)
local generated, generation_error = load(string.rep('do local x=1 end;', 1200), '=quadratic-register-history')
assert(generated == nil and generation_error:find('bytecode generation work limit exceeded', 1, true), tostring(generation_error))
local deep_code, generation_depth_error = load('return ' .. string.rep('1+', 100) .. '1', '=left-associated-generation')
assert(deep_code == nil and generation_depth_error:find('bytecode generation nesting limit exceeded', 1, true), tostring(generation_depth_error))
assert(assert(load('return 9', '=post-generation-recovery'))() == 9)
return 'compiler-work-pass'
