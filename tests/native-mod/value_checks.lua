local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local function handlers()
  return {
    kind = function(machine, values) return 'return', table.pack(Execution.type(machine, values[1])) end,
    pause = function(_, values) return 'yield', values end,
  }
end
local function run(source, services)
  local bundle = assert(Compiler.compile(source, '=native-values'))
  local machine = Execution.new(bundle)
  Execution.service(machine, 'kind')
  Execution.service(machine, 'pause')
  local status = Execution.run(machine, bundle, Execution.executable(bundle), 1000, services or handlers())
  return machine, status
end
return {
  run = function(check)
    local machine, status = run('local a={}; local b=a; a[a]=b; a[true]=1; a["b1"]=2; a[1]=3; a["1"]=4; return a==b,a[a]==a,a[true],a["b1"],a[1],a["1"],a[nil],a[0/0]')
    local r = machine.result
    check('native table alias cycle and key identities remain distinct', status == 'return' and r.n == 8 and r[1] and r[2]
      and r[3] == 1 and r[4] == 2 and r[5] == 3 and r[6] == 4 and r[7] == nil and r[8] == nil)
    machine, status = run('local f=function() end; local g=function() end; local t={[f]=7,[g]=8}; return f==f,f==g,t[f],t[g],kind(f),kind(t),kind(nil),kind(false),kind(2),kind("s")')
    r = machine.result
    check('native callable identity and guest type semantics', status == 'return' and r.n == 10 and r[1] and not r[2]
      and r[3] == 7 and r[4] == 8 and r[5] == 'function' and r[6] == 'table' and r[7] == 'nil'
      and r[8] == 'boolean' and r[9] == 'number' and r[10] == 'string')
    local bundle = assert(Compiler.compile('return 1', '=native-ingress'))
    check('native initial argument cannot persist host functions', not pcall(Execution.new, bundle, table.pack(function() end)))
    local m = Execution.new(bundle)
    check('native setters refuse host functions atomically', not pcall(Execution.set, m, m.env, 'bad', function() end)
      and Execution.get(m, m.env, 'bad') == nil)
    check('native setters refuse host metatables', not pcall(Execution.set, m, m.env, 'bad', setmetatable({}, {})))
    for name, value in pairs({func = function() end, raw = {game = game}, meta = setmetatable({native_ref = m.env.native_ref}, {})}) do
      machine, status = run('return pause()', {pause = function() return 'return', table.pack(value) end})
      check('native service result cannot retain host value ' .. name, status == 'error' and machine.error.message:find('forbidden', 1, true)
        or status == 'error' and machine.error.message:find('invalid native reference', 1, true))
    end
  end,
  suspend = function(check)
    local bundle = assert(Compiler.compile([[
local x=1
local a={}
local b=a
local f=function(v) x=x+v; return x,nil end
local g=function() return x end
local t={[f]=g,f=f,g=g,a=a,b=b}
a.self=a
local before=t.f(2)
pause(t,before,nil)
local after=t.f(4)
return before,after,t.g(),t[t.f]==t.g,t.a==t.b,t.a.self==t.a,kind(t.f),nil
]], '=native-value-reload'))
    local machine = Execution.new(bundle)
    Execution.service(machine, 'pause'); Execution.service(machine, 'kind')
    local status = Execution.run(machine, bundle, Execution.executable(bundle), 1000, handlers())
    check('native closure graph suspends with shared captured state', status == 'yield' and machine.yielded.n == 3
      and machine.yielded[2] == 3 and machine.yielded[3] == nil)
    return {machine = machine, bundle = bundle}
  end,
  reload = function(state, check)
    local machine = state.machine
    local t = machine.yielded[1]
    check('native aliases and cycles retained before reload execution', Execution.get(machine, t, 'a').native_ref == Execution.get(machine, t, 'b').native_ref
      and Execution.get(machine, Execution.get(machine, t, 'a'), 'self').native_ref == Execution.get(machine, t, 'a').native_ref)
    Execution.resume(machine, table.pack())
    local status = Execution.run(machine, state.bundle, Execution.executable(state.bundle), 1000, handlers())
    local r = machine.result
    check('native reloaded dynamic closures share captured cells and identities', status == 'return' and r.n == 8
      and r[1] == 3 and r[2] == 7 and r[3] == 7 and r[4] and r[5] and r[6] and r[7] == 'function' and r[8] == nil)
  end,
}
