local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local function finish(source, arguments, limit, aggregate)
  local vm = VM.new(assert(Compiler.compile(source, '=scalar-byte-work')), arguments)
  local credits = {computer = {used = 0, limit = Limits.compiler_work_per_computer}, string_computer = {used = 0, limit = limit}, string_aggregate = aggregate}
  for _ = 1, 30 do
    local status, result = VM.run(vm, 256, credits)
    if status == 'dead' then
      assert(not vm.objects[vm.main.ref].failed)
      return result, credits
    end
  end
  error('scalar byte-work fixture did not complete')
end
function M.initial(check)
  for _, expression in ipairs({'tonumber(text)', 'select(text, 7)', 'text + 1', 'text - 1', 'text * 2', 'text / 2', 'text % 5', 'text ^ 2', '-text', 'text == text', 'text < text', 'text <= text', 'rawequal(text, text)', 'math.abs(text)', 'math.max(text, 2)'}) do
    local result, credits = finish('local text=...; return pcall(function() return '..expression..' end)', table.pack('12'), 0)
    check('scalar byte work is admitted before '..expression, result[1] == false and result[2] == 'per-computer string work limit exceeded'
      and credits.string_computer.used == 0)
  end
  local result, credits = finish('local text=...; return pcall(function() local n; for i=text,text,text do n=i end; return n end)', table.pack('12'), 0)
  check('numeric for coerces only after byte admission', result[1] == false and result[2] == 'per-computer string work limit exceeded' and credits.string_computer.used == 0)
  local padded = string.rep(' ', Limits.string_bytes - 2)..'65'
  for _, expression in ipairs({"string.char(text)", "string.sub('abc', text)", "string.byte('abc', text)"}) do
    result, credits = finish('local text=...; return pcall(function() return '..expression..' end)', table.pack(padded), 4)
    check('string numeric argument reserves full conversion bytes: '..expression, result[1] == false
      and result[2] == 'per-computer string work limit exceeded' and credits.string_computer.used == 0)
  end
  local aggregate = {used = 0, limit = 6}
  result, credits = finish('local text=...; return pcall(function() return text == text end)', table.pack('abc'), 7, aggregate)
  check('comparison aggregate refusal preserves both counters', result[1] == false and result[2] == 'aggregate string work limit exceeded'
    and credits.string_computer.used == 0 and aggregate.used == 0)
  aggregate = {used = 0, limit = 7}
  result, credits = finish('local text=...; return pcall(function() return text == text end)', table.pack('abc'), 7, aggregate)
  check('comparison charges a bounded pair of byte scans', result[1] == true and result[2] == true
    and credits.string_computer.used == 7 and aggregate.used == 7)
  result, credits = finish('local a,b=...; return a == b', table.pack('abc', 'abcd'), 0)
  check('different-length string equality needs no byte scan', result[1] == false and credits.string_computer.used == 0)
  result, credits = finish('local n=...; return n+2,-n,n==12,n<13,tonumber(n),select(1,n),math.abs(n)', table.pack(12), 0)
  check('numeric-only operations do not consume byte credits', result.n == 7 and result[1] == 14 and result[2] == -12
    and result[3] == true and result[4] == true and result[5] == 12 and result[6] == 12 and result[7] == 12 and credits.string_computer.used == 0)
  result, credits = finish('local a,b=...; return pcall(function() return a+b end)', table.pack('12','34'), 5)
  check('two arithmetic coercions reserve together', result[1] == false and result[2] == 'per-computer string work limit exceeded'
    and credits.string_computer.used == 0)
  result, credits = finish('local text=...; return tonumber(text,16),-text', table.pack('12'), 6)
  check('admitted conversion and unary coercion preserve results', result[1] == 18 and result[2] == -12 and credits.string_computer.used == 6)
  result, credits = finish('local text=...; local n; for i=text,text,text do n=i end; return n', table.pack('12'), 9)
  check('numeric for reserves all three conversions once', result[1] == 12 and credits.string_computer.used == 9)
  result, credits = finish("return string.sub('abcd','2','3'),string.byte('abcd','2','3')", nil, 20)
  check('admitted string indices preserve slice and byte tuples', result.n == 3 and result[1] == 'bc' and result[2] == 98
    and result[3] == 99 and credits.string_computer.used == 20)
  result, credits = finish('local text=...; return string.char(text)', table.pack(padded), Limits.string_bytes + 4)
  check('maximum numeric string argument is admitted within fresh credits', result[1] == 'A' and credits.string_computer.used == Limits.string_bytes + 4)
  aggregate = {used = 0, limit = 4}
  result, credits = finish("return pcall(string.sub,'abcd','2','3')", nil, 10, aggregate)
  check('admitted index conversion stays charged after result refusal', result[1] == false and result[2] == 'aggregate string work limit exceeded'
    and credits.string_computer.used == 4 and aggregate.used == 4)
  aggregate = {used = 0, limit = 5}
  result, credits = finish('local a,b=...; return a<b', table.pack('ab','abcd'), 5, aggregate)
  check('unequal-length ordering reserves the shorter pair scan', result[1] == true and credits.string_computer.used == 5 and aggregate.used == 5)
  aggregate = {used = 0, limit = 5}
  result, credits = finish('local a,b=...; return pcall(function() return a+b end)', table.pack('12','34'), 6, aggregate)
  check('arithmetic aggregate refusal preserves paired counters', result[1] == false and result[2] == 'aggregate string work limit exceeded'
    and credits.string_computer.used == 0 and aggregate.used == 0)
  aggregate = {used = 0, limit = 8}
  result, credits = finish('local text=...; return pcall(function() for i=text,text,text do end end)', table.pack('12'), 9, aggregate)
  check('numeric-for aggregate refusal preserves triple counters', result[1] == false and result[2] == 'aggregate string work limit exceeded'
    and credits.string_computer.used == 0 and aggregate.used == 0)
end
return M
