-- Trusted, authored compiler conformance cases. Reference host load is used
-- ONLY here for these fixed test strings, never for player or OS source.
local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local function equal(left, right)
  if left.n ~= right.n then return false end
  for i = 1, left.n do if left[i] ~= right[i] then return false end end
  return true
end
local cases = {
  {'scalar arithmetic', 'return 1+2*3,2^3,7%4,7/2,-2,not false,true==false,"a"<"b",#"tree"'},
  {'numeric coercion', 'return "2"+3,-"4",5*"6"'},
  {'nil tuple', 'return nil,1,nil,nil'},
  {'varargs', 'local a,b,c=...; return a,b,c,...', table.pack(4,nil,6,nil)},
  {'single vararg', 'return (...),7', table.pack(nil,3,nil)},
  {'local assignments', 'local x,y=2,5; x,y=y,x; return x,y'},
  {'multiple returns', 'local function f() return 1,nil,3,nil end; local a,b,c,d=f(); return a,b,c,d,f()'},
  {'parenthesized call', 'local function f() return 1,2,3 end; return (f()),f()'},
  {'empty returns', 'local function f() return end; return f()'},
  {'concat scalar calls', 'local function f() return 2,3,nil end; return "a"..f()'},
  {'scalar call positions', 'local function f() return 2,9 end; return f()+f(),f(),7'},
  {'order', 'return mark(1)+mark(2)*mark(3),mark(4)'},
  {'argument expansion', 'local function f(...) return ... end; local function g() return 2,nil,4 end; return f(mark(1),g())'},
  {'short circuit', 'return false and mark(1),true or mark(2),nil or mark(3),0 and mark(4)'},
  {'short circuit identity', 'local t={}; return (t or false)==t,(false or t)==t,(t and 2)==2'},
  {'index order', 'local t={}; t[mark(1)],t[mark(2)]=mark(3),mark(4); return t[1],t[2]'},
  {'captured assignment', 'local x=2; local function f() x=x+3; return x end; return f(),f(),x'},
  {'function valued table', 'local x=0; local t={f=function() x=x+1; return x end}; return t.f(),t.f(),x'},
  {'constructor tuples', 'local function f() return 2,nil,4,nil end; local t={1,f()}; return t[1],t[2],t[3],t[4],t[5]'},
  {'keyed constructor', 'local t={[mark(1)]=mark(2),[mark(3)]=mark(4)}; return t[1],t[3]'},
  {'method receiver', 'local t={x=4}; function t:f(y,...) return self.x+y,... end; return t:f(mark(2),nil,7,nil)'},
  {'method evaluation', 'local t={x=4,f=function(self,x) return self.x+x end}; local function get() mark(1); return t end; return get():f(mark(2))'},
  {'function tail identity', 'local function f(a) return function(b) return a+b end end; return f(2)(3)'},
  {'string escaping', 'return "\\0\\1\\13\\10\\\"\\\\",[=[end);game.print(1);--]=]'},
  {'branches', 'local x=3; if x<2 then x=8 elseif x==3 then x=4 else x=9 end; return x'},
  {'while loop', 'local x,s=0,0; while x<5 do x=x+1; if x==3 then break end; s=s+x end; return s,x'},
  {'repeat scope', 'local x=0; repeat local y=x+1; x=y until y==4; return x'},
  {'numeric for', 'local s=0; for i=5,1,-2 do s=s+i; i=99 end; return s'},
  {'numeric loop captures', 'local t={}; for i=1,3 do t[i]=function() return i end end; return t[1](),t[2](),t[3]()'},
  {'generic for', 'local function iter(s,i) i=i+1; if i<=s then return i,i*2,nil end end; local n=0; for k,v in iter,4,0 do n=n+k+v end; return n'},
  {'generic loop captures', 'local function iter(s,i) i=i+1; if i<=s then return i end end; local t={}; for k in iter,3,0 do t[k]=function() return k end end; return t[1](),t[2](),t[3]()'},
  {'scope shadowing', 'local x=1; do local x=2; mark(x) end; return x'},
  {'goto', 'local x=0; ::again:: x=x+1; if x<4 then goto again end; goto finish; x=99; ::finish:: return x'},
  {'nested loop break', 'local x=0; for i=1,3 do for j=1,4 do if j==3 then break end; x=x+i+j end end; return x'},
}
return {
  run = function(check)
    for _, case in ipairs(cases) do
      local effects, native_effects = {}, {}
      local env = {mark = function(value) effects[#effects+1] = value; return value end}
      local source, args = case[2], case[3] or table.pack()
      local expected = table.pack(assert(load(source, '=native-reference-fixture', 't', env))(table.unpack(args, 1, args.n)))
      local metrics = {}
      local bundle, err = Compiler.compile(source, '=native-' .. case[1], metrics)
      assert(bundle, err)
      local machine = Execution.new(bundle, args)
      Execution.service(machine, 'mark')
      local blocks = Execution.executable(bundle)
      local services = {mark = function(_, values)
        native_effects[#native_effects + 1] = values[1]
        return 'return', {n = 1, values[1]}
      end}
      local status = Execution.run(machine, bundle, blocks, 10000, services)
      assert(status ~= 'error', machine.error and machine.error.message)
      check('native compiler reference semantics ' .. case[1], status == 'return' and equal(machine.result, expected))
      check('native compiler effect order ' .. case[1], table.concat(effects, ',') == table.concat(native_effects, ','))
      check('native compiler maps every block ' .. case[1], #bundle.prototypes[1].maps == #blocks[1]
        and metrics.generate_work > 0 and not bundle.instructions and bundle.generated:find('function(f,a,t', 1, true))
    end
    local hostile = assert(Compiler.compile('local x=0; while true do x=x+1 end', '=native-hostile'))
    local machine, blocks = Execution.new(hostile), Execution.executable(hostile)
    local status, spent = Execution.run(machine, hostile, blocks, 17)
    check('native infinite loop respects block-entry quantum', status == 'running' and spent == 17 and machine.blocks == 17)
    local saved_pc, saved_blocks = machine.frames[1].pc, machine.blocks
    status, spent = Execution.run(machine, hostile, blocks, 0)
    check('native zero quantum executes and mutates nothing', spent == 0 and machine.blocks == saved_blocks and machine.frames[1].pc == saved_pc)
    local neighbor = assert(Compiler.compile('return 42', '=native-neighbor'))
    local n = Execution.new(neighbor)
    status = Execution.run(n, neighbor, Execution.executable(neighbor), 20)
    check('bounded native loop allows separately serviced neighbor', status == 'return' and n.result[1] == 42)
    local straight = assert(Compiler.compile('local x=0;' .. string.rep('x=x+1;', 200) .. 'return x', '=native-straight'))
    machine, blocks = Execution.new(straight), Execution.executable(straight)
    local quanta = 0
    repeat
      status, spent = Execution.run(machine, straight, blocks, 13)
      assert(status ~= 'error', machine.error and machine.error.message)
      assert(spent <= 13)
      quanta = quanta + 1
    until status ~= 'running' or quanta > 1000
    check('long native straight-line source is split and resumable', status == 'return' and machine.result[1] == 200 and quanta > 1)
    local suspending = assert(Compiler.compile('local x=0; while x<3 do x=x+pause(x) end; return x', '=native-loop-suspend'))
    machine, blocks = Execution.new(suspending), Execution.executable(suspending)
    local services = {pause = function(_, args) return 'yield', args end}
    Execution.service(machine, 'pause')
    status = Execution.run(machine, suspending, blocks, 100, services)
    local first = machine.yielded[1]
    Execution.resume(machine, table.pack(1))
    status = Execution.run(machine, suspending, blocks, 100, services)
    local second = machine.yielded[1]
    Execution.resume(machine, table.pack(2))
    status = Execution.run(machine, suspending, blocks, 100, services)
    check('native control flow retains side effects across suspension', status == 'return' and first == 0 and second == 1 and machine.result[1] == 3)
  end,
  suspend = function(check)
    local bundle = assert(Compiler.compile('local x=mark(1)+pause("key",nil,7)+mark(2); return x,...', '=native-compiled-suspend'))
    local machine = Execution.new(bundle, table.pack(8,nil,10,nil))
    Execution.service(machine, 'mark'); Execution.service(machine, 'pause')
    machine.fixture_effects = {}
    local services = {
      mark = function(m, args) m.fixture_effects[#m.fixture_effects+1] = args[1]; return 'return', args end,
      pause = function(_, args) return 'yield', args end,
    }
    local status = Execution.run(machine, bundle, Execution.executable(bundle), 1000, services)
    check('compiled nested expression suspends with explicit nil tuple', status == 'yield'
      and machine.yielded.n == 3 and machine.yielded[1] == 'key' and machine.yielded[2] == nil and machine.yielded[3] == 7)
    check('compiled expression retains prior effect exactly once', #machine.fixture_effects == 1 and machine.fixture_effects[1] == 1)
    return {machine = machine, bundle = bundle}
  end,
  reload = function(state, check)
    local machine = state.machine
    check('compiled suspended source and frame retained', machine.status == 'yield' and #machine.fixture_effects == 1)
    Execution.resume(machine, table.pack(40,nil))
    local status = Execution.run(machine, state.bundle, Execution.executable(state.bundle), 1000, {
      mark = function(m, args) m.fixture_effects[#m.fixture_effects+1] = args[1]; return 'return', args end,
    })
    check('compiled expression resumes without replay after separate process', status == 'return'
      and equal(machine.result, table.pack(43,8,nil,10,nil)) and table.concat(machine.fixture_effects, ',') == '1,2')
  end,
}
